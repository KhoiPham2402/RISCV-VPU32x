// =============================================================================
// tb_vga_capture.sv — Capture one VGA frame from riscv_vpu_top_fpga
//
// Flow:
//   1. Reset system
//   2. Backdoor-load a test pattern into DMEM Y-channel (word 12288–16383)
//   3. Wait for VS sync to align to frame boundary
//   4. Capture exactly 640×480 pixels (VGA_BLANK_N=1) to vga_capture.txt
//   5. Finish
//
// Test pattern written to Y-channel:
//   Rows  0–31 : horizontal white/black bars (row/8 alternating)
//   Rows 32–63 : vertical bars (col/8 alternating)
//   Rows 64–95 : diagonal gradient (row+col) % 256
//   Rows 96–127: solid ramp (col*2)
//
// Reconstruct image:
//   python sw/vga_reconstruct.py fpga/sim/vga_capture.txt
//
// Run from project root:
//   vsim -do fpga/sim/run_vga_capture.do
// =============================================================================
`timescale 1ns/1ps

module tb_vga_capture;

    // ─── Clock / Reset ──────────────────────────────────────────────────────
    logic clk = 0;
    always #10 clk = ~clk;   // 50 MHz
    logic reset;

    // ─── VGA output ─────────────────────────────────────────────────────────
    logic [7:0] VGA_R, VGA_G, VGA_B;
    logic       VGA_CLK, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N;

    // ─── DUT ────────────────────────────────────────────────────────────────
    riscv_vpu_top_fpga #(
        .UART_CLK_FREQ  (50_000_000),
        .UART_BAUD_RATE (115_200)
    ) dut (
        .i_clk       (clk),
        .i_reset     (reset),
        .i_io_sw     (32'b0),
        .uart_rx     (1'b1),   // UART idle — firmware will block at UART receive, which is fine
        .uart_tx     (),
        .vga_r       (VGA_R),   .vga_g      (VGA_G),  .vga_b       (VGA_B),
        .vga_clk     (VGA_CLK), .vga_hs     (VGA_HS), .vga_vs      (VGA_VS),
        .vga_blank_n (VGA_BLANK_N),
        .vga_sync_n  (VGA_SYNC_N),
        .o_io_ledr  (), .o_io_ledg (), .o_io_lcd  (),
        .o_io_hex0  (), .o_io_hex1 (), .o_io_hex2 (), .o_io_hex3 (),
        .o_io_hex4  (), .o_io_hex5 (), .o_io_hex6 (), .o_io_hex7 (),
        .o_pc_debug (), .o_insn_vld(),
        .o_vpu_cycles(), .o_vmask16(), .o_vpu_busy(), .o_fsm_state(),
        .o_wb_result_lane0(), .o_wb_result_lane1(),
        .o_wb_result_lane2(), .o_wb_result_lane3()
    );

    // ─── Backdoor load Y-channel test pattern ───────────────────────────────
    // DMEM word addr = 12288 + row*32 + col/4
    // Byte lane      = col % 4
    // dut.u_dmem.bank[lane].u.mem[word_addr] = Y_value
    task automatic load_test_pattern;
        logic [7:0] y_val;
        int word_addr;
        for (int row = 0; row < 128; row++) begin
            for (int col = 0; col < 128; col++) begin
                // 4-zone test pattern
                if (row < 32)        y_val = ((row / 8) % 2) ? 8'hFF : 8'h00;   // H-bars
                else if (row < 64)   y_val = ((col / 8) % 2) ? 8'hFF : 8'h00;   // V-bars
                else if (row < 96)   y_val = (row + col) % 256;                  // diagonal
                else                 y_val = col * 2;                             // ramp
                word_addr = 12288 + row * 32 + col / 4;
                case (col % 4)
                    0: dut.u_dmem.bank[0].u.mem[word_addr] = y_val;
                    1: dut.u_dmem.bank[1].u.mem[word_addr] = y_val;
                    2: dut.u_dmem.bank[2].u.mem[word_addr] = y_val;
                    3: dut.u_dmem.bank[3].u.mem[word_addr] = y_val;
                endcase
            end
        end
        $display("[TB] Test pattern loaded into DMEM Y-channel");
        $display("[TB]   Rows  0-31 : horizontal bars");
        $display("[TB]   Rows 32-63 : vertical bars");
        $display("[TB]   Rows 64-95 : diagonal gradient");
        $display("[TB]   Rows 96-127: left-to-right ramp");
    endtask

    // ─── VGA frame capture ──────────────────────────────────────────────────
    localparam int FRAME_W  = 640;
    localparam int FRAME_H  = 480;
    localparam int FRAME_PIX = FRAME_W * FRAME_H;

    integer     cap_fd;
    int         cap_pix;
    logic       capturing;

    // Pixel counter: log R,G,B on every active pixel
    always @(posedge VGA_CLK) begin
        if (capturing && VGA_BLANK_N) begin
            $fwrite(cap_fd, "%0d %0d %0d\n", VGA_R, VGA_G, VGA_B);
            cap_pix++;
            if (cap_pix >= FRAME_PIX) begin
                capturing = 1'b0;
            end
        end
    end

    // ─── Stimulus ────────────────────────────────────────────────────────────
    initial begin
        capturing = 1'b0;
        cap_pix   = 0;
        reset = 1'b1;
        repeat(8) @(posedge clk);
        reset = 1'b0;
        repeat(4) @(posedge clk);

        // Backdoor-load before simulation runs VGA output
        load_test_pattern();

        // Wait for PLL lock and VGA counters to start
        repeat(64) @(posedge clk);

        // Synchronise to start of frame: wait for VS falling edge (vc=490),
        // then VS rising edge (vc=492 = end of vsync), then capture the full
        // next active frame. VS period = 800*490 = 392000 pclk = ~15.7ms.
        @(negedge VGA_VS);
        @(posedge VGA_VS);

        // Open output file
        cap_fd = $fopen("fpga/sim/vga_capture.txt", "w");
        if (cap_fd == 0) begin
            $display("[TB] ERROR: cannot open vga_capture.txt");
            $finish;
        end
        $display("[TB] Capturing one VGA frame (%0d pixels)...", FRAME_PIX);
        capturing = 1'b1;

        // Wait until capture completes (one full frame worth of active pixels)
        wait (capturing == 1'b0);
        $fclose(cap_fd);
        $display("[TB] Capture complete — %0d pixels written to fpga/sim/vga_capture.txt",
                 cap_pix);
        $display("[TB] Run: python sw/vga_reconstruct.py fpga/sim/vga_capture.txt");

        // Sample check: read a few pixels directly from DMEM to verify
        $display("[TB] Spot check (row=0):");
        for (int col = 0; col < 8; col++) begin
            automatic int w = 12288 + col / 4;
            automatic int y_rd;
            case (col % 4)
                0: y_rd = dut.u_dmem.bank[0].u.mem[w];
                1: y_rd = dut.u_dmem.bank[1].u.mem[w];
                2: y_rd = dut.u_dmem.bank[2].u.mem[w];
                3: y_rd = dut.u_dmem.bank[3].u.mem[w];
            endcase
            $display("[TB]   Y[0][%0d] = 0x%02h (%0d) — expect %0d",
                     col, y_rd, y_rd, (col < 32) ? 0 : 0); // row 0 = H-bar → 0x00
        end

        $finish;
    end

    // Safety watchdog
    initial begin
        #200_000_000; // 200 ms — two full frames
        $display("[TB] WATCHDOG: simulation timeout");
        $finish;
    end

endmodule
