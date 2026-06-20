// =============================================================================
// tb_uart_loopback_system.sv — Full FPGA system UART loopback test
//
// Loads uart_loopback.hex into IMEM (firmware: receive byte → echo same byte).
// Testbench drives uart_rx, monitors uart_tx, verifies echo.
//
// Uses SIM_BAUD = 5 Mbaud (not 115200) for fast simulation:
//   bit period = 200 ns = 10 system clock cycles
//   one byte  = 2000 ns  (vs 86800 ns at 115200)
//
// Run: vsim -c -do fpga/sim/run_uart_loopback.do
// =============================================================================
`timescale 1ns/1ps

module tb_uart_loopback_system;

    localparam int CLK_FREQ  = 50_000_000;
    localparam int SIM_BAUD  = 5_000_000;   // baud_div = 9
    localparam int CLK_HALF  = 10;          // ns — 50 MHz
    localparam int BIT_NS    = 1_000_000_000 / SIM_BAUD;  // 200 ns per bit

    parameter string IMEM_HEX = "C:\\CapstoneProject2\\riscv_vpu\\uart_loopback.hex";

    // ─── Clock / Reset ──────────────────────────────────────────────────────
    logic clk = 0;
    always #(CLK_HALF) clk = ~clk;
    logic reset;

    // ─── UART wires ─────────────────────────────────────────────────────────
    logic uart_rx_tb;    // testbench drives FPGA RX
    logic uart_tx_fpga;  // FPGA TX → testbench monitors

    // ─── DUT ────────────────────────────────────────────────────────────────
    riscv_vpu_top_fpga #(
        .UART_CLK_FREQ  (CLK_FREQ),
        .UART_BAUD_RATE (SIM_BAUD)
    ) dut (
        .i_clk            (clk),
        .i_reset          (reset),
        .i_io_sw          (32'b0),
        .uart_rx          (uart_rx_tb),
        .uart_tx          (uart_tx_fpga),
        // leave all other outputs unconnected for UART test
        .vga_r(), .vga_g(), .vga_b(), .vga_clk(),
        .vga_hs(), .vga_vs(), .vga_blank_n(), .vga_sync_n(),
        .o_io_ledr(), .o_io_ledg(), .o_io_lcd(),
        .o_io_hex0(), .o_io_hex1(), .o_io_hex2(), .o_io_hex3(),
        .o_io_hex4(), .o_io_hex5(), .o_io_hex6(), .o_io_hex7(),
        .o_pc_debug(), .o_insn_vld(), .o_vpu_cycles(), .o_vmask16(),
        .o_vpu_busy(), .o_fsm_state(),
        .o_wb_result_lane0(), .o_wb_result_lane1(),
        .o_wb_result_lane2(), .o_wb_result_lane3()
    );

    // ─── UART send: drive FPGA RX with 8N1 frame ────────────────────────────
    task automatic uart_send(input [7:0] data);
        uart_rx_tb = 1'b0; #(BIT_NS);   // start bit
        for (int i = 0; i < 8; i++) begin
            uart_rx_tb = data[i]; #(BIT_NS);
        end
        uart_rx_tb = 1'b1; #(BIT_NS);   // stop bit
    endtask

    // ─── UART receive: sample FPGA TX, 10 ms timeout ────────────────────────
    task automatic uart_recv(output logic [7:0] data, output logic ok);
        data = 8'hFF;
        ok   = 1'b0;
        fork
            begin : rx_thread
                @(negedge uart_tx_fpga);        // start bit falling edge
                #(BIT_NS / 2);                  // center of start bit
                if (uart_tx_fpga !== 1'b0) disable rx_thread;  // false start
                for (int i = 0; i < 8; i++) begin
                    #(BIT_NS);
                    data[i] = uart_tx_fpga;
                end
                #(BIT_NS);                      // stop bit
                ok = 1'b1;
            end
            begin : timeout_thread
                #(10_000_000);                  // 10 ms timeout
            end
        join_any
        disable fork;
    endtask

    // ─── Stimulus ────────────────────────────────────────────────────────────
    logic [7:0] rx_data;
    logic       rx_ok;
    int         pass_cnt, fail_cnt;

    // Test bytes: normal, boundary, alternating bits
    logic [7:0] test_vec [0:7] = '{8'h41, 8'h55, 8'hAA, 8'hFF, 8'h00, 8'h0F, 8'hF0, 8'h5A};

    initial begin
        uart_rx_tb = 1'b1;   // UART idle high
        reset      = 1'b1;
        pass_cnt   = 0;
        fail_cnt   = 0;

        repeat(8) @(posedge clk);
        reset = 1'b0;
        @(negedge clk);

        // Backdoor-load uart_loopback.hex into IMEM
        $readmemh(IMEM_HEX, dut.u_core.u_imem.u_b0.mem_sim);
        $readmemh(IMEM_HEX, dut.u_core.u_imem.u_b1.mem_sim);
        $readmemh(IMEM_HEX, dut.u_core.u_imem.u_b2.mem_sim);
        $readmemh(IMEM_HEX, dut.u_core.u_imem.u_b3.mem_sim);
        $display("[TB] IMEM loaded: uart_loopback firmware");
        $display("[TB] Firmware: receive byte → echo same byte back");
        $display("[TB] Baud rate: %0d (SIM), bit period: %0d ns", SIM_BAUD, BIT_NS);
        $display("[TB] ─────────────────────────────────────────");

        // Give firmware time to boot and reach rx_wait loop
        repeat(40) @(posedge clk);

        // ── Send 8 test bytes, verify echo ──────────────────────────────────
        for (int t = 0; t < 8; t++) begin
            automatic logic [7:0] sent = test_vec[t];

            $display("[TB] Sending 0x%02h ...", sent);
            uart_send(sent);

            uart_recv(rx_data, rx_ok);

            if (!rx_ok) begin
                $display("[TB]   [FAIL] Timeout — no echo received");
                fail_cnt++;
            end else if (rx_data === sent) begin
                $display("[TB]   [PASS] Echo 0x%02h ✓", rx_data);
                pass_cnt++;
            end else begin
                $display("[TB]   [FAIL] Sent 0x%02h, got 0x%02h", sent, rx_data);
                fail_cnt++;
            end

            // Small gap between bytes (let firmware loop back to rx_wait)
            #(BIT_NS * 3);
        end

        // ── Summary ─────────────────────────────────────────────────────────
        $display("[TB] ─────────────────────────────────────────");
        $display("[TB] TOTAL: %0d PASS / %0d FAIL", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("[TB] ALL UART LOOPBACK TESTS PASSED");
        else
            $display("[TB] SOME TESTS FAILED");
        $display("[TB] ─────────────────────────────────────────");

        #(1000);
        $finish;
    end

    // ─── Watchdog ────────────────────────────────────────────────────────────
    initial begin
        #(200_000_000);  // 200 ms
        $display("[TB] WATCHDOG: simulation timed out");
        $finish;
    end

    // ─── Monitor UART TX activity ────────────────────────────────────────────
    always @(negedge uart_tx_fpga)
        $display("[%0t ns] FPGA TX: start bit detected", $time);

endmodule
