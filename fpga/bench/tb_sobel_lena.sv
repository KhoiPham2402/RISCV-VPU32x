// =============================================================================
// tb_sobel_lena.sv — Sobel edge detection on Lena, full FPGA system
//
// DUT: pipelined_vpu (FPGA scalar core, fpga/rtl/pipeline/) +
//      vproc_system_wrapper (FPGA VPU, fpga/rtl/vpu/) +
//      dmem_arbiter + dmem_model_sp (shared single-port DMEM bus, matching
//      fpga/rtl/top/riscv_vpu_top_fpga.sv's architecture — see
//      fpga/rtl/bus/dmem_arbiter.sv)
//
// IMEM: backdoor-loaded from sobel_imem.hex (sw/benchmarks/sobel/sobel.c
//       compiled via riscv64-unknown-elf-gcc, see sw/benchmarks/sobel/Makefile).
// DMEM: backdoor-loaded from sobel_dmem_init.hex (64x64 grayscale Lena input
//       plane at word 1024, output plane pre-zeroed at word 5120 — see
//       sw/benchmarks/sobel/prep_sobel.py). No UART needed.
//
// Modeled on fpga/bench/tb_fpga_imem_lena.sv (IMEM backdoor-load + done
// detection) and bench/tb_lena_gray.sv (full-DMEM dump for reconstruction).
//
// Run: vsim -c -do fpga/sim/run_sobel_lena.do
// =============================================================================
`timescale 1ns/1ps

module tb_sobel_lena;

    // ─── Parameters ─────────────────────────────────────────────────────────
    parameter string IMEM_FILE = "sw/benchmarks/sobel/sobel_imem.hex";
    parameter string DMEM_INIT = "sw/benchmarks/sobel/sobel_dmem_init.hex";
    parameter string DMEM_OUT  = "sw/benchmarks/sobel/sobel_dmem_out.hex";
    parameter int    MAX_CYCLES = 400000;

    // ─── Clock / Reset ──────────────────────────────────────────────────────
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset;             // active-HIGH (pipelined_vpu convention)

    // ─── Scalar DMEM bus (from pipelined_vpu) ───────────────────────────────
    logic [31:0] s_addr, s_wdata, s_rdata;
    logic        s_we, s_re;
    logic [ 3:0] s_be;
    logic        s_stall;

    // ─── VLSU DMEM bus (from vproc_system_wrapper) ──────────────────────────
    logic        vlsu_req, vlsu_we;
    logic [31:0] vlsu_addr, vlsu_wdata, vlsu_rdata;
    logic [ 3:0] vlsu_be;
    logic        vlsu_ready;

    // ─── VPU interface wires ────────────────────────────────────────────────
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

    // ─── DUT: FPGA scalar core ───────────────────────────────────────────────
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

    // ─── DUT: FPGA VPU ───────────────────────────────────────────────────────
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

    // ─── Shared DMEM bus: single port, arbitrated (VLSU > scalar) ───────────
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
    always @(posedge clk) if (s_stall) n_arb_conflict++;

    // ─── Stimulus ────────────────────────────────────────────────────────────
    integer cycle_cnt;
    integer jdone_cnt, jdone_grace;
    integer out_fd;

    initial begin
        reset = 1'b1;
        n_arb_conflict = 0;
        repeat(4) @(posedge clk);
        reset = 1'b0;
        @(negedge clk);

        // Backdoor-load IMEM: all 4 banks store the full 32-bit word,
        // imem_sync extracts the byte slice per bank.
        $readmemh(IMEM_FILE, u_core.u_imem.u_b0.mem_sim);
        $readmemh(IMEM_FILE, u_core.u_imem.u_b1.mem_sim);
        $readmemh(IMEM_FILE, u_core.u_imem.u_b2.mem_sim);
        $readmemh(IMEM_FILE, u_core.u_imem.u_b3.mem_sim);

        // Backdoor-load DMEM with the grayscale input plane (+ pre-zeroed
        // output plane, already zero in sobel_dmem_init.hex)
        $readmemh(DMEM_INIT, u_dmem.mem);

        $display("[SOBEL] IMEM loaded from %s", IMEM_FILE);
        $display("[SOBEL] DMEM loaded from %s. in[0..3]=%0d %0d %0d %0d",
            DMEM_INIT, u_dmem.mem[1024], u_dmem.mem[1025],
            u_dmem.mem[1026], u_dmem.mem[1027]);

        // ── Run until firmware hits infinite loop (j done = 0x0000006f) ──
        jdone_cnt   = 0;
        jdone_grace = 0;
        for (cycle_cnt = 0; cycle_cnt < MAX_CYCLES; cycle_cnt++) begin
            @(posedge clk); #1;

            if (u_core.inst_decode == 32'h0000_006f && insn_vld) begin
                jdone_cnt++;
                jdone_grace = 0;
            end else if (jdone_cnt > 0) begin
                jdone_grace++;
                if (jdone_grace > 2) begin jdone_cnt = 0; jdone_grace = 0; end
            end

            if (jdone_cnt >= 3) begin
                $display("[Cycle %0d] j-done detected — draining...", cycle_cnt);
                repeat(16) @(posedge clk);
                break;
            end
        end

        if (cycle_cnt >= MAX_CYCLES - 1)
            $display("WARNING: timeout after %0d cycles!", MAX_CYCLES);

        // ── Sample results ───────────────────────────────────────────────
        $display("=================================================================");
        $display("  Cycles  : %0d", cycle_cnt);
        $display("  Arbitration conflicts (scalar denied): %0d cycles", n_arb_conflict);
        $display("  out[row1, col1..4] = %0d %0d %0d %0d  (word 5120+64+1..4)",
            u_dmem.mem[5120+64+1], u_dmem.mem[5120+64+2],
            u_dmem.mem[5120+64+3], u_dmem.mem[5120+64+4]);
        $display("  out[row32,col32]   = %0d  (word 5120+32*64+32)",
            u_dmem.mem[5120 + 32*64 + 32]);

        // ── Dump full DMEM for reconstruct_sobel.py ──────────────────────
        out_fd = $fopen(DMEM_OUT, "w");
        if (out_fd == 0) begin
            $display("  WARNING: cannot open %s for write", DMEM_OUT);
        end else begin
            for (int i = 0; i < 16384; i++)
                $fdisplay(out_fd, "%08x", u_dmem.mem[i]);
            $fclose(out_fd);
            $display("  DMEM dumped -> %s", DMEM_OUT);
        end

        $display("=================================================================");
        $display("  Next step:");
        $display("    python sw/benchmarks/sobel/reconstruct_sobel.py");
        $display("    -> sobel_vpu_output.png + sobel_comparison.png");
        $display("=================================================================");
        $stop;
    end

endmodule
