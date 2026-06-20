// Top-level for pipelined VPU trial synthesis.
// Structurally identical to riscv_vpu_top; substitutes vproc_system_wrapper_p
// for the VPU subsystem to measure Fmax improvement from the pre-lane pipeline.
//
// Target: Intel Cyclone V  5CSXFC6D6F31C6 (DE10-Standard)
// Expected Fmax: >90 MHz (vs ~47 MHz baseline) due to cut MUL critical path.

module riscv_vpu_top_pipeline (
    input  logic         clk,
    input  logic         rst_n,

    input  logic [31:0]  io_sw,
    output logic [31:0]  io_ledr,
    output logic [31:0]  io_ledg,
    output logic [31:0]  io_lcd,
    output logic [ 6:0]  io_hex0,
    output logic [ 6:0]  io_hex1,
    output logic [ 6:0]  io_hex2,
    output logic [ 6:0]  io_hex3,
    output logic [ 6:0]  io_hex4,
    output logic [ 6:0]  io_hex5,
    output logic [ 6:0]  io_hex6,
    output logic [ 6:0]  io_hex7,

    output logic [31:0]  pc_debug,
    output logic         insn_vld,

    output logic [3:0]   vpu_cycles,
    output logic [15:0]  vpu_vmask16,
    output logic         vpu_fifo_full,
    output logic         vpu_busy,
    output logic [3:0]   vpu_fsm_state,
    output logic [31:0]  vpu_wb_lane0,
    output logic [31:0]  vpu_wb_lane1,
    output logic [31:0]  vpu_wb_lane2,
    output logic [31:0]  vpu_wb_lane3
);

    // Scalar ↔ VPU wires
    logic        vpu_ready;
    logic        vpu_cfg_done;
    logic [31:0] vpu_vl_remain;
    logic        vpu_insn_vld;
    logic [31:0] vpu_insn;
    logic [31:0] vpu_rs1_data;
    logic [31:0] vpu_rs2_data;
    logic [31:0] vpu_csr_vl;
    logic [31:0] vpu_csr_vtype;
    logic [31:0] vpu_csr_vlenb;
    logic [11:0] scalar_csr_addr;
    logic [31:0] scalar_csr_rdata;

    // VLSU memory bus
    logic        vlsu_mem_req;
    logic        vlsu_mem_we;
    logic [31:0] vlsu_mem_addr;
    logic [ 3:0] vlsu_mem_be;
    logic [31:0] vlsu_mem_wdata;
    logic [31:0] vlsu_mem_rdata;   // combinatorial read from scalar LSU DMEM

    // dmem_sync-equivalent: VLSU reads have 1-cycle latency (matches vproc_vec_lsu
    // prefetch design); writes are acked combinatorially on the same cycle.
    logic [31:0] vlsu_rdata_q;
    logic        vlsu_rd_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vlsu_rdata_q    <= 32'd0;
            vlsu_rd_pending <= 1'b0;
        end else begin
            vlsu_rd_pending <= vlsu_mem_req & ~vlsu_mem_we;
            if (vlsu_mem_req & ~vlsu_mem_we)
                vlsu_rdata_q <= vlsu_mem_rdata;
        end
    end

    wire vlsu_mem_ready_int = vlsu_mem_we ? vlsu_mem_req : vlsu_rd_pending;

    single_cycle u_scalar_core (
        .i_clk          (clk),
        .i_reset        (rst_n),
        .i_io_sw        (io_sw),
        .o_io_ledr      (io_ledr),
        .o_io_ledg      (io_ledg),
        .o_io_lcd       (io_lcd),
        .o_io_hex0      (io_hex0),
        .o_io_hex1      (io_hex1),
        .o_io_hex2      (io_hex2),
        .o_io_hex3      (io_hex3),
        .o_io_hex4      (io_hex4),
        .o_io_hex5      (io_hex5),
        .o_io_hex6      (io_hex6),
        .o_io_hex7      (io_hex7),
        .o_pc_debug     (pc_debug),
        .o_insn_vld     (insn_vld),

        .i_vpu_ready      (vpu_ready),
        .i_vpu_cfg_done   (vpu_cfg_done),
        .i_vpu_vl_remain  (vpu_vl_remain),
        .o_vpu_insn_vld   (vpu_insn_vld),
        .o_vpu_insn       (vpu_insn),
        .o_vpu_rs1_data   (vpu_rs1_data),
        .o_vpu_rs2_data   (vpu_rs2_data),
        .o_csr_addr       (scalar_csr_addr),
        .i_csr_rdata      (scalar_csr_rdata),

        .i_vlsu_mem_req   (vlsu_mem_req),
        .i_vlsu_mem_we    (vlsu_mem_we),
        .i_vlsu_mem_addr  (vlsu_mem_addr),
        .i_vlsu_mem_be    (vlsu_mem_be),
        .i_vlsu_mem_wdata (vlsu_mem_wdata),
        .o_vlsu_mem_rdata (vlsu_mem_rdata)
    );

    vproc_system_wrapper_p u_vpu (
        .clk             (clk),
        .rst_n           (rst_n),

        .instr_valid     (vpu_insn_vld),
        .instruction     (vpu_insn),
        .rs1_scalar_data (vpu_rs1_data),
        .rs2_scalar_data (vpu_rs2_data),

        .vrf_commit_en   (1'b1),

        .cycles          (vpu_cycles),
        .vmask16         (vpu_vmask16),
        .fifo_full       (vpu_fifo_full),
        .busy            (vpu_busy),
        .fsm_state       (vpu_fsm_state),
        .wb_result_lane0 (vpu_wb_lane0),
        .wb_result_lane1 (vpu_wb_lane1),
        .wb_result_lane2 (vpu_wb_lane2),
        .wb_result_lane3 (vpu_wb_lane3),

        .vpu_ready       (vpu_ready),
        .vpu_cfg_done    (vpu_cfg_done),
        .vpu_vl_remain   (vpu_vl_remain),
        .csr_vl_o        (vpu_csr_vl),
        .csr_vtype_o     (vpu_csr_vtype),
        .csr_vlenb_o     (vpu_csr_vlenb),
        .scalar_csr_addr (scalar_csr_addr),
        .scalar_csr_rdata(scalar_csr_rdata),

        .vlsu_mem_req    (vlsu_mem_req),
        .vlsu_mem_we     (vlsu_mem_we),
        .vlsu_mem_addr   (vlsu_mem_addr),
        .vlsu_mem_be     (vlsu_mem_be),
        .vlsu_mem_wdata  (vlsu_mem_wdata),
        .vlsu_mem_rdata  (vlsu_rdata_q),
        .vlsu_mem_ready  (vlsu_mem_ready_int),
        .vlsu_busy_o     ()
    );

endmodule
