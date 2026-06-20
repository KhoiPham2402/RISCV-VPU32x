`timescale 1ns/1ps
// tb_uart_loopback.sv — Standalone UART RX+TX verification
//
// Loads uart_loopback.hex firmware into IMEM. Sends bytes via UART and
// checks that the DUT replies with (sent_byte + 1) mod 256.
//
// Critical test cases (covering the old sampling bug):
//   0x64 (bit7=0, R=100) → expect 0x65
//   0x32 (bit7=0, B=50)  → expect 0x33
//   0x00                 → expect 0x01
//   0x7F                 → expect 0x80
//   0xFF                 → expect 0x00
//   0x96 (bit7=1, G=150) → expect 0x97

module tb_uart_loopback;

    localparam int CLK_FREQ  = 50_000_000;
    localparam int SIM_BAUD  = 5_000_000;   // baud_div = 9, bit period = 10 cycles
    localparam int CLK_HALF  = 10;          // ns (50 MHz)
    localparam int BIT_NS    = 1_000_000_000 / SIM_BAUD;  // 200 ns

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
        .o_io_ledr        (),  .o_io_ledg  (),  .o_io_lcd   (),
        .o_io_hex0        (),  .o_io_hex1  (),  .o_io_hex2  (),
        .o_io_hex3        (),  .o_io_hex4  (),  .o_io_hex5  (),
        .o_io_hex6        (),  .o_io_hex7  (),
        .vga_r            (),  .vga_g      (),  .vga_b      (),
        .vga_clk          (),  .vga_hs     (),  .vga_vs     (),
        .vga_blank_n      (),  .vga_sync_n (),
        .o_pc_debug       (),  .o_insn_vld (),
        .o_vpu_cycles     (),  .o_vmask16  (),
        .o_vpu_busy       (),  .o_fsm_state(),
        .o_wb_result_lane0(), .o_wb_result_lane1(),
        .o_wb_result_lane2(), .o_wb_result_lane3()
    );

    initial clk = 1'b0;
    always #(CLK_HALF) clk = ~clk;

    // ── UART helpers ──────────────────────────────────────────────────────────
    task automatic uart_send(input logic [7:0] data);
        int i;
        uart_rx_drv = 1'b0; #(BIT_NS);
        for (i = 0; i < 8; i++) begin uart_rx_drv = data[i]; #(BIT_NS); end
        uart_rx_drv = 1'b1; #(BIT_NS);
    endtask

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
            begin : tmo; #(5_000_000); end  // 5 ms timeout per byte
        join_any
        disable fork;
    endtask

    // ── Test runner ───────────────────────────────────────────────────────────
    int pass_cnt, fail_cnt;

    task automatic check_byte(input logic [7:0] send_val);
        logic [7:0] rx_byte;
        logic       rx_ok;
        logic [7:0] expected;
        expected = send_val + 8'd1;
        uart_send(send_val);
        uart_recv(rx_byte, rx_ok);
        if (!rx_ok) begin
            $display("[FAIL] send=0x%02X : timeout — no response", send_val);
            fail_cnt++;
        end else if (rx_byte === expected) begin
            $display("[PASS] send=0x%02X → recv=0x%02X (expect 0x%02X)", send_val, rx_byte, expected);
            pass_cnt++;
        end else begin
            $display("[FAIL] send=0x%02X → recv=0x%02X (expect 0x%02X)", send_val, rx_byte, expected);
            fail_cnt++;
        end
    endtask

    // ── Main ─────────────────────────────────────────────────────────────────
    initial begin
        pass_cnt = 0; fail_cnt = 0;
        uart_rx_drv = 1'b1;
        reset = 1'b1;
        repeat (20) @(posedge clk);
        reset = 1'b0;
        repeat (40) @(posedge clk);

        $display("=== UART loopback test (SIM_BAUD=%0d) ===", SIM_BAUD);

        // Critical cases: bytes with bit7=0 failed with old half-bit sampling
        check_byte(8'h64);   // R=100, bit7=0  ← was broken before fix
        check_byte(8'h32);   // B=50,  bit7=0
        check_byte(8'h00);   // zero
        check_byte(8'h7F);   // 127, bit7=0 → expect 0x80
        check_byte(8'h96);   // G=150, bit7=1 (worked before fix too)
        check_byte(8'hFF);   // 255 → expect 0x00 (wrap)
        check_byte(8'hAA);   // 0xAA → expect 0xAB
        check_byte(8'h55);   // alternating bits

        $display("=== RESULT: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("[ALL PASS] UART RX+TX working correctly.");
        else
            $display("[FAILED] Check sampling fix in uart.sv line 138.");

        #(1000);
        $finish;
    end

    initial begin
        #(100_000_000);   // 100 ms global timeout
        $display("[TIMEOUT] Simulation did not complete — hung in rx_wait?");
        $finish;
    end

endmodule
