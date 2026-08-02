// =============================================================================
// riscv_vpu_top_fpga.sv  —  FPGA top-level (Cyclone V, Quartus 18.1)
//
// Memory map:
//   0x0000_0000 – 0x0000_1FFF  IMEM  8 KB  (instruction, read-only via imem_sync)
//   0x0000_0000 – 0x0000_FFFF  DMEM  64 KB (data, dual-port M10K)
//   0xFF00_0000 – 0xFF00_00FF  UART  MMIO  (mapped via TL-UL inline)
//
// Bus architecture:
//   Scalar core → address decode → UART TL-UL (0xFF00_00xx)
//                               └→ dmem_arbiter M1 (0x0000_xxxx)
//   VLSU        → dmem_arbiter M0 (highest priority)
//   VGA         → dmem_arbiter M2 (lowest priority)
//   dmem_arbiter → single shared DMEM port (dmem_qip_wrapper) — VLSU wins any
//   contention, scalar stalls and retries (see pipelined_vpu.sv s_dmem_stall_i)
// =============================================================================
import tl_pkg::*;

module riscv_vpu_top_fpga #(
    parameter int UART_CLK_FREQ  = 40_000_000,
    parameter int UART_BAUD_RATE = 115_200
) (
    input  logic        i_clk,
    input  logic        i_reset,    // active-high

    // ── Board I/O ─────────────────────────────────────────────────────────────
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

    // ── UART ──────────────────────────────────────────────────────────────────
    input  logic        uart_rx,
    output logic        uart_tx,

    // ── VGA (ADV7123 on DE10-Standard) ───────────────────────────────────────
    output logic [7:0]  vga_r,          // VGA_R[7:0]
    output logic [7:0]  vga_g,          // VGA_G[7:0]
    output logic [7:0]  vga_b,          // VGA_B[7:0]
    output logic        vga_clk,        // VGA_CLK
    output logic        vga_hs,         // VGA_HS  (active-low)
    output logic        vga_vs,         // VGA_VS  (active-low)
    output logic        vga_blank_n,    // VGA_BLANK_N
    output logic        vga_sync_n,     // VGA_SYNC_N (tied low)

    // ── Debug observe ─────────────────────────────────────────────────────────
    output logic [31:0] o_pc_debug,
    output logic        o_insn_vld,
    output logic [3:0]  o_vpu_cycles,
    output logic [15:0] o_vmask16,
    output logic        o_vpu_busy,
    output logic [3:0]  o_fsm_state,
    output logic [31:0] o_wb_result_lane0,
    output logic [31:0] o_wb_result_lane1,
    output logic [31:0] o_wb_result_lane2,
    output logic [31:0] o_wb_result_lane3
);

    // =========================================================================
    // PLL — 50 MHz ref → outclk_0: 40 MHz sclk, outclk_1: 25 MHz pclk
    // =========================================================================
    logic sclk;               // 40 MHz system clock (from PLL outclk_0)
    // NOTE: pclk_int (PLL outclk_1, 25 MHz) is a fixed output of the generated
    // `pll` IP and must stay wired here, but it is intentionally unused — VGA/
    // HDMI is clocked from `sclk` instead to eliminate a CDC (see u_vga_ctrl
    // below). Left connected rather than floating so a Quartus IP resync
    // doesn't silently drop the port; not a leftover from a prior design.
    logic pclk_int;
    logic pll_locked;
    logic rst_n;
    // Hold reset until PLL is locked so sclk is stable.
    assign rst_n = ~i_reset & pll_locked;

    pll u_pll (
        .refclk   (i_clk),
        .rst      (1'b0),
        .outclk_0 (sclk),      // 40 MHz system clock
        .outclk_1 (pclk_int),  // 25 MHz, unused — see NOTE above
        .locked   (pll_locked)
    );

    // =========================================================================
    // Internal wires
    // =========================================================================

    // Scalar DMEM flat ports (from pipelined_vpu)
    logic [31:0] s_dmem_addr;
    logic [31:0] s_dmem_wdata;
    logic        s_dmem_we;
    logic [ 3:0] s_dmem_be;
    logic        s_dmem_re;
    logic [31:0] s_dmem_rdata;   // muxed: DMEM or UART
    logic        s_dmem_stall;   // from dmem_arbiter: denied this cycle (VLSU priority)

    // Downstream single memory port (dmem_arbiter -> dmem_qip_wrapper)
    logic        dmem_re_p, dmem_we_p;
    logic [31:0] dmem_addr_p, dmem_wdata_p, dmem_rdata_p;
    logic [ 3:0] dmem_be_p;

    // Video read port wires (VGA controller → DMEM)
    logic [13:0] vid_addr;
    logic        vid_re;
    logic [31:0] vid_rdata;

    // VLSU DMEM wires
    logic        vlsu_req;
    logic        vlsu_we;
    logic [31:0] vlsu_addr;
    logic [ 3:0] vlsu_be;
    logic [31:0] vlsu_wdata;
    logic [31:0] vlsu_rdata;
    logic        vlsu_ready;

    // VPU dispatch wires
    logic        vpu_ready;
    logic        vpu_cfg_done;
    logic [31:0] vpu_vl_remain;
    logic        vpu_insn_vld;
    logic [31:0] vpu_insn;
    logic [31:0] vpu_rs1_data;
    logic [31:0] vpu_rs2_data;

    // =========================================================================
    // UART address decode  (0xFF00_00xx)
    // =========================================================================
    wire uart_sel = (s_dmem_addr[31:8] == 24'hFF0000);

    // Gate DMEM scalar port: block UART-addressed transactions from reaching DMEM
    wire dmem_we = s_dmem_we & ~uart_sel;
    wire dmem_re = s_dmem_re & ~uart_sel;

    // DMEM scalar read data (registered inside dmem_qip_wrapper, 1-cycle latency)
    logic [31:0] dmem_rdata;

    // =========================================================================
    // Inline TL-UL master → UART
    // Scalar core drives tl_a; UART responds combinatorially on tl_d.
    // We register tl_d.data to align with the 1-cycle DMEM read latency so
    // the scalar core always sees data 1 cycle after its read request.
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

    // Latch UART read data + sel to align with 1-cycle DMEM latency
    logic        uart_rd_pending_r;
    logic [31:0] uart_rdata_r;
    always_ff @(posedge sclk) begin
        if (!rst_n) begin
            uart_rd_pending_r <= 1'b0;
            uart_rdata_r      <= 32'h0;
        end else begin
            uart_rd_pending_r <= uart_sel & s_dmem_re;
            uart_rdata_r      <= uart_tl_d.data;
        end
    end

    // s_dmem_rdata mux: UART wins when pending, else DMEM
    assign s_dmem_rdata = uart_rd_pending_r ? uart_rdata_r : dmem_rdata;

    // =========================================================================
    // UART instance
    // =========================================================================
    uart #(
        .CLK_FREQ (UART_CLK_FREQ),
        .BAUD_RATE(UART_BAUD_RATE)
    ) u_uart (
        .clk     (sclk),
        .rst_n   (rst_n),
        .uart_rx (uart_rx),
        .uart_tx (uart_tx),
        .tl_a    (uart_tl_a),
        .tl_d    (uart_tl_d)
    );

    // =========================================================================
    // Scalar core (5-stage pipeline)
    // =========================================================================
    pipelined_vpu u_core (
        .i_clk           (sclk),
        .i_reset         (~rst_n),   // gated by pll_locked: scalar core waits for PLL
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
        .s_dmem_stall_i  (s_dmem_stall),
        .vpu_ready_i     (vpu_ready),
        .vpu_cfg_done_i  (vpu_cfg_done),
        .vpu_vl_remain_i (vpu_vl_remain),
        .vpu_insn_vld_o  (vpu_insn_vld),
        .vpu_insn_o      (vpu_insn),
        .vpu_rs1_data_o  (vpu_rs1_data),
        .vpu_rs2_data_o  (vpu_rs2_data)
    );

    // =========================================================================
    // Data Memory bus — single shared port, arbitrated (VLSU > scalar > video)
    // =========================================================================
    dmem_arbiter #(
        .ADDR_W(32), .DATA_W(32), .VID_AW(14)
    ) u_dmem_arb (
        .clk        (sclk),
        .rst_n      (rst_n),
        .m0_req_i   (vlsu_req),
        .m0_we_i    (vlsu_we),
        .m0_addr_i  (vlsu_addr),
        .m0_be_i    (vlsu_be),
        .m0_wdata_i (vlsu_wdata),
        .m0_rdata_o (vlsu_rdata),
        .m0_ready_o (vlsu_ready),
        .m1_re_i    (dmem_re),
        .m1_we_i    (dmem_we),
        .m1_addr_i  (s_dmem_addr),
        .m1_be_i    (s_dmem_be),
        .m1_wdata_i (s_dmem_wdata),
        .m1_rdata_o (dmem_rdata),
        .m1_stall_o (s_dmem_stall),
        .m2_addr_i  (vid_addr),
        .m2_re_i    (vid_re),
        .m2_rdata_o (vid_rdata),
        .mem_re_o   (dmem_re_p),
        .mem_we_o   (dmem_we_p),
        .mem_addr_o (dmem_addr_p),
        .mem_be_o   (dmem_be_p),
        .mem_wdata_o(dmem_wdata_p),
        .mem_rdata_i(dmem_rdata_p)
    );

    // 4 × 8-bit Quartus M10K single logical port (64 KB)
    dmem_qip_wrapper #(
        .DEPTH(16384)
    ) u_dmem (
        .clk  (sclk),
        .re   (dmem_re_p),
        .we   (dmem_we_p),
        .addr (dmem_addr_p),
        .be   (dmem_be_p),
        .wdata(dmem_wdata_p),
        .rdata(dmem_rdata_p)
    );

    // =========================================================================
    // VGA Controller (ADV7123, no I2C required)
    // =========================================================================
    vga_ctrl u_vga (
        .pclk         (sclk),          // 40 MHz = same clock as DMEM, eliminates CDC
        .rst_n        (rst_n),
        .mode_i       (i_io_sw[0]),     // SW[0]=0: grayscale, SW[0]=1: color RGB
        .vid_addr_o   (vid_addr),
        .vid_re_o     (vid_re),
        .vid_rdata_i  (vid_rdata),
        .vga_r_o      (vga_r),
        .vga_g_o      (vga_g),
        .vga_b_o      (vga_b),
        .vga_clk_o    (vga_clk),
        .vga_hs_o     (vga_hs),
        .vga_vs_o     (vga_vs),
        .vga_blank_n_o(vga_blank_n),
        .vga_sync_n_o (vga_sync_n)
    );

    // =========================================================================
    // Vector Processing Unit
    // =========================================================================
    vproc_system_wrapper u_vpu (
        .clk              (sclk),
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
