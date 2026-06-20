`timescale 1ns/1ps
module tb_lena_orig_test;
    logic clk, rst_n;
    logic [31:0] io_sw, io_ledr, io_ledg, io_lcd;
    logic [6:0] io_hex0,io_hex1,io_hex2,io_hex3,io_hex4,io_hex5,io_hex6,io_hex7;
    logic [31:0] pc_debug; logic insn_vld;
    logic [3:0] vpu_cycles; logic [15:0] vpu_vmask16;
    logic vpu_fifo_full, vpu_busy; logic [3:0] vpu_fsm_state;
    logic [31:0] vpu_wb_lane0,vpu_wb_lane1,vpu_wb_lane2,vpu_wb_lane3;
    riscv_vpu_top dut(.clk(clk),.rst_n(rst_n),.io_sw(io_sw),.io_ledr(io_ledr),.io_ledg(io_ledg),.io_lcd(io_lcd),.io_hex0(io_hex0),.io_hex1(io_hex1),.io_hex2(io_hex2),.io_hex3(io_hex3),.io_hex4(io_hex4),.io_hex5(io_hex5),.io_hex6(io_hex6),.io_hex7(io_hex7),.pc_debug(pc_debug),.insn_vld(insn_vld),.vpu_cycles(vpu_cycles),.vpu_vmask16(vpu_vmask16),.vpu_fifo_full(vpu_fifo_full),.vpu_busy(vpu_busy),.vpu_fsm_state(vpu_fsm_state),.vpu_wb_lane0(vpu_wb_lane0),.vpu_wb_lane1(vpu_wb_lane1),.vpu_wb_lane2(vpu_wb_lane2),.vpu_wb_lane3(vpu_wb_lane3));
    `define IMEM dut.u_scalar_core.IMEM.inst_mem
    `define DMEM dut.u_scalar_core.lsu_u.dmem
    initial clk=0; always #5 clk=~clk;
    integer cycle_cnt; integer jd_cnt, jd_grace; logic [31:0] ci;
    initial begin
        io_sw=0; rst_n=0; repeat(3) @(posedge clk); rst_n=1; @(negedge clk);
        $readmemh("C:\CapstoneProject2\riscv_vpu\sw\benchmarks\lena_gray\lena_imem.hex", `IMEM);
        $readmemh("C:\CapstoneProject2\riscv_vpu\sw\benchmarks\lena_gray\lena_dmem_init.hex", `DMEM);
        $display("[ORIG-VPU] IMEM+DMEM loaded");
        jd_cnt=0; jd_grace=0;
        for(cycle_cnt=0;cycle_cnt<120000;cycle_cnt++) begin
            @(posedge clk); #1; ci=dut.u_scalar_core.inst;
            if(ci==32'h0000_006f) begin jd_cnt++; jd_grace=0; end
            else if(jd_cnt>0) begin jd_grace++; if(jd_grace>2) begin jd_cnt=0; jd_grace=0; end end
            if(jd_cnt>=3) begin repeat(16) @(posedge clk); break; end
        end
        $display("[ORIG-VPU] Cycles=%0d  Y[0..3]=%02h %02h %02h %02h  Y[4..7]=%02h %02h %02h %02h",
            cycle_cnt+1, `DMEM[12288][7:0],`DMEM[12288][15:8],`DMEM[12288][23:16],`DMEM[12288][31:24],
            `DMEM[12289][7:0],`DMEM[12289][15:8],`DMEM[12289][23:16],`DMEM[12289][31:24]);
        $finish;
    end
endmodule
