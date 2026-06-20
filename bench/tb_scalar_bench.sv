`timescale 1ns/1ps
// tb_scalar_bench.sv — measures cycles until firmware reaches "done" loop.
// Detects done by: PC stops ADVANCING (max observed PC doesn't increase for
// 200 consecutive cycles). Works even if j-done causes PC to flip between
// two values (branch flush pattern in 5-stage pipeline).
module tb_scalar_bench;
    logic clk  = 1'b0;
    logic reset;
    logic [31:0] pc;

    riscv_vpu_top_fpga #(
        .UART_CLK_FREQ (50_000_000),
        .UART_BAUD_RATE(115_200)
    ) dut (
        .i_clk   (clk), .i_reset(reset),
        .i_io_sw (32'd0), .uart_rx(1'b1), .uart_tx(),
        .o_io_ledr(),.o_io_ledg(),.o_io_lcd(),
        .o_io_hex0(),.o_io_hex1(),.o_io_hex2(),
        .o_io_hex3(),.o_io_hex4(),.o_io_hex5(),
        .o_io_hex6(),.o_io_hex7(),
        .vga_r(),.vga_g(),.vga_b(),.vga_clk(),
        .vga_hs(),.vga_vs(),.vga_blank_n(),.vga_sync_n(),
        .o_pc_debug      (pc),
        .o_insn_vld      (), .o_vpu_cycles  (),
        .o_vmask16       (), .o_vpu_busy    (),
        .o_fsm_state     (),
        .o_wb_result_lane0(), .o_wb_result_lane1(),
        .o_wb_result_lane2(), .o_wb_result_lane3()
    );

    always #10 clk = ~clk;   // 50 MHz

    integer cyc;
    logic [31:0] max_pc;
    integer      stable_cnt;

    initial begin
        reset = 1'b1;
        repeat(50) @(posedge clk);
        reset = 1'b0;
        @(posedge clk);

        cyc = 0; max_pc = 32'h0; stable_cnt = 0;

        forever begin
            @(posedge clk);
            cyc = cyc + 1;

            // Track highest PC seen so far
            if (pc > max_pc) begin
                max_pc     = pc;
                stable_cnt = 0;   // reset stable counter when PC advances
            end else begin
                stable_cnt = stable_cnt + 1;
                // Done when PC hasn't advanced for 500 cycles
                if (stable_cnt == 500) begin
                    $display("[BENCH] done at cycle %0d  (max_pc=0x%08X)", cyc, max_pc);
                    $finish;
                end
            end

            if (cyc % 100000 == 0)
                $display("[BENCH] ... %0d cycles, pc=0x%08X max=0x%08X",
                         cyc, pc, max_pc);
        end
    end

    initial begin
        #40000000;   // 40ms = 2M cycles timeout
        $display("[BENCH] TIMEOUT at %0d cycles", $time/20);
        $finish;
    end

endmodule
