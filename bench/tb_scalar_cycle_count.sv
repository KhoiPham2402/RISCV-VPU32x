`timescale 1ns/1ps
module tb_scalar_cycle_count;

    logic        clk   = 1'b0;
    logic        rst_n;
    logic [31:0] pc;
    logic [31:0] ledr;

    riscv_vpu_top dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .io_sw      (32'd0),
        .io_ledr    (ledr),
        .io_ledg    (),
        .io_hex0    (), .io_hex1    (), .io_hex2    (),
        .io_hex3    (), .io_hex4    (), .io_hex5    (),
        .io_hex6    (), .io_hex7    (),
        .io_lcd     (),
        .pc_debug   (pc),
        .insn_vld   (),
        .vpu_cycles (), .vpu_vmask16 (), .vpu_fifo_full(),
        .vpu_busy   (), .vpu_fsm_state(),
        .vpu_wb_lane0(), .vpu_wb_lane1(),
        .vpu_wb_lane2(), .vpu_wb_lane3()
    );

    always #5 clk = ~clk;   // 100 MHz for faster sim

    integer      cyc;
    logic [31:0] max_pc;
    integer      stable_cnt;

    initial begin
        rst_n = 1'b0;
        repeat(10) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        cyc = 0; max_pc = 32'h0; stable_cnt = 0;

        @(posedge clk); max_pc = pc;

        forever begin
            @(posedge clk);
            cyc = cyc + 1;
            if (pc > max_pc) begin
                max_pc     = pc;
                stable_cnt = 0;
            end else begin
                stable_cnt = stable_cnt + 1;
                if (stable_cnt == 500) begin
                    $display("[BENCH] done at cycle %0d  (max_pc=0x%08X)", cyc, max_pc);
                    $finish;
                end
            end
            if (cyc % 50000 == 0)
                $display("[BENCH] ... %0d cycles  pc=0x%08X  max=0x%08X",
                         cyc, pc, max_pc);
        end
    end

    initial begin
        repeat(2100000) @(posedge clk);
        $display("[BENCH] TIMEOUT at 2100000 cycles");
        $finish;
    end
endmodule
