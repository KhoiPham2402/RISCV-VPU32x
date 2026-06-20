// =============================================================================
// riscv_vpu_top_v2.sv  —  Trial Integration: RV32IM + VPU, Pipeline + Sync Mem
//
// Changes vs riscv_vpu_top.sv:
//   - Scalar core: 2-stage pipeline (scalar_core_v2) instead of single-cycle
//   - IMEM: synchronous 1-cycle latency (imem_sync)
//   - DMEM: synchronous 1-cycle read latency (dmem_sync), byte-enable writes
//   - UART: RX/TX serial interface, accessible at 0xFF00_00xx
//   - Bus : TileLink-UL 1M-2S (CPU → DMEM or UART)
//   - VPU: unchanged (vproc_system_wrapper), direct VLSU port to dmem_sync
//
// Top-level ports are identical to riscv_vpu_top.sv for testbench compatibility.
// Additional: uart_rx_i / uart_tx_o for serial data input.
// =============================================================================
import tl_pkg::*;

module riscv_vpu_top_v2 (
    input  logic         clk,
    input  logic         rst_n,

    // IO from board
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

    // Debug
    output logic [31:0]  pc_debug,
    output logic         insn_vld,

    // VPU debug
    output logic [3:0]   vpu_cycles,
    output logic [15:0]  vpu_vmask16,
    output logic         vpu_fifo_full,
    output logic         vpu_busy,
    output logic [3:0]   vpu_fsm_state,
    output logic [31:0]  vpu_wb_lane0,
    output logic [31:0]  vpu_wb_lane1,
    output logic [31:0]  vpu_wb_lane2,
    output logic [31:0]  vpu_wb_lane3,

    // UART
    input  logic         uart_rx,
    output logic         uart_tx
);
    // =========================================================================
    // Scalar ↔ VPU wires
    // =========================================================================
    logic        vpu_ready;
    logic        vpu_cfg_done;
    logic [31:0] vpu_vl_remain;
    logic        vpu_insn_vld;
    logic [31:0] vpu_insn;
    logic [31:0] vpu_rs1_data;
    logic [31:0] vpu_rs2_data;
    logic [11:0] scalar_csr_addr;
    logic [31:0] scalar_csr_rdata;

    // =========================================================================
    // VLSU ↔ DMEM wires
    // =========================================================================
    logic        vlsu_req;
    logic        vlsu_we;
    logic [31:0] vlsu_addr;
    logic [3:0]  vlsu_be;
    logic [31:0] vlsu_wdata;
    logic [31:0] vlsu_rdata;
    logic        vlsu_ready;

    // =========================================================================
    // TL-UL wires
    // =========================================================================
    tl_a_t tl_a_cpu;    // CPU → xbar
    tl_d_t tl_d_cpu;    // xbar → CPU
    tl_a_t tl_a_dmem;   // xbar → DMEM adapter
    tl_d_t tl_d_dmem;   // DMEM adapter → xbar
    tl_a_t tl_a_uart;   // xbar → UART
    tl_d_t tl_d_uart;   // UART → xbar

    // =========================================================================
    // Scalar core (2-stage pipeline)
    // =========================================================================
    scalar_core_v2 u_scalar_core (
        .clk             (clk),
        .rst_n           (rst_n),

        .io_sw_i         (io_sw),
        .io_ledr_o       (io_ledr),
        .io_ledg_o       (io_ledg),
        .io_lcd_o        (io_lcd),
        .io_hex0_o       (io_hex0),
        .io_hex1_o       (io_hex1),
        .io_hex2_o       (io_hex2),
        .io_hex3_o       (io_hex3),
        .io_hex4_o       (io_hex4),
        .io_hex5_o       (io_hex5),
        .io_hex6_o       (io_hex6),
        .io_hex7_o       (io_hex7),

        .pc_debug_o      (pc_debug),
        .insn_vld_o      (insn_vld),

        .vpu_ready_i     (vpu_ready),
        .vpu_cfg_done_i  (vpu_cfg_done),
        .vpu_vl_remain_i (vpu_vl_remain),
        .vpu_insn_vld_o  (vpu_insn_vld),
        .vpu_insn_o      (vpu_insn),
        .vpu_rs1_data_o  (vpu_rs1_data),
        .vpu_rs2_data_o  (vpu_rs2_data),
        .csr_addr_o      (scalar_csr_addr),
        .csr_rdata_i     (scalar_csr_rdata),

        .tl_a_o          (tl_a_cpu),
        .tl_d_i          (tl_d_cpu)
    );

    // =========================================================================
    // TL-UL crossbar (1M-2S)
    // =========================================================================
    tl_ul_xbar u_xbar (
        .clk    (clk),
        .rst_n  (rst_n),
        .m_a    (tl_a_cpu),
        .m_d    (tl_d_cpu),
        .s0_a   (tl_a_dmem),
        .s0_d   (tl_d_dmem),
        .s1_a   (tl_a_uart),
        .s1_d   (tl_d_uart)
    );

    // =========================================================================
    // TL-UL → DMEM adapter
    // =========================================================================
    logic [31:0] dmem_s_addr, dmem_s_wdata, dmem_s_rdata;
    logic        dmem_s_we, dmem_s_re;
    logic [3:0]  dmem_s_be;

    tl_ul_dmem_adapter u_dmem_adapter (
        .clk     (clk),
        .rst_n   (rst_n),
        .tl_a    (tl_a_dmem),
        .tl_d    (tl_d_dmem),
        .s_addr  (dmem_s_addr),
        .s_wdata (dmem_s_wdata),
        .s_we    (dmem_s_we),
        .s_be    (dmem_s_be),
        .s_re    (dmem_s_re),
        .s_rdata (dmem_s_rdata)
    );

    // =========================================================================
    // Synchronous DMEM (64 KB)
    // =========================================================================
    dmem_sync #(.DEPTH(16384)) u_dmem (
        .clk        (clk),
        .rst_n      (rst_n),
        .s_addr     (dmem_s_addr),
        .s_wdata    (dmem_s_wdata),
        .s_we       (dmem_s_we),
        .s_be       (dmem_s_be),
        .s_re       (dmem_s_re),
        .s_rdata    (dmem_s_rdata),
        .vlsu_req   (vlsu_req),
        .vlsu_we    (vlsu_we),
        .vlsu_addr  (vlsu_addr),
        .vlsu_be    (vlsu_be),
        .vlsu_wdata (vlsu_wdata),
        .vlsu_rdata (vlsu_rdata),
        .vlsu_ready (vlsu_ready),
        .vid_addr   (14'h0),
        .vid_re     (1'b0),
        .vid_rdata  ()
    );

    // =========================================================================
    // UART (slave 1 on TL-UL bus)
    // =========================================================================
    uart #(
        .CLK_FREQ  (50_000_000),
        .BAUD_RATE (115_200)
    ) u_uart (
        .clk     (clk),
        .rst_n   (rst_n),
        .uart_rx (uart_rx),
        .uart_tx (uart_tx),
        .tl_a    (tl_a_uart),
        .tl_d    (tl_d_uart)
    );

    // =========================================================================
    // Vector Processing Unit (unchanged from v1)
    // =========================================================================
    vproc_system_wrapper u_vpu (
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
        .csr_vl_o        (),
        .csr_vtype_o     (),
        .csr_vlenb_o     (),
        .scalar_csr_addr (scalar_csr_addr),
        .scalar_csr_rdata(scalar_csr_rdata),

        .vlsu_mem_req    (vlsu_req),
        .vlsu_mem_we     (vlsu_we),
        .vlsu_mem_addr   (vlsu_addr),
        .vlsu_mem_be     (vlsu_be),
        .vlsu_mem_wdata  (vlsu_wdata),
        .vlsu_mem_rdata  (vlsu_rdata),
        .vlsu_busy_o     ()
    );

endmodule
