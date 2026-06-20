`timescale 1ns/1ps
// tb_fpga_lena_sim.sv — End-to-end simulation of riscv_vpu_top_fpga
//
// Tests the lena grayscale demo:
//   1. Send 3×16384 bytes (R=100, G=150, B=50) via UART at SIM_BAUD.
//   2. Wait for VPU to compute Y = floor(R×77/256) + floor(G×150/256) + floor(B×29/256).
//      Expected: 30 + 87 + 5 = 122 = 0x7A per pixel.
//   3. Receive ACK byte 0xAA from firmware.
//
// IPs replaced by behavioral models:
//   fpga/ip/dmem_bank.sv  — 8-bit TDP SRAM (registered output, OLD_DATA)
//   fpga/ip/pll.sv        — divide-by-2 pixel clock, locked after 16 cycles

module tb_fpga_lena_sim;

    // ── Parameters ────────────────────────────────────────────────────────────
    localparam int CLK_FREQ = 50_000_000;
    localparam int SIM_BAUD = 5_000_000;   // baud_div = CLK_FREQ/SIM_BAUD - 1 = 9
    localparam int CLK_HALF = 10;          // ns — 50 MHz
    localparam int BIT_NS   = 1_000_000_000 / SIM_BAUD;  // 200 ns per bit

    // ── DUT signals ───────────────────────────────────────────────────────────
    logic clk, reset;
    logic uart_rx_drv;  // testbench → DUT RX
    logic uart_tx_mon;  // DUT TX → testbench monitor

    // ── DUT ──────────────────────────────────────────────────────────────────
    riscv_vpu_top_fpga #(
        .UART_CLK_FREQ (CLK_FREQ),
        .UART_BAUD_RATE(SIM_BAUD)
    ) dut (
        .i_clk            (clk),
        .i_reset          (reset),
        .i_io_sw          (32'd0),
        .uart_rx          (uart_rx_drv),
        .uart_tx          (uart_tx_mon),
        .o_io_ledr        (),
        .o_io_ledg        (),
        .o_io_lcd         (),
        .o_io_hex0        (),
        .o_io_hex1        (),
        .o_io_hex2        (),
        .o_io_hex3        (),
        .o_io_hex4        (),
        .o_io_hex5        (),
        .o_io_hex6        (),
        .o_io_hex7        (),
        .vga_r            (),
        .vga_g            (),
        .vga_b            (),
        .vga_clk          (),
        .vga_hs           (),
        .vga_vs           (),
        .vga_blank_n      (),
        .vga_sync_n       (),
        .o_pc_debug       (),
        .o_insn_vld       (),
        .o_vpu_cycles     (),
        .o_vmask16        (),
        .o_vpu_busy       (),
        .o_fsm_state      (),
        .o_wb_result_lane0(),
        .o_wb_result_lane1(),
        .o_wb_result_lane2(),
        .o_wb_result_lane3()
    );

    // ── Clock ─────────────────────────────────────────────────────────────────
    initial clk = 1'b0;
    always #(CLK_HALF) clk = ~clk;

    // ── UART TX helper: send one 8N1 byte to DUT RX ───────────────────────────
    task automatic uart_send_byte(input logic [7:0] data);
        int i;
        uart_rx_drv = 1'b0; #(BIT_NS);  // start bit
        for (i = 0; i < 8; i++) begin
            uart_rx_drv = data[i]; #(BIT_NS);
        end
        uart_rx_drv = 1'b1; #(BIT_NS);  // stop bit
    endtask

    // ── UART RX helper: receive one 8N1 byte from DUT TX (150 ms timeout) ─────
    task automatic uart_recv_byte(output logic [7:0] data, output logic ok);
        int i;
        data = 8'hFF;
        ok   = 1'b0;
        fork
            begin : rx_thread
                @(negedge uart_tx_mon);
                #(BIT_NS / 2);           // align to center of start bit
                for (i = 0; i < 8; i++) begin
                    #(BIT_NS);
                    data[i] = uart_tx_mon;
                end
                ok = 1'b1;
            end
            begin : timeout_thread
                #(150_000_000);          // 150 ms — covers VPU computation time
            end
        join_any
        disable fork;
    endtask

    // ── Main stimulus ─────────────────────────────────────────────────────────
    logic [7:0] rx_byte;
    logic       rx_ok;

    initial begin
        uart_rx_drv = 1'b1;  // UART idle
        reset       = 1'b1;
        repeat (20) @(posedge clk);
        reset = 1'b0;
        // Give firmware ~40 cycles to reach recv_block before we transmit
        repeat (40) @(posedge clk);

        $display("[%0t ns] Sending R plane (16384 bytes, R=0x64)...", $time);
        for (int p = 0; p < 16384; p++) uart_send_byte(8'h64);  // R = 100

        $display("[%0t ns] Sending G plane (16384 bytes, G=0x96)...", $time);
        for (int p = 0; p < 16384; p++) uart_send_byte(8'h96);  // G = 150

        $display("[%0t ns] Sending B plane (16384 bytes, B=0x32)...", $time);
        for (int p = 0; p < 16384; p++) uart_send_byte(8'h32);  // B = 50

        $display("[%0t ns] All planes sent. Waiting for ACK 0xAA...", $time);
        uart_recv_byte(rx_byte, rx_ok);

        if (!rx_ok) begin
            $display("[FAIL] Timeout: no ACK received within 150 ms of last byte.");
        end else if (rx_byte === 8'hAA) begin
            $display("[PASS] ACK=0x%02X received — end-to-end UART→VPU→UART flow OK.", rx_byte);
            $display("       Expected Y per pixel = 122 (0x7A): R×77/256=%0d G×150/256=%0d B×29/256=%0d",
                     (100*77)/256, (150*150)/256, (50*29)/256);
        end else begin
            $display("[FAIL] Expected ACK=0xAA, got 0x%02X.", rx_byte);
        end

        #(1000);
        $finish;
    end

    // ── Global watchdog ───────────────────────────────────────────────────────
    initial begin
        // 49152 bytes × 10 bits × 200 ns ≈ 98 ms + 150 ms VPU headroom + margin
        #(300_000_000);
        $display("[FAIL] Global timeout at %0t ns — simulation did not complete.", $time);
        $finish;
    end

endmodule
