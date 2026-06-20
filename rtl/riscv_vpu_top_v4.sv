// =============================================================================
// riscv_vpu_top_v4.sv  —  Simulation top: pipelined RISC-V + VPU + UART
//
// Extends riscv_vpu_top_v3 with UART at 0xFF00_00xx.
//
// Address decode (scalar core only):
//   0x0000_xxxx → dmem_sync scalar port
//   0xFF00_00xx → UART TL-UL registers (inline decode, no arbiter needed)
//
// CLK_FREQ / BAUD_RATE are parameters so simulations can use a fast baud rate
// without changing firmware (firmware uses UART at whatever rate the hardware
// is configured for).  Default: 14_745_600 / 115_200 → baud_div = 7 (8 cycles/bit).
// =============================================================================
import tl_pkg::*;

module riscv_vpu_top_v4 #(
    parameter int CLK_FREQ  = 14_745_600,   // default: baud_div=7, 8 clk/bit
    parameter int BAUD_RATE = 115_200
) (
    input  logic        i_clk,
    input  logic        i_reset,            // active-high

    input  logic [31:0] i_io_sw,
    output logic [31:0] o_io_ledr,
    output logic [31:0] o_io_ledg,
    output logic [31:0] o_io_lcd,
    output logic [ 6:0] o_io_hex0,
    output logic [ 6:0] o_io_hex1,
    output logic [ 6:0] o_io_hex2,
    output logic [ 6:0] o_io_hex3,
    output logic [ 6:0] o_io_hex4,
    output logic [ 6:0] o_io_hex5,
    output logic [ 6:0] o_io_hex6,
    output logic [ 6:0] o_io_hex7,

    output logic [31:0] o_pc_debug,
    output logic        o_insn_vld,
    output logic [ 3:0] o_vpu_cycles,
    output logic [15:0] o_vmask16,
    output logic        o_vpu_busy,
    output logic [ 3:0] o_fsm_state,
    output logic [31:0] o_wb_result_lane0,
    output logic [31:0] o_wb_result_lane1,
    output logic [31:0] o_wb_result_lane2,
    output logic [31:0] o_wb_result_lane3,

    // UART pins
    input  logic        uart_rx,
    output logic        uart_tx
);

    logic rst_n;
    assign rst_n = ~i_reset;

    // =========================================================================
    // Internal wires
    // =========================================================================

    // Scalar DMEM flat ports
    logic [31:0] s_dmem_addr;
    logic [31:0] s_dmem_wdata;
    logic        s_dmem_we;
    logic [ 3:0] s_dmem_be;
    logic        s_dmem_re;
    logic [31:0] s_dmem_rdata;

    // VLSU DMEM wires
    logic        vlsu_req, vlsu_we;
    logic [31:0] vlsu_addr, vlsu_wdata, vlsu_rdata;
    logic [ 3:0] vlsu_be;
    logic        vlsu_ready;

    // VPU dispatch wires
    logic        vpu_ready, vpu_cfg_done;
    logic [31:0] vpu_vl_remain;
    logic        vpu_insn_vld;
    logic [31:0] vpu_insn, vpu_rs1_data, vpu_rs2_data;

    // =========================================================================
    // UART address decode  (0xFF00_00xx)
    // =========================================================================
    wire uart_sel = (s_dmem_addr[31:8] == 24'hFF0000);

    // Block UART-addressed transactions from DMEM
    wire dmem_we = s_dmem_we & ~uart_sel;
    wire dmem_re = s_dmem_re & ~uart_sel;

    logic [31:0] dmem_rdata;

    // =========================================================================
    // Inline TL-UL master → UART
    // =========================================================================
    tl_a_t uart_tl_a;
    tl_d_t uart_tl_d;

    always_comb begin
        uart_tl_a = TL_A_IDLE;
        if (uart_sel) begin
            if (s_dmem_we) begin
                uart_tl_a.valid   = 1'b1;
                uart_tl_a.opcode  = TL_A_PUT_PARTIAL;
                uart_tl_a.address = s_dmem_addr;
                uart_tl_a.mask    = s_dmem_be;
                uart_tl_a.data    = s_dmem_wdata;
                uart_tl_a.size    = 3'd2;
            end else if (s_dmem_re) begin
                uart_tl_a.valid   = 1'b1;
                uart_tl_a.opcode  = TL_A_GET;
                uart_tl_a.address = s_dmem_addr;
                uart_tl_a.size    = 3'd2;
            end
        end
    end

    // Register UART response to match 1-cycle DMEM read latency
    logic        uart_rd_pending_r;
    logic [31:0] uart_rdata_r;
    always_ff @(posedge i_clk) begin
        if (!rst_n) begin
            uart_rd_pending_r <= 1'b0;
            uart_rdata_r      <= 32'h0;
        end else begin
            uart_rd_pending_r <= uart_sel & s_dmem_re;
            uart_rdata_r      <= uart_tl_d.data;
        end
    end

    assign s_dmem_rdata = uart_rd_pending_r ? uart_rdata_r : dmem_rdata;

    // =========================================================================
    // UART
    // =========================================================================
    uart #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart (
        .clk    (i_clk),
        .rst_n  (rst_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .tl_a   (uart_tl_a),
        .tl_d   (uart_tl_d)
    );

    // =========================================================================
    // Scalar core (5-stage pipeline)
    // =========================================================================
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
        .s_dmem_addr_o   (s_dmem_addr),
        .s_dmem_wdata_o  (s_dmem_wdata),
        .s_dmem_we_o     (s_dmem_we),
        .s_dmem_be_o     (s_dmem_be),
        .s_dmem_re_o     (s_dmem_re),
        .s_dmem_rdata_i  (s_dmem_rdata),
        .vpu_ready_i     (vpu_ready),
        .vpu_cfg_done_i  (vpu_cfg_done),
        .vpu_vl_remain_i (vpu_vl_remain),
        .vpu_insn_vld_o  (vpu_insn_vld),
        .vpu_insn_o      (vpu_insn),
        .vpu_rs1_data_o  (vpu_rs1_data),
        .vpu_rs2_data_o  (vpu_rs2_data)
    );

    // =========================================================================
    // Synchronous Data Memory (64 KB)
    // =========================================================================
    dmem_sync #(
        .DEPTH(16384)
    ) u_dmem (
        .clk       (i_clk),
        .rst_n     (rst_n),
        .s_addr    (s_dmem_addr),
        .s_wdata   (s_dmem_wdata),
        .s_we      (dmem_we),
        .s_be      (s_dmem_be),
        .s_re      (dmem_re),
        .s_rdata   (dmem_rdata),
        .vlsu_req  (vlsu_req),
        .vlsu_we   (vlsu_we),
        .vlsu_addr (vlsu_addr),
        .vlsu_be   (vlsu_be),
        .vlsu_wdata(vlsu_wdata),
        .vlsu_rdata(vlsu_rdata),
        .vlsu_ready(vlsu_ready),
        // video port unused in simulation top (no HDMI)
        .vid_addr  (14'h0),
        .vid_re    (1'b0),
        .vid_rdata ()
    );

    // =========================================================================
    // Vector Processing Unit
    // =========================================================================
    vproc_system_wrapper u_vpu (
        .clk              (i_clk),
        .rst_n            (rst_n),
        .instr_valid      (vpu_insn_vld),
        .instruction      (vpu_insn),
        .rs1_scalar_data  (vpu_rs1_data),
        .rs2_scalar_data  (vpu_rs2_data),
        .vrf_commit_en    (1'b1),
        .cycles           (o_vpu_cycles),
        .vmask16          (o_vmask16),
        .fifo_full        (),
        .busy             (o_vpu_busy),
        .fsm_state        (o_fsm_state),
        .wb_result_lane0  (o_wb_result_lane0),
        .wb_result_lane1  (o_wb_result_lane1),
        .wb_result_lane2  (o_wb_result_lane2),
        .wb_result_lane3  (o_wb_result_lane3),
        .vpu_ready        (vpu_ready),
        .vpu_cfg_done     (vpu_cfg_done),
        .vpu_vl_remain    (vpu_vl_remain),
        .csr_vl_o         (),
        .csr_vtype_o      (),
        .csr_vlenb_o      (),
        .scalar_csr_addr  (12'b0),
        .scalar_csr_rdata (),
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
