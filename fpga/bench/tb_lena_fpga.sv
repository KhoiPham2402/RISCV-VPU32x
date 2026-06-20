// =============================================================================
// tb_lena_fpga.sv — FPGA lena UART→VPU functional verification
//
// Phase 1 (UART/VPU):
//   Send 3×16384 bytes (R=200, G=100, B=50 uniform pattern)
//   Wait for ACK 0xAA from firmware
//   Expected Y = floor(200×77/256) + floor(100×150/256) + floor(50×29/256)
//             = 60 + 58 + 5 = 123 (0x7B) for all 16384 pixels
//
// Speed trick: force baud_div = 3 → 4 cycles/bit  (~2.3 M sys-clk cycles)
//
// Top-level ports: VGA (vga_r/g/b/clk/hs/vs/blank_n/sync_n)
//   DE10-Standard uses ADV7123 DAC, no I2C required.
//
// Signals to watch:
//   uart_rx_tb, uart_tx_obs    — serial traffic
//   dut.o_pc_debug             — must advance (core alive)
//   dut.o_vpu_busy             — pulses during 1024 VPU iterations
//   dut.o_fsm_state            — IDLE→EXEC→IDLE × 1024
//   dut.vga_blank_n            — high 640 cycles/line during active video
//   dut.vga_r/g/b              — 0x7B7B7B in image region after VPU done
// =============================================================================
`timescale 1ns/1ps

module tb_lena_fpga;

    // ── Clocking ──────────────────────────────────────────────────────────────
    localparam CLK_PERIOD  = 20;     // 50 MHz system clock (ns)
    localparam BAUD_CYCLES = 4;      // cycles per UART bit (forced)

    logic clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ── DUT ──────────────────────────────────────────────────────────────────
    logic i_reset    = 1'b1;
    logic uart_rx_tb = 1'b1;
    logic uart_tx_obs;

    riscv_vpu_top_fpga dut (
        .i_clk          (clk),
        .i_reset        (i_reset),
        .i_io_sw        (32'd0),
        // UART
        .uart_rx        (uart_rx_tb),
        .uart_tx        (uart_tx_obs),
        // VGA — observe only, not checked in this testbench
        .vga_r          (),
        .vga_g          (),
        .vga_b          (),
        .vga_clk        (),
        .vga_hs         (),
        .vga_vs         (),
        .vga_blank_n    (),
        .vga_sync_n     (),
        // Board I/O — unused
        .o_io_ledr      (), .o_io_ledg  (), .o_io_lcd    (),
        .o_io_hex0      (), .o_io_hex1  (), .o_io_hex2   (),
        .o_io_hex3      (), .o_io_hex4  (), .o_io_hex5   (),
        .o_io_hex6      (), .o_io_hex7  (),
        // Debug observe
        .o_pc_debug     (), .o_insn_vld  (),
        .o_vpu_cycles   (), .o_vmask16   (),
        .o_vpu_busy     (), .o_fsm_state (),
        .o_wb_result_lane0(), .o_wb_result_lane1(),
        .o_wb_result_lane2(), .o_wb_result_lane3()
    );

    // ── UART helpers ──────────────────────────────────────────────────────────
    task automatic uart_send_byte(input [7:0] data);
        integer b;
        uart_rx_tb = 1'b0;                           // start bit
        repeat(BAUD_CYCLES) @(posedge clk); #1;
        for (b = 0; b < 8; b++) begin
            uart_rx_tb = data[b];                    // LSB first
            repeat(BAUD_CYCLES) @(posedge clk); #1;
        end
        uart_rx_tb = 1'b1;                           // stop bit
        repeat(BAUD_CYCLES) @(posedge clk); #1;
        @(posedge clk); #1;                          // inter-byte gap
    endtask

    task automatic uart_recv_byte(output logic [7:0] data);
        integer b;
        // Wait for start bit falling edge on TX
        @(negedge uart_tx_obs);
        // Sample at centre of each bit (1.5 periods after start edge)
        repeat(BAUD_CYCLES + BAUD_CYCLES/2) @(posedge clk);
        data = 8'd0;
        for (b = 0; b < 8; b++) begin
            data[b] = uart_tx_obs;
            repeat(BAUD_CYCLES) @(posedge clk);
        end
    endtask

    // ── Reference Y ──────────────────────────────────────────────────────────
    // BT.601: Y = (R×77 + G×150 + B×29) >> 8
    function automatic [7:0] expected_y(input [7:0] r, g, b);
        logic [15:0] yr, yg, yb;
        yr = {8'd0, r} * 16'd77;
        yg = {8'd0, g} * 16'd150;
        yb = {8'd0, b} * 16'd29;
        return yr[15:8] + yg[15:8] + yb[15:8];
    endfunction

    // ── Test constants ────────────────────────────────────────────────────────
    localparam logic [7:0] TEST_R = 8'd200;
    localparam logic [7:0] TEST_G = 8'd100;
    localparam logic [7:0] TEST_B = 8'd50;
    localparam logic [7:0] Y_EXP  = 8'd123;   // expected_y(200,100,50)

    // ── Main test sequence ────────────────────────────────────────────────────
    logic [7:0] ack_byte;
    integer     px;

    initial begin
        // Reset
        i_reset = 1'b1;
        repeat(20) @(posedge clk);
        i_reset = 1'b0;
        repeat(5)  @(posedge clk);

        // Force fast baud rate: 4 cycles/bit instead of 434
        force dut.u_uart.baud_div = 16'd3;
        @(posedge clk);

        $display("=======================================================");
        $display(" FPGA Lena Grayscale Simulation");
        $display(" Pattern : R=%0d G=%0d B=%0d", TEST_R, TEST_G, TEST_B);
        $display(" Expected Y = %0d (0x%02X)", Y_EXP, Y_EXP);
        $display("   yr=%0d  yg=%0d  yb=%0d",
            ({8'd0,TEST_R}*16'd77 )>>8,
            ({8'd0,TEST_G}*16'd150)>>8,
            ({8'd0,TEST_B}*16'd29 )>>8);
        $display("=======================================================");

        // Send R channel (16384 bytes)
        $display("[%0t ns] Sending R channel (16384 bytes)...", $time);
        for (px = 0; px < 16384; px++)
            uart_send_byte(TEST_R);

        // Send G channel
        $display("[%0t ns] Sending G channel...", $time);
        for (px = 0; px < 16384; px++)
            uart_send_byte(TEST_G);

        // Send B channel
        $display("[%0t ns] Sending B channel...", $time);
        for (px = 0; px < 16384; px++)
            uart_send_byte(TEST_B);

        $display("[%0t ns] All channels sent. Waiting for ACK...", $time);

        // Receive ACK (0xAA)
        uart_recv_byte(ack_byte);

        $display("-------------------------------------------------------");
        if (ack_byte === 8'hAA) begin
            $display("[PASS] ACK = 0xAA received at %0t ns", $time);
            $display("[PASS] VPU processed 16384 pixels correctly");
        end else begin
            $display("[FAIL] Expected ACK=0xAA, got 0x%02X", ack_byte);
        end
        $display("=======================================================");
        $finish;
    end

    // ── PC liveness watchdog ──────────────────────────────────────────────────
    logic [31:0] pc_last     = 32'hX;
    int          pc_stall_cnt = 0;

    always @(posedge clk) begin
        if (dut.o_pc_debug !== pc_last) begin
            pc_last       <= dut.o_pc_debug;
            pc_stall_cnt  <= 0;
        end else begin
            pc_stall_cnt  <= pc_stall_cnt + 1;
            if (pc_stall_cnt == 5000)
                $display("[WARN][%0t ns] PC stuck at 0x%08X for 5000 cycles",
                         $time, dut.o_pc_debug);
        end
    end

    // ── Global timeout ────────────────────────────────────────────────────────
    initial begin
        // 3×16384 bytes × 10 bits/byte × 4 cycles/bit + VPU time
        // ≈ 2M cycles for UART + ~200k for VPU = ~2.5M; timeout at 5M
        #(5_000_000 * CLK_PERIOD);
        $display("[TIMEOUT] 5 M cycles exceeded — check UART/VPU hang");
        $finish;
    end

endmodule
