`timescale 1ns/1ps
// tb_lena_mini.sv — Fast end-to-end UART→VPU→ACK simulation
//
// Loads uart_lena_mini.hex (16-pixel firmware) and sends 3×16 bytes via UART.
// VPU computes BT.601 Y channel, firmware replies ACK 0xAA.
//
// Test input: R=0x64(100), G=0x96(150), B=0x32(50) for all 16 pixels
// Expected Y = floor(100×77/256) + floor(150×150/256) + floor(50×29/256)
//           = 30 + 87 + 5 = 122 = 0x7A
// Total UART bytes: 48 × 10 bits × 200 ns = 96 µs sim time → seconds wall time

module tb_lena_mini;

    localparam int CLK_FREQ = 50_000_000;
    localparam int SIM_BAUD = 5_000_000;   // baud_div = 9, bit period = 10 cycles
    localparam int CLK_HALF = 10;          // ns (50 MHz)
    localparam int BIT_NS   = 1_000_000_000 / SIM_BAUD;  // 200 ns

    // ── DUT signals ───────────────────────────────────────────────────────────
    logic clk, reset;
    logic uart_rx_drv;
    logic uart_tx_mon;

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
        .o_io_ledr        (), .o_io_ledg  (), .o_io_lcd   (),
        .o_io_hex0        (), .o_io_hex1  (), .o_io_hex2  (),
        .o_io_hex3        (), .o_io_hex4  (), .o_io_hex5  (),
        .o_io_hex6        (), .o_io_hex7  (),
        .vga_r            (), .vga_g      (), .vga_b      (),
        .vga_clk          (), .vga_hs     (), .vga_vs     (),
        .vga_blank_n      (), .vga_sync_n (),
        .o_pc_debug       (), .o_insn_vld (),
        .o_vpu_cycles     (), .o_vmask16  (),
        .o_vpu_busy       (), .o_fsm_state(),
        .o_wb_result_lane0(), .o_wb_result_lane1(),
        .o_wb_result_lane2(), .o_wb_result_lane3()
    );

    initial clk = 1'b0;
    always #(CLK_HALF) clk = ~clk;

    // ── UART send one 8N1 byte to DUT RX ─────────────────────────────────────
    task automatic uart_send(input logic [7:0] data);
        int i;
        uart_rx_drv = 1'b0; #(BIT_NS);
        for (i = 0; i < 8; i++) begin uart_rx_drv = data[i]; #(BIT_NS); end
        uart_rx_drv = 1'b1; #(BIT_NS);
    endtask

    // ── UART receive one 8N1 byte from DUT TX (10 ms timeout) ────────────────
    task automatic uart_recv(output logic [7:0] data, output logic ok);
        int i;
        data = 8'hFF; ok = 1'b0;
        fork
            begin : rx
                @(negedge uart_tx_mon);
                #(BIT_NS / 2);
                for (i = 0; i < 8; i++) begin #(BIT_NS); data[i] = uart_tx_mon; end
                ok = 1'b1;
            end
            begin : tmo; #(10_000_000); end  // 10 ms — covers VPU compute
        join_any
        disable fork;
    endtask

    // ── Main ─────────────────────────────────────────────────────────────────
    logic [7:0] rx_byte;
    logic       rx_ok;

    initial begin
        uart_rx_drv = 1'b1;
        reset       = 1'b1;
        repeat (20) @(posedge clk);
        reset = 1'b0;
        repeat (40) @(posedge clk);

        $display("=== UART→VPU mini lena test (SIM_BAUD=%0d) ===", SIM_BAUD);
        $display("    Sending R plane (16 bytes, R=0x64=100)...");
        for (int p = 0; p < 16; p++) uart_send(8'h64);

        $display("    Sending G plane (16 bytes, G=0x96=150)...");
        for (int p = 0; p < 16; p++) uart_send(8'h96);

        $display("    Sending B plane (16 bytes, B=0x32=50)...");
        for (int p = 0; p < 16; p++) uart_send(8'h32);

        $display("    All 48 bytes sent. Waiting for ACK 0xAA...");
        uart_recv(rx_byte, rx_ok);

        if (!rx_ok) begin
            $display("[FAIL] Timeout — no ACK received within 10 ms.");
            $display("       Check: VPU dispatch, VLSU store, firmware loop.");
        end else if (rx_byte === 8'hAA) begin
            $display("[PASS] ACK=0x%02X received.", rx_byte);
            $display("       Expected Y = 30+87+5 = 122 = 0x7A per pixel");
            $display("         R×77/256 = %0d, G×150/256 = %0d, B×29/256 = %0d",
                     (100*77)/256, (150*150)/256, (50*29)/256);
        end else begin
            $display("[FAIL] ACK=0x%02X (expected 0xAA).", rx_byte);
        end

        #(1000);
        $finish;
    end

    // ── Global watchdog (30 ms) ───────────────────────────────────────────────
    initial begin
        #(30_000_000);
        $display("[TIMEOUT] Simulation stuck at %0t ns.", $time);
        $finish;
    end

endmodule
