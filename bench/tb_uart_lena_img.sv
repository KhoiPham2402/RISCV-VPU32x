// =============================================================================
// tb_uart_lena_img.sv  —  Full 128×128 Lena via UART → VPU → image output
//
// Sends actual Lena R/G/B pixel data from lena_dmem_init.hex via UART RX,
// waits for firmware ACK, then dumps the full 64KB DMEM to a hex file that
// reconstruct.py can convert to a PNG.
//
// Firmware loaded: uart_lena.hex (imem.hex in project root)
//   Receives 3×16384 bytes (R, G, B planes), runs VPU BT.601, sends ACK 0xAA.
//
// Timing: CLK_FREQ=14_745_600 / BAUD_RATE=115_200 → baud_div=7 → 8 clk/bit
//   80 cycles/byte × 49152 bytes ≈ 3.93 M cycles UART Rx.
//   Expect total simulation ≈ 4.0 M cycles.
//
// After simulation:
//   python sw/benchmarks/lena_gray/reconstruct.py \
//          sw/benchmarks/lena_gray/v3_output/lena_dmem_out_uart.hex
// =============================================================================

module tb_uart_lena_img;

    // ── Baud timing ──────────────────────────────────────────────────────────
    localparam int CLK_FREQ   = 14_745_600;
    localparam int BAUD_RATE  = 115_200;
    localparam int BAUD_DIV   = CLK_FREQ / (16 * BAUD_RATE) - 1;  // 7
    localparam int BIT_CYCLES = BAUD_DIV + 1;                      // 8 clk/bit

    localparam int N_PIXELS   = 16384;    // 128×128
    localparam int TIMEOUT    = 5_000_000;
    localparam string DMEM_OUT = "sw/benchmarks/lena_gray/v3_output/lena_dmem_out_uart.hex";

    // ── DUT signals ──────────────────────────────────────────────────────────
    logic        clk;
    logic        reset;
    logic        uart_rx_drv;
    logic        uart_tx_obs;

    riscv_vpu_top_v4 #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .i_clk           (clk),
        .i_reset         (reset),
        .i_io_sw         (32'h0),
        .o_io_ledr       (),
        .o_io_ledg       (),
        .o_io_lcd        (),
        .o_io_hex0       (),
        .o_io_hex1       (),
        .o_io_hex2       (),
        .o_io_hex3       (),
        .o_io_hex4       (),
        .o_io_hex5       (),
        .o_io_hex6       (),
        .o_io_hex7       (),
        .o_pc_debug      (),
        .o_insn_vld      (),
        .o_vpu_cycles    (),
        .o_vmask16       (),
        .o_vpu_busy      (),
        .o_fsm_state     (),
        .o_wb_result_lane0(),
        .o_wb_result_lane1(),
        .o_wb_result_lane2(),
        .o_wb_result_lane3(),
        .uart_rx         (uart_rx_drv),
        .uart_tx         (uart_tx_obs)
    );

    // ── Clock (100 MHz wall; baud timing is cycle-counted) ───────────────────
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ── Pixel data (loaded from lena_dmem_init.hex) ──────────────────────────
    // Layout: words 0–4095 = R, 4096–8191 = G, 8192–12287 = B  (little-endian)
    logic [31:0] dmem_init [0:16383];

    // ── UART send tasks ───────────────────────────────────────────────────────
    task automatic uart_send_bit(input logic val);
        uart_rx_drv = val;
        repeat(BIT_CYCLES) @(posedge clk);
    endtask

    task automatic uart_send_byte(input logic [7:0] data);
        integer b;
        uart_send_bit(1'b0);
        for (b = 0; b < 8; b++)
            uart_send_bit(data[b]);
        uart_send_bit(1'b1);
    endtask

    // ── UART receive task ─────────────────────────────────────────────────────
    task automatic uart_recv_byte(output logic [7:0] data);
        integer b;
        @(negedge uart_tx_obs);
        repeat(BIT_CYCLES + BIT_CYCLES/2) @(posedge clk);
        for (b = 0; b < 8; b++) begin
            data[b] = uart_tx_obs;
            repeat(BIT_CYCLES) @(posedge clk);
        end
        repeat(BIT_CYCLES/2) @(posedge clk);
    endtask

    // ── Send one full channel (16384 bytes) ───────────────────────────────────
    // channel_start: word offset in dmem_init (0=R, 4096=G, 8192=B)
    task automatic send_channel(input int channel_start, input string name);
        logic [7:0] pixel;
        $display("[INFO] Sending %s channel (%0d bytes)...", name, N_PIXELS);
        for (int i = 0; i < N_PIXELS; i++) begin
            // little-endian: byte i is in word[i/4] bits [(i%4)*8 +: 8]
            pixel = dmem_init[channel_start + i/4][8*(i%4) +: 8];
            uart_send_byte(pixel);
        end
        $display("[INFO] %s channel done.", name);
    endtask

    // ── Dump full DMEM to hex file ────────────────────────────────────────────
    task automatic dump_dmem();
        int fd;
        fd = $fopen(DMEM_OUT, "w");
        if (fd == 0) begin
            $display("[ERROR] Cannot open output file: %s", DMEM_OUT);
            return;
        end
        for (int w = 0; w < 16384; w++)
            $fwrite(fd, "%08x\n", dut.u_dmem.mem[w]);
        $fclose(fd);
        $display("[INFO] DMEM dumped to %s", DMEM_OUT);
    endtask

    // ── Main stimulus ─────────────────────────────────────────────────────────
    logic [7:0] ack_byte;

    initial begin
        $readmemh("sw/benchmarks/lena_gray/lena_dmem_init.hex", dmem_init);
        $display("[INFO] Loaded lena_dmem_init.hex (%0d words)", $size(dmem_init));
        $display("[INFO] R[0]=%02x G[0]=%02x B[0]=%02x",
                 dmem_init[0][7:0], dmem_init[4096][7:0], dmem_init[8192][7:0]);

        uart_rx_drv = 1'b1;
        reset       = 1'b1;
        repeat(10) @(posedge clk);
        reset = 1'b0;
        repeat(5) @(posedge clk);

        // ── Send R, G, B planes ──────────────────────────────────────────────
        send_channel(0,    "R");
        send_channel(4096, "G");
        send_channel(8192, "B");

        // ── Wait for ACK (firmware sends 0xAA when done) ─────────────────────
        $display("[INFO] Waiting for ACK byte on uart_tx...");
        uart_recv_byte(ack_byte);

        if (ack_byte === 8'hAA)
            $display("[PASS] ACK received: 0x%02X", ack_byte);
        else
            $display("[FAIL] Bad ACK: got 0x%02X, expected 0xAA", ack_byte);

        // ── Dump DMEM and produce image ───────────────────────────────────────
        dump_dmem();

        // Quick sanity: check first 4 Y pixels (word 12288)
        $display("[INFO] Y[3:0] = %02x %02x %02x %02x",
                 dut.u_dmem.mem[12288][7:0],
                 dut.u_dmem.mem[12288][15:8],
                 dut.u_dmem.mem[12288][23:16],
                 dut.u_dmem.mem[12288][31:24]);

        $display("");
        $display("=== Simulation complete ===");
        $display("Run: python sw/benchmarks/lena_gray/reconstruct.py %s", DMEM_OUT);
        $finish;
    end

    // ── Global timeout ────────────────────────────────────────────────────────
    initial begin
        repeat(TIMEOUT) @(posedge clk);
        $display("[FAIL] Global timeout at %0d cycles", TIMEOUT);
        dump_dmem();
        $finish;
    end

endmodule
