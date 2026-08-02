// =============================================================================
// dmem_arbiter.sv
//
// Single shared-port DMEM bus arbiter — 3 masters, 1 memory port.
// Replaces the old true-dual-port dmem_qip_wrapper (separate scalar + VLSU
// physical ports): DMEM is now accessed through arbitration, the same way
// UART already is, so future SoC peripherals attach via a shared bus rather
// than a dedicated memory port each.
//
// Priority (fixed, per architectural decision): VLSU (M0) > scalar (M1) >
// video/VGA (M2). VLSU always wins on contention, so vproc_vec_lsu.sv's
// one-word-ahead prefetch (which has no retry logic on a denied request)
// never actually sees a stall — m0_ready_o reproduces the exact timing the
// old dedicated VLSU port gave it. Scalar core stalls via m1_stall_o
// (pipelined_vpu.sv s_dmem_stall_i) on contention. Video keeps the same
// hold-register technique the old dmem_qip_wrapper used locally, now driven
// by the arbiter's read-grant pipeline instead of Port-A-local logic.
//
// Fixed 1-cycle read latency for whichever master is granted, no ready/valid
// handshake on the downstream memory port — deliberately not a full
// TileLink-UL bus, since every slave here (M10K DMEM) is fixed-latency and
// the extra backpressure plumbing would be unused complexity.
// =============================================================================

module dmem_arbiter #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 32,
    parameter int VID_AW = 14
) (
    input  logic              clk,
    input  logic              rst_n,

    // ── M0: VLSU (highest priority) ─────────────────────────────────────────
    input  logic               m0_req_i,
    input  logic               m0_we_i,
    input  logic [ADDR_W-1:0]  m0_addr_i,
    input  logic [3:0]         m0_be_i,
    input  logic [DATA_W-1:0]  m0_wdata_i,
    output logic [DATA_W-1:0]  m0_rdata_o,
    output logic               m0_ready_o,

    // ── M1: scalar core ─────────────────────────────────────────────────────
    input  logic               m1_re_i,
    input  logic               m1_we_i,
    input  logic [ADDR_W-1:0]  m1_addr_i,
    input  logic [3:0]         m1_be_i,
    input  logic [DATA_W-1:0]  m1_wdata_i,
    output logic [DATA_W-1:0]  m1_rdata_o,
    output logic               m1_stall_o,

    // ── M2: video / VGA (read-only, lowest priority) ────────────────────────
    input  logic [VID_AW-1:0]  m2_addr_i,
    input  logic               m2_re_i,
    output logic [DATA_W-1:0]  m2_rdata_o,

    // ── Downstream single memory port ───────────────────────────────────────
    output logic               mem_re_o,
    output logic               mem_we_o,
    output logic [ADDR_W-1:0]  mem_addr_o,
    output logic [3:0]         mem_be_o,
    output logic [DATA_W-1:0]  mem_wdata_o,
    input  logic [DATA_W-1:0]  mem_rdata_i     // valid 1 cycle after mem_re_o/we_o
);

    // ── Grant logic (fixed priority: M0 > M1 > M2) ──────────────────────────
    logic m1_req;
    logic m0_gnt, m1_gnt, m2_gnt;

    assign m1_req = m1_re_i | m1_we_i;

    assign m0_gnt = m0_req_i;
    assign m1_gnt = m1_req & ~m0_req_i;
    assign m2_gnt = m2_re_i & ~m0_req_i & ~m1_req;

    assign m1_stall_o = m1_req & ~m1_gnt;

    // ── Downstream port mux ──────────────────────────────────────────────────
    always_comb begin
        mem_re_o    = 1'b0;
        mem_we_o    = 1'b0;
        mem_addr_o  = '0;
        mem_be_o    = 4'b0000;
        mem_wdata_o = '0;
        if (m0_gnt) begin
            mem_re_o    = ~m0_we_i;
            mem_we_o    = m0_we_i;
            mem_addr_o  = m0_addr_i;
            mem_be_o    = m0_be_i;
            mem_wdata_o = m0_wdata_i;
        end else if (m1_gnt) begin
            mem_re_o    = m1_re_i;
            mem_we_o    = m1_we_i;
            mem_addr_o  = m1_addr_i;
            mem_be_o    = m1_be_i;
            mem_wdata_o = m1_wdata_i;
        end else if (m2_gnt) begin
            mem_re_o    = 1'b1;
            mem_addr_o  = {{(ADDR_W-VID_AW-2){1'b0}}, m2_addr_i, 2'b00};
        end
    end

    // ── Read-grant pipeline: which master's read is landing on mem_rdata_i ──
    logic rd0_r, rd2_r;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd0_r <= 1'b0;
            rd2_r <= 1'b0;
        end else begin
            rd0_r <= m0_gnt & ~m0_we_i;
            rd2_r <= m2_gnt;
        end
    end

    assign m0_rdata_o = mem_rdata_i;
    assign m1_rdata_o = mem_rdata_i;   // consumed by scalar exactly 1 cycle after grant

    // m0_ready_o reproduces the old dmem_qip_wrapper's vlsu_ready semantics
    // exactly: writes ack the same cycle they're granted, reads ack 1 cycle
    // later (M10K registered output).
    assign m0_ready_o = m0_we_i ? m0_req_i : rd0_r;

    // ── Video hold register ──────────────────────────────────────────────────
    // Keeps the last valid video pixel word stable on any cycle video loses
    // arbitration (to M0 or M1) — same technique as the old dmem_qip_wrapper's
    // vid_rdata_hold/a_was_video_r, now driven by the arbiter grant.
    logic [DATA_W-1:0] m2_hold_r;

    always_ff @(posedge clk) begin
        if (!rst_n)     m2_hold_r <= '0;
        else if (rd2_r) m2_hold_r <= mem_rdata_i;
    end

    assign m2_rdata_o = rd2_r ? mem_rdata_i : m2_hold_r;

endmodule
