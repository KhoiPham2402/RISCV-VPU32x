// =============================================================================
// tb_fwd_hazard.sv — directed regression for the EX-stage MEM-forward bug
// fixed 2026-08-02 in pipelined_vpu.sv (mem_fwd_value).
//
// Bug: fwd_a/fwd_b's "forward from MEM" case (01) always selected
// alu_result_m, which is only the MEM-stage instruction's real result for
// regular ALU ops / AUIPC (wb_sel_mem==01). For LUI (wb_sel_mem==11) the
// real result is imm_m; for JAL/JALR (wb_sel_mem==10) it's pc_four_m (the
// link address, not the jump target alu_result_m computes). Any instruction
// immediately following a lui/jal/jalr that consumes its rd — most commonly
// the addi half of a `li reg, <32-bit constant>` expansion — got silently
// wrong data via this 1-cycle-apart forwarding path.
//
// This also exercises the case that prompted the investigation: a scalar
// `lw` immediately followed by a VPU `vle32.v` that uses the just-loaded
// register as its base address (verifies the load-use hazard/forwarding
// path generically handles a vector consumer the same as a scalar one,
// since it only compares instruction-encoding register field positions).
//
// Source: fpga/bench/asm/fwd_hazard.S, fpga/bench/asm/fwd_hazard2.S
// (pre-built to fwd_hazard_imem.hex / fwd_hazard2_imem.hex — see
// fpga/sim/run_fwd_hazard.do for the rebuild command).
//
// Run: vsim -c -do fpga/sim/run_fwd_hazard.do
// =============================================================================
`timescale 1ns/1ps

module tb_fwd_hazard;

    parameter string IMEM_FILE = "";
    localparam int MAX_CYCLES = 5000;

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

    integer cycle_cnt;
    integer jdone_cnt;
    integer errors;

    initial begin
        reset = 1'b1;
        errors = 0;
        repeat(4) @(posedge clk);
        reset = 1'b0;
        @(negedge clk);

        $readmemh(IMEM_FILE, u_core.u_imem.u_b0.mem_sim);
        $readmemh(IMEM_FILE, u_core.u_imem.u_b1.mem_sim);
        $readmemh(IMEM_FILE, u_core.u_imem.u_b2.mem_sim);
        $readmemh(IMEM_FILE, u_core.u_imem.u_b3.mem_sim);
        for (integer i = 0; i < 16384; i++) u_dmem.mem[i] = 32'b0;

        jdone_cnt = 0;
        for (cycle_cnt = 0; cycle_cnt < MAX_CYCLES; cycle_cnt++) begin
            @(posedge clk); #1;
            if (u_core.inst_decode == 32'h0000_006f && insn_vld) begin
                jdone_cnt++;
                if (jdone_cnt >= 3) begin
                    repeat(8) @(posedge clk);
                    break;
                end
            end
        end

        $display("[FWD_HAZARD] cycles=%0d", cycle_cnt);

        // lui->addi (li pseudo-op) forwarding, then scalar lw -> vle32.v
        // using the loaded register as base address, dumped via vse32.v.
        $display("[FWD_HAZARD] DMEM[0x200..0x20C] source = %08h %08h %08h %08h",
            u_dmem.mem[128], u_dmem.mem[129], u_dmem.mem[130], u_dmem.mem[131]);
        $display("[FWD_HAZARD] DMEM[0x300..0x30C] dumped = %08h %08h %08h %08h",
            u_dmem.mem[192], u_dmem.mem[193], u_dmem.mem[194], u_dmem.mem[195]);
        if (!(u_dmem.mem[192] === 32'h11111111 && u_dmem.mem[193] === 32'h22222222 &&
              u_dmem.mem[194] === 32'h33333333 && u_dmem.mem[195] === 32'h44444444)) begin
            $display("[FWD_HAZARD] FAIL: lui/addi forwarding or lw->vle32.v hazard broken");
            errors++;
        end else begin
            $display("[FWD_HAZARD] PASS: lui->addi forwarding + lw->vle32.v hazard correct");
        end

        // jal x9 immediately followed by sw x9 (1-cycle-apart forward of
        // the link address, wb_sel_mem==10 case).
        $display("[FWD_HAZARD] DMEM[0x400] (jal x9 link addr) = %08h (expected 00000058)",
            u_dmem.mem[256]);
        if (u_dmem.mem[256] !== 32'h00000058) begin
            $display("[FWD_HAZARD] FAIL: jal->sw forwarding broken");
            errors++;
        end else begin
            $display("[FWD_HAZARD] PASS: jal link-address forwarding correct");
        end

        if (errors == 0) $display("=== RESULT: ALL PASS ===");
        else              $display("=== RESULT: %0d CHECK(S) FAILED ===", errors);
        $stop;
    end

endmodule
