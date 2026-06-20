//==========================================================================
// riscv_vpu_top_v3.sv
// Top-level: 5-stage pipelined RISC-V core + 64 KB sync DMEM + VPU
//
// Connections:
//   pipelined_vpu  ←scalar DMEM→  dmem_sync  ←VLSU→  vproc_system_wrapper
//   pipelined_vpu  ←VPU dispatch→ vproc_system_wrapper
//
// Reset: i_reset is active-HIGH; internally inverted to rst_n for VPU/DMEM
//==========================================================================

module riscv_vpu_top_v3 (
    input  logic         i_clk,
    input  logic         i_reset,       // active-high

    input  logic [31:0]  i_io_sw,
    output logic [31:0]  o_io_ledr,
    output logic [31:0]  o_io_ledg,
    output logic [31:0]  o_io_lcd,
    output logic [ 6:0]  o_io_hex0,
    output logic [ 6:0]  o_io_hex1,
    output logic [ 6:0]  o_io_hex2,
    output logic [ 6:0]  o_io_hex3,
    output logic [ 6:0]  o_io_hex4,
    output logic [ 6:0]  o_io_hex5,
    output logic [ 6:0]  o_io_hex6,
    output logic [ 6:0]  o_io_hex7,

    output logic [31:0]  o_pc_debug,
    output logic         o_insn_vld,

    // VPU debug/observe outputs
    output logic [3:0]   o_vpu_cycles,
    output logic [15:0]  o_vmask16,
    output logic         o_vpu_busy,
    output logic [3:0]   o_fsm_state,
    output logic [31:0]  o_wb_result_lane0,
    output logic [31:0]  o_wb_result_lane1,
    output logic [31:0]  o_wb_result_lane2,
    output logic [31:0]  o_wb_result_lane3
);

    logic rst_n;
    assign rst_n = ~i_reset;

    //==================================================================
    // Scalar DMEM wires (pipelined_vpu → dmem_sync)
    //==================================================================
    logic [31:0] s_dmem_addr;
    logic [31:0] s_dmem_wdata;
    logic        s_dmem_we;
    logic [ 3:0] s_dmem_be;
    logic        s_dmem_re;
    logic [31:0] s_dmem_rdata;

    //==================================================================
    // VLSU DMEM wires (vproc_system_wrapper → dmem_sync)
    //==================================================================
    logic        vlsu_req;
    logic        vlsu_we;
    logic [31:0] vlsu_addr;
    logic [ 3:0] vlsu_be;
    logic [31:0] vlsu_wdata;
    logic [31:0] vlsu_rdata;
    logic        vlsu_ready;

    //==================================================================
    // VPU dispatch wires (pipelined_vpu ↔ vproc_system_wrapper)
    //==================================================================
    logic        vpu_ready;
    logic        vpu_cfg_done;
    logic [31:0] vpu_vl_remain;
    logic        vpu_insn_vld;
    logic [31:0] vpu_insn;
    logic [31:0] vpu_rs1_data;
    logic [31:0] vpu_rs2_data;

    //==================================================================
    // Core (5-stage pipeline)
    //==================================================================
    pipelined_vpu u_core (
        .i_clk           (i_clk),
        .i_reset         (i_reset),
        .i_io_sw         (i_io_sw),
        .o_io_ledr       (o_io_ledr),
        .o_io_ledg       (o_io_ledg),
        .o_io_lcd        (o_io_lcd),
        .o_io_hex0       (o_io_hex0),
        .o_io_hex1       (o_io_hex1),
        .o_io_hex2       (o_io_hex2),
        .o_io_hex3       (o_io_hex3),
        .o_io_hex4       (o_io_hex4),
        .o_io_hex5       (o_io_hex5),
        .o_io_hex6       (o_io_hex6),
        .o_io_hex7       (o_io_hex7),
        .o_pc_debug      (o_pc_debug),
        .o_insn_vld      (o_insn_vld),
        // Scalar DMEM
        .s_dmem_addr_o   (s_dmem_addr),
        .s_dmem_wdata_o  (s_dmem_wdata),
        .s_dmem_we_o     (s_dmem_we),
        .s_dmem_be_o     (s_dmem_be),
        .s_dmem_re_o     (s_dmem_re),
        .s_dmem_rdata_i  (s_dmem_rdata),
        // VPU
        .vpu_ready_i     (vpu_ready),
        .vpu_cfg_done_i  (vpu_cfg_done),
        .vpu_vl_remain_i (vpu_vl_remain),
        .vpu_insn_vld_o  (vpu_insn_vld),
        .vpu_insn_o      (vpu_insn),
        .vpu_rs1_data_o  (vpu_rs1_data),
        .vpu_rs2_data_o  (vpu_rs2_data)
    );

    //==================================================================
    // Synchronous Data Memory (64 KB)
    //==================================================================
    dmem_sync #(
        .DEPTH(16384)   // 64 KB
    ) u_dmem (
        .clk       (i_clk),
        .rst_n     (rst_n),
        // Scalar port
        .s_addr    (s_dmem_addr),
        .s_wdata   (s_dmem_wdata),
        .s_we      (s_dmem_we),
        .s_be      (s_dmem_be),
        .s_re      (s_dmem_re),
        .s_rdata   (s_dmem_rdata),
        // VLSU port
        .vlsu_req  (vlsu_req),
        .vlsu_we   (vlsu_we),
        .vlsu_addr (vlsu_addr),
        .vlsu_be   (vlsu_be),
        .vlsu_wdata(vlsu_wdata),
        .vlsu_rdata(vlsu_rdata),
        .vlsu_ready(vlsu_ready),
        .vid_addr  (14'h0),
        .vid_re    (1'b0),
        .vid_rdata ()
    );

    //==================================================================
    // Vector Processing Unit
    //==================================================================
    vproc_system_wrapper u_vpu (
        .clk              (i_clk),
        .rst_n            (rst_n),
        // Issue interface
        .instr_valid      (vpu_insn_vld),
        .instruction      (vpu_insn),
        .rs1_scalar_data  (vpu_rs1_data),
        .rs2_scalar_data  (vpu_rs2_data),
        // VRF commit (always enabled — FSM controls internally)
        .vrf_commit_en    (1'b1),
        // Debug outputs
        .cycles           (o_vpu_cycles),
        .vmask16          (o_vmask16),
        .fifo_full        (),
        .busy             (o_vpu_busy),
        .fsm_state        (o_fsm_state),
        .wb_result_lane0  (o_wb_result_lane0),
        .wb_result_lane1  (o_wb_result_lane1),
        .wb_result_lane2  (o_wb_result_lane2),
        .wb_result_lane3  (o_wb_result_lane3),
        // Handshake
        .vpu_ready        (vpu_ready),
        .vpu_cfg_done     (vpu_cfg_done),
        .vpu_vl_remain    (vpu_vl_remain),
        // CSR access (unused for basic operation)
        .csr_vl_o         (),
        .csr_vtype_o      (),
        .csr_vlenb_o      (),
        .scalar_csr_addr  (12'b0),
        .scalar_csr_rdata (),
        // VLSU DMEM
        .vlsu_mem_req     (vlsu_req),
        .vlsu_mem_we      (vlsu_we),
        .vlsu_mem_addr    (vlsu_addr),
        .vlsu_mem_be      (vlsu_be),
        .vlsu_mem_wdata   (vlsu_wdata),
        .vlsu_mem_rdata   (vlsu_rdata),
        .vlsu_mem_ready   (vlsu_ready),
        .vlsu_busy_o      ()
    );

endmodule
