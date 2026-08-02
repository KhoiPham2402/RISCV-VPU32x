// =============================================================================
// tb_bench_generic.sv — Generic AXPY/matmul benchmark runner for the fpga/rtl
// 5-stage pipeline + VPU. Loads IMEM from a hex file, runs for a fixed cycle
// budget, then checks the 4-word "mailbox" at DMEM byte address 0x1E0
// (word indices 120..123) that sw/benchmarks/{axpy,matmul}/main.c writes
// results to. No DMEM pre-init needed — both benchmarks stack-allocate and
// initialize their own input arrays in firmware.
//
// DMEM is a single shared port arbitrated by dmem_arbiter (VLSU > scalar),
// matching the real fpga/rtl/top/riscv_vpu_top_fpga.sv architecture — not an
// idealized dual-port model, so real scalar/VLSU contention (and any
// resulting stall/retry bugs) is actually exercised here.
//
// Run (override parameters via -g):
//   vsim -c -gIMEM_FILE=<path> -gEXP0=.. -gEXP1=.. -gEXP2=.. -gEXP3=.. \
//        -gNAME=<label> work.tb_bench_generic
// See fpga/sim/run_bench_axpy_matmul.do for the AXPY + matmul invocations.
// =============================================================================
`timescale 1ns/1ps
module tb_bench_generic;

    parameter string IMEM_FILE = "";
    parameter int    MAX_CYCLES = 20000;
    parameter int    EXP0 = 0, EXP1 = 0, EXP2 = 0, EXP3 = 0;
    parameter string NAME = "bench";

    logic clk = 0;
    always #5 clk = ~clk;
    logic reset;

    logic [31:0] s_addr, s_wdata, s_rdata;
    logic        s_we, s_re;
    logic [ 3:0] s_be;
    logic        s_stall;

    logic        vlsu_req, vlsu_we;
    logic [31:0] vlsu_addr, vlsu_wdata, vlsu_rdata;
    logic [ 3:0] vlsu_be;
    logic        vlsu_ready;

    logic        vpu_ready, vpu_cfg_done, vpu_busy;
    logic [31:0] vpu_vl_remain;
    logic        vpu_insn_vld;
    logic [31:0] vpu_insn, vpu_rs1, vpu_rs2;
    logic [3:0]  fsm_state;
    logic [15:0] vmask16;
    logic [3:0]  vpu_cycles;
    logic        fifo_full;
    logic [31:0] wb_l0, wb_l1, wb_l2, wb_l3;
    logic [31:0] csr_vl, csr_vtype, csr_vlenb, csr_rdata;
    logic        vlsu_busy_o;
    logic [31:0] pc_debug;
    logic        insn_vld;

    pipelined_vpu u_core (
        .i_clk          (clk),
        .i_reset        (reset),
        .i_io_sw        (32'b0),
        .o_io_ledr      (), .o_io_ledg (), .o_io_lcd  (),
        .o_io_hex0      (), .o_io_hex1 (), .o_io_hex2 (), .o_io_hex3 (),
        .o_io_hex4      (), .o_io_hex5 (), .o_io_hex6 (), .o_io_hex7 (),
        .o_pc_debug     (pc_debug),
        .o_insn_vld     (insn_vld),
        .o_illegal_instr(),
        .s_dmem_addr_o  (s_addr),
        .s_dmem_wdata_o (s_wdata),
        .s_dmem_we_o    (s_we),
        .s_dmem_be_o    (s_be),
        .s_dmem_re_o    (s_re),
        .s_dmem_rdata_i (s_rdata),
        .s_dmem_stall_i (s_stall),
        .vpu_ready_i    (vpu_ready),
        .vpu_cfg_done_i (vpu_cfg_done),
        .vpu_vl_remain_i(vpu_vl_remain),
        .vpu_insn_vld_o (vpu_insn_vld),
        .vpu_insn_o     (vpu_insn),
        .vpu_rs1_data_o (vpu_rs1),
        .vpu_rs2_data_o (vpu_rs2)
    );

    vproc_system_wrapper #(
        .NUM_REGS   (32),
        .ADDR_WIDTH (5),
        .CTRL_WIDTH (49)
    ) u_vpu (
        .clk              (clk),
        .rst_n            (~reset),
        .instr_valid      (vpu_insn_vld),
        .instruction      (vpu_insn),
        .rs1_scalar_data  (vpu_rs1),
        .rs2_scalar_data  (vpu_rs2),
        .vrf_commit_en    (1'b1),
        .cycles           (vpu_cycles),
        .vmask16          (vmask16),
        .fifo_full        (fifo_full),
        .busy             (vpu_busy),
        .fsm_state        (fsm_state),
        .wb_result_lane0  (wb_l0),
        .wb_result_lane1  (wb_l1),
        .wb_result_lane2  (wb_l2),
        .wb_result_lane3  (wb_l3),
        .vpu_ready        (vpu_ready),
        .vpu_cfg_done     (vpu_cfg_done),
        .vpu_vl_remain    (vpu_vl_remain),
        .csr_vl_o         (csr_vl),
        .csr_vtype_o      (csr_vtype),
        .csr_vlenb_o      (csr_vlenb),
        .scalar_csr_addr  (12'b0),
        .scalar_csr_rdata (csr_rdata),
        .vlsu_mem_req     (vlsu_req),
        .vlsu_mem_we      (vlsu_we),
        .vlsu_mem_addr    (vlsu_addr),
        .vlsu_mem_be      (vlsu_be),
        .vlsu_mem_wdata   (vlsu_wdata),
        .vlsu_mem_rdata   (vlsu_rdata),
        .vlsu_mem_ready   (vlsu_ready),
        .vlsu_busy_o      (vlsu_busy_o)
    );

    logic        mem_re_p, mem_we_p;
    logic [31:0] mem_addr_p, mem_wdata_p, mem_rdata_p;
    logic [ 3:0] mem_be_p;

    dmem_arbiter #(.ADDR_W(32), .DATA_W(32), .VID_AW(14)) u_dmem_arb (
        .clk(clk), .rst_n(~reset),
        .m0_req_i(vlsu_req), .m0_we_i(vlsu_we), .m0_addr_i(vlsu_addr),
        .m0_be_i(vlsu_be),   .m0_wdata_i(vlsu_wdata),
        .m0_rdata_o(vlsu_rdata), .m0_ready_o(vlsu_ready),
        .m1_re_i(s_re), .m1_we_i(s_we), .m1_addr_i(s_addr),
        .m1_be_i(s_be), .m1_wdata_i(s_wdata),
        .m1_rdata_o(s_rdata), .m1_stall_o(s_stall),
        .m2_addr_i(14'b0), .m2_re_i(1'b0), .m2_rdata_o(),
        .mem_re_o(mem_re_p), .mem_we_o(mem_we_p), .mem_addr_o(mem_addr_p),
        .mem_be_o(mem_be_p), .mem_wdata_o(mem_wdata_p), .mem_rdata_i(mem_rdata_p)
    );

    dmem_model_sp #(.DEPTH(16384)) u_dmem (
        .clk(clk), .re(mem_re_p), .we(mem_we_p), .addr(mem_addr_p),
        .be(mem_be_p), .wdata(mem_wdata_p), .rdata(mem_rdata_p)
    );

    integer n_arb_conflict;
    integer arb_streak, max_arb_streak;
    always @(posedge clk) begin
        if (s_stall) begin
            n_arb_conflict++;
            arb_streak++;
            if (arb_streak > max_arb_streak) max_arb_streak = arb_streak;
        end else begin
            arb_streak = 0;
        end
    end

    integer cycle_cnt;
    integer errors;
    initial begin
        reset = 1'b1;
        n_arb_conflict = 0;
        arb_streak = 0;
        max_arb_streak = 0;
        repeat(4) @(posedge clk);
        reset = 1'b0;
        @(negedge clk);

        $readmemh(IMEM_FILE, u_core.u_imem.u_b0.mem_sim);
        $readmemh(IMEM_FILE, u_core.u_imem.u_b1.mem_sim);
        $readmemh(IMEM_FILE, u_core.u_imem.u_b2.mem_sim);
        $readmemh(IMEM_FILE, u_core.u_imem.u_b3.mem_sim);

        for (integer i = 0; i < 16384; i++) u_dmem.mem[i] = 32'b0;

        $display("[%s] IMEM loaded from %s", NAME, IMEM_FILE);

        for (cycle_cnt = 0; cycle_cnt < MAX_CYCLES; cycle_cnt++) begin
            @(posedge clk); #1;
        end

        errors = 0;
        $display("[%s] mailbox[0]=%0d (expected %0d)", NAME, $signed(u_dmem.mem[120]), EXP0);
        $display("[%s] mailbox[1]=%0d (expected %0d)", NAME, $signed(u_dmem.mem[121]), EXP1);
        $display("[%s] mailbox[2]=%0d (expected %0d)", NAME, $signed(u_dmem.mem[122]), EXP2);
        $display("[%s] mailbox[3]=%0d (expected %0d)", NAME, $signed(u_dmem.mem[123]), EXP3);
        $display("[%s] arbitration conflicts (scalar denied): %0d cycles, max consecutive streak: %0d cycles",
                 NAME, n_arb_conflict, max_arb_streak);
        if ($signed(u_dmem.mem[120]) !== EXP0) errors++;
        if ($signed(u_dmem.mem[121]) !== EXP1) errors++;
        if ($signed(u_dmem.mem[122]) !== EXP2) errors++;
        if ($signed(u_dmem.mem[123]) !== EXP3) errors++;

        if (errors == 0) $display("[%s] ALL CHECKS PASSED (%0d cycles)", NAME, MAX_CYCLES);
        else $display("[%s] %0d CHECK(S) FAILED", NAME, errors);
        $stop;
    end
endmodule
