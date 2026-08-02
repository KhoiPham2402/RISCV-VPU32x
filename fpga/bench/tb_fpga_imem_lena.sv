// =============================================================================
// tb_fpga_imem_lena.sv — Full FPGA system: scalar core fetches from real IMEM
//
// DUT: pipelined_vpu (FPGA scalar core, fpga/rtl/pipeline/) +
//      vproc_system_wrapper (FPGA VPU, fpga/rtl/vpu/)
//
// IMEM: backdoor-loaded from lena_imem.hex (lena_gray compiled firmware).
// DMEM: behavioral model, backdoor-loaded from lena_dmem_init.hex (RGB pixels).
// No UART needed — firmware reads pixels directly from DMEM.
//
// Waveform shows:
//   PC, current instruction (from IMEM), VPU dispatch signals,
//   FSM state (enum), VLSU state (enum), VRF write-back data.
//
// Run: vsim -do fpga/sim/run_wave_fpga_imem_lena.do
// =============================================================================
`timescale 1ns/1ps

module tb_fpga_imem_lena;

    // ─── Parameters ─────────────────────────────────────────────────────────
    parameter string IMEM_FILE = "C:\\CapstoneProject2\\riscv_vpu\\sw\\benchmarks\\lena_gray\\lena_imem.hex";
    parameter string DMEM_INIT = "C:\\CapstoneProject2\\riscv_vpu\\sw\\benchmarks\\lena_gray\\lena_dmem_init.hex";
    localparam int   MAX_CYCLES = 120000;

    // ─── Clock / Reset ──────────────────────────────────────────────────────
    logic clk = 0;
    always #5 clk = ~clk;   // 100 MHz
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
        // Scalar DMEM
        .s_dmem_addr_o  (s_addr),
        .s_dmem_wdata_o (s_wdata),
        .s_dmem_we_o    (s_we),
        .s_dmem_be_o    (s_be),
        .s_dmem_re_o    (s_re),
        .s_dmem_rdata_i (s_rdata),
        .s_dmem_stall_i (s_stall),
        // VPU interface
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
    // Matches the real fpga/rtl/top/riscv_vpu_top_fpga.sv architecture (see
    // fpga/rtl/bus/dmem_arbiter.sv) instead of an idealized dual-port model
    // — real scalar/VLSU contention (and the retry/stall path it exercises
    // in pipelined_vpu.sv) is actually exercised by this testbench.
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

    // ─── VPU instruction name (for waveform) ────────────────────────────────
    string vpu_instr_name;
    always_comb begin
        if (!vpu_insn_vld) vpu_instr_name = "---";
        else case (vpu_insn[6:0])
            7'b1010111: begin
                if (vpu_insn[14:12] == 3'b111)              vpu_instr_name = "vsetvli";
                else if (vpu_insn[14:12]==3'b010 &&
                         vpu_insn[31:29]==3'b000)           vpu_instr_name = "vred*.vs";
                else if (vpu_insn[31:26]==6'b100101)        vpu_instr_name = (vpu_insn[14:12]==3'b110) ? "vmul.vx" : "vmul.vv";
                else if (vpu_insn[31:26]==6'b100100)        vpu_instr_name = "vmulhu.vx";
                else if (vpu_insn[31:26]==6'b000000 &&
                         vpu_insn[14:12]==3'b000)           vpu_instr_name = "vadd.vv";
                else                                        vpu_instr_name = "OP-V";
            end
            7'b0000111: vpu_instr_name = (vpu_insn[14:12]==3'b000) ? "vle8.v"  :
                                         (vpu_insn[14:12]==3'b110) ? "vle32.v" : "vle?.v";
            7'b0100111: vpu_instr_name = (vpu_insn[14:12]==3'b000) ? "vse8.v"  :
                                         (vpu_insn[14:12]==3'b110) ? "vse32.v" : "vse?.v";
            default:    vpu_instr_name = "---";
        endcase
    end

    // ─── FSM state name ──────────────────────────────────────────────────────
    string fsm_state_name;
    always_comb case (fsm_state)
        4'd0: fsm_state_name = "ST_IDLE";
        4'd1: fsm_state_name = "ST_CONFIG";
        4'd2: fsm_state_name = "ST_EXEC";
        4'd5: fsm_state_name = "ST_MASKING";
        4'd7: fsm_state_name = "ST_REDUCTION";
        4'd8: fsm_state_name = "ST_RED_DONE";
        4'd9: fsm_state_name = "ST_DRAIN";
        default: fsm_state_name = "ST_OTHER";
    endcase

    // ─── Stimulus ────────────────────────────────────────────────────────────
    integer cycle_cnt;
    integer jdone_cnt, jdone_grace;

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

        // Backdoor-load DMEM with RGB pixel planes
        $readmemh(DMEM_INIT, u_dmem.mem);

        $display("[TB] IMEM loaded from %s", IMEM_FILE);
        $display("[TB] DMEM loaded. R[0]=%02h  G[0]=%02h  B[0]=%02h",
            u_dmem.mem[0][7:0], u_dmem.mem[4096][7:0], u_dmem.mem[8192][7:0]);

        // ── Run until firmware hits infinite loop (j done = 0x0000006f) ──
        jdone_cnt   = 0;
        jdone_grace = 0;
        for (cycle_cnt = 0; cycle_cnt < MAX_CYCLES; cycle_cnt++) begin
            @(posedge clk); #1;

            // Detect 'j 0' infinite loop (done marker)
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

        // ── Print first 16 Y pixels ──────────────────────────────────────
        $display("Y[0..3]  = %02h %02h %02h %02h",
            u_dmem.mem[12288][7:0],  u_dmem.mem[12288][15:8],
            u_dmem.mem[12288][23:16],u_dmem.mem[12288][31:24]);
        $display("Y[4..7]  = %02h %02h %02h %02h",
            u_dmem.mem[12289][7:0],  u_dmem.mem[12289][15:8],
            u_dmem.mem[12289][23:16],u_dmem.mem[12289][31:24]);
        $display("Cycles: %0d", cycle_cnt);
        $display("Arbitration conflicts (scalar denied): %0d cycles", n_arb_conflict);
        $stop;
    end

endmodule
