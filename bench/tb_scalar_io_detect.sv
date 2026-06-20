`timescale 1ns/1ps
module tb_scalar_io_detect;
    logic        clk   = 1'b0;
    logic        rst_n;
    logic [31:0] pc;
    logic [31:0] ledr;

    riscv_vpu_top dut (
        .clk(clk), .rst_n(rst_n), .io_sw(32'd0),
        .io_ledr(ledr), .io_ledg(), .io_hex0(), .io_hex1(), .io_hex2(),
        .io_hex3(), .io_hex4(), .io_hex5(), .io_hex6(), .io_hex7(),
        .io_lcd(), .pc_debug(pc), .insn_vld(),
        .vpu_cycles(), .vpu_vmask16(), .vpu_fifo_full(),
        .vpu_busy(), .vpu_fsm_state(),
        .vpu_wb_lane0(), .vpu_wb_lane1(), .vpu_wb_lane2(), .vpu_wb_lane3()
    );

    always #5 clk = ~clk;

    integer cyc;
    integer last_pc_change;
    logic [31:0] prev_pc;

    initial begin
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        cyc = 0;
        prev_pc = 32'h0;
        last_pc_change = 0;

        forever begin
            @(posedge clk);
            cyc = cyc + 1;
            if (pc !== prev_pc) last_pc_change = cyc;
            prev_pc = pc;
            // Done: PC stuck for 200 consecutive cycles AND we've run >100 cycles
            if ((cyc - last_pc_change) == 200 && cyc > 100) begin
                $display("[RESULT] PC stuck at 0x%08X after cycle %0d", pc, last_pc_change);
                $display("[CYCLES] Execution = %0d cycles", last_pc_change);
                $finish;
            end
            if (cyc % 100000 == 0)
                $display("[...] cycle %0d  pc=0x%08X", cyc, pc);
        end
    end

    initial begin
        repeat(3000000) @(posedge clk);
        $display("[TIMEOUT] at 3M cycles");
        $finish;
    end
endmodule
