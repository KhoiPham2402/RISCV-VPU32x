// =============================================================================
// dmem_qip_wrapper.sv
//
// 4 × 8-bit True Dual-Port M10K banks — implements 64 KB byte-addressable DMEM.
//
// Why 4×8 instead of 1×32 with byteena:
//   Cyclone V M10K in TDP + byteena mode: max depth = 512 words/block (only 1/8
//   of the 4096 words/block available without byteena).  4×8-bit uses simple
//   per-bank wren instead of byteena, keeping full 4096-word depth → 16 M10K
//   total vs 128 M10K with byteena.
//
// Port A → scalar core  (pipelined_vpu, s_* signals)
// Port B → VLSU         (vproc_vec_lsu, vlsu_* signals)
//
// HOW TO GENERATE dmem_bank in Quartus IP Catalog:
//   IP Catalog → Basic Functions → On Chip Memory → RAM: 2-PORT (altsyncram)
//     - "With two read/write ports" (True Dual-Port)
//     - Width    : 8 bits
//     - Depth    : 16384 words
//     - Byte enable: NO  (byte select handled externally via per-bank wren)
//     - Registered outputs on both ports (1-cycle latency)
//     - Read-during-write: OLD_DATA on both ports
//     - Single clock
//     - Target: M10K
//     - Output module name: dmem_bank
//   Generate once → add dmem_bank.qip to Quartus project.
//   This wrapper instantiates it 4 times, one per byte lane.
// =============================================================================

module dmem_qip_wrapper #(
    parameter int DEPTH = 16384    // 64 KB (must match IP configuration)
) (
    input  logic        clk,
    input  logic        rst_n,

    // ── Scalar port (from pipelined_vpu) ────────────────────────────────────
    input  logic [31:0] s_addr,
    input  logic [31:0] s_wdata,
    input  logic        s_we,
    input  logic [ 3:0] s_be,
    input  logic        s_re,
    output logic [31:0] s_rdata,

    // ── VLSU port (from vproc_vec_lsu) ──────────────────────────────────────
    input  logic        vlsu_req,
    input  logic        vlsu_we,
    input  logic [31:0] vlsu_addr,
    input  logic [ 3:0] vlsu_be,
    input  logic [31:0] vlsu_wdata,
    output logic [31:0] vlsu_rdata,
    output logic        vlsu_ready,

    // ── Video read port (read-only, 1-cycle latency, Port A mux) ────────────
    // Scalar reads have priority; video reads are issued when s_re = 0.
    input  logic [13:0] vid_addr,
    input  logic        vid_re,
    output logic [31:0] vid_rdata
);
    localparam int AW = $clog2(DEPTH);   // 14 bits for 16384 words

    // ── Word addresses ───────────────────────────────────────────────────────
    // Port A: scalar (read or write) has priority over video.
    // Bug fix: stores (s_we=1, s_re=0) must use s_addr, not vid_addr.
    wire scalar_active = s_re | s_we;
    wire [AW-1:0] a_word = scalar_active ? s_addr[AW+1:2] : vid_addr;
    wire [AW-1:0] b_word = vlsu_addr[AW+1:2];

    // ── Per-bank write enables (replaces byteena) ────────────────────────────
    // Byte enable is achieved by selectively enabling each 8-bit bank's wren.
    // Block video read when scalar write is in progress (address conflict).
    wire a_rden = s_re | (vid_re & ~s_we);
    wire b_rden = vlsu_req & ~vlsu_we;

    logic [31:0] port_a_q;

    wire [3:0] a_wren = {4{s_we}}           & s_be;
    wire [3:0] b_wren = {4{vlsu_req & vlsu_we}} & vlsu_be;

    // ── 4 × 8-bit True Dual-Port M10K banks ─────────────────────────────────
    // Each dmem_bank_bN wrapper sets init_file = "dmem_bN.mif" via defparam,
    // pre-loading Lena RGB at synthesis time (no UART needed).
    // MIF layout: words 0-4095=R, 4096-8191=G, 8192-12287=B, 12288-16383=0.
    dmem_bank_b0 bank0 (
        .clock     (clk),
        .address_a (a_word),        .data_a    (s_wdata   [ 7: 0]),
        .wren_a    (a_wren[0]),     .rden_a    (a_rden),
        .q_a       (port_a_q  [ 7: 0]),
        .address_b (b_word),        .data_b    (vlsu_wdata[ 7: 0]),
        .wren_b    (b_wren[0]),     .rden_b    (b_rden),
        .q_b       (vlsu_rdata[ 7: 0])
    );
    dmem_bank_b1 bank1 (
        .clock     (clk),
        .address_a (a_word),        .data_a    (s_wdata   [15: 8]),
        .wren_a    (a_wren[1]),     .rden_a    (a_rden),
        .q_a       (port_a_q  [15: 8]),
        .address_b (b_word),        .data_b    (vlsu_wdata[15: 8]),
        .wren_b    (b_wren[1]),     .rden_b    (b_rden),
        .q_b       (vlsu_rdata[15: 8])
    );
    dmem_bank_b2 bank2 (
        .clock     (clk),
        .address_a (a_word),        .data_a    (s_wdata   [23:16]),
        .wren_a    (a_wren[2]),     .rden_a    (a_rden),
        .q_a       (port_a_q  [23:16]),
        .address_b (b_word),        .data_b    (vlsu_wdata[23:16]),
        .wren_b    (b_wren[2]),     .rden_b    (b_rden),
        .q_b       (vlsu_rdata[23:16])
    );
    dmem_bank_b3 bank3 (
        .clock     (clk),
        .address_a (a_word),        .data_a    (s_wdata   [31:24]),
        .wren_a    (a_wren[3]),     .rden_a    (a_rden),
        .q_a       (port_a_q  [31:24]),
        .address_b (b_word),        .data_b    (vlsu_wdata[31:24]),
        .wren_b    (b_wren[3]),     .rden_b    (b_rden),
        .q_b       (vlsu_rdata[31:24])
    );

    // Scalar read: port_a_q is always valid (scalar had priority on address).
    assign s_rdata = port_a_q;

    // Video read: track whether Port A was used for video (not scalar) last cycle.
    // Without this, a scalar read in the same cycle contaminates vid_rdata with
    // scalar data, causing pixel corruption on the VGA display.
    logic a_was_video_r;
    always_ff @(posedge clk) begin
        if (!rst_n) a_was_video_r <= 1'b0;
        else        a_was_video_r <= vid_re & ~scalar_active;
    end

    // Hold register: keeps the last valid video pixel word stable when scalar
    // takes Port A. Updated every cycle that Port A was used for video.
    logic [31:0] vid_rdata_hold;
    always_ff @(posedge clk) begin
        if (!rst_n)             vid_rdata_hold <= 32'h0;
        else if (a_was_video_r) vid_rdata_hold <= port_a_q;
    end

    // Combinatorial mux: when port_a_q is fresh video data, use it directly
    // (zero extra latency); otherwise hold the last valid word.
    // This preserves the original 1-cycle DMEM read latency seen by vga_ctrl.
    assign vid_rdata = a_was_video_r ? port_a_q : vid_rdata_hold;

    // ── vlsu_ready handshake ─────────────────────────────────────────────────
    // Writes ack immediately; reads ack 1 cycle later (M10K registered output).
    logic vlsu_rd_pending_r;
    always_ff @(posedge clk) begin
        if (!rst_n) vlsu_rd_pending_r <= 1'b0;
        else        vlsu_rd_pending_r <= b_rden;
    end

    assign vlsu_ready = vlsu_we ? vlsu_req : vlsu_rd_pending_r;

endmodule
