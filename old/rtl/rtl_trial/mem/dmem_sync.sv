// =============================================================================
// dmem_sync.sv  —  Synchronous dual-port data memory (64 KB)
//
// Models Quartus M10K True Dual-Port (altsyncram) behavior:
//   Port A = scalar core (read/write) OR video read (muxed, scalar has priority)
//   Port B = VLSU (read/write, fully independent)
//
// Timing matches M10K registered-output mode:
//   - Reads  : data valid 1 cycle after enable (OLD_DATA on same-cycle write)
//   - Writes : committed on posedge clk
//   - Simultaneous same-addr write from A+B: VLSU (B) wins — matches Quartus
//     "last write wins" for TDP same-addr conflict (undefined in spec, defined here)
//
// Port A address mux:
//   s_we=1 or s_re=1  →  scalar  (write or read)
//   vid_re=1 only     →  video   (read when scalar is idle)
// =============================================================================
module dmem_sync #(
    parameter int DEPTH = 16384   // 16384 × 32-bit = 64 KB
) (
    input  logic        clk,
    input  logic        rst_n,

    // ── Port A: scalar core ──────────────────────────────────────────────────
    input  logic [31:0] s_addr,
    input  logic [31:0] s_wdata,
    input  logic        s_we,
    input  logic [3:0]  s_be,
    input  logic        s_re,
    output logic [31:0] s_rdata,

    // ── Port B: VLSU ─────────────────────────────────────────────────────────
    input  logic        vlsu_req,
    input  logic        vlsu_we,
    input  logic [31:0] vlsu_addr,
    input  logic [3:0]  vlsu_be,
    input  logic [31:0] vlsu_wdata,
    output logic [31:0] vlsu_rdata,
    output logic        vlsu_ready,

    // ── Port A video mux: read-only, yields to scalar ────────────────────────
    input  logic [13:0] vid_addr,
    input  logic        vid_re,
    output logic [31:0] vid_rdata
);
    localparam int AW = $clog2(DEPTH);   // 14

    logic [31:0] mem [0:DEPTH-1];

    // ── Port A address / enable mux ──────────────────────────────────────────
    // Scalar (s_we or s_re) takes priority over video read.
    wire scalar_active = s_we | s_re;
    wire [AW-1:0] a_word = scalar_active ? s_addr[AW+1:2] : vid_addr;
    wire          a_rden = s_re | (vid_re & ~scalar_active);

    // ── Port A write (scalar) ─────────────────────────────────────────────────
    always_ff @(posedge clk) begin
        if (s_we) begin
            if (s_be[0]) mem[s_addr[AW+1:2]][ 7: 0] <= s_wdata[ 7: 0];
            if (s_be[1]) mem[s_addr[AW+1:2]][15: 8] <= s_wdata[15: 8];
            if (s_be[2]) mem[s_addr[AW+1:2]][23:16] <= s_wdata[23:16];
            if (s_be[3]) mem[s_addr[AW+1:2]][31:24] <= s_wdata[31:24];
        end
    end

    // ── Port B write (VLSU) ───────────────────────────────────────────────────
    // Separate always_ff = independent port, matching M10K TDP.
    // On same-addr conflict with Port A, VLSU NBA executes last → VLSU wins.
    always_ff @(posedge clk) begin
        if (vlsu_req && vlsu_we) begin
            if (vlsu_be[0]) mem[vlsu_addr[AW+1:2]][ 7: 0] <= vlsu_wdata[ 7: 0];
            if (vlsu_be[1]) mem[vlsu_addr[AW+1:2]][15: 8] <= vlsu_wdata[15: 8];
            if (vlsu_be[2]) mem[vlsu_addr[AW+1:2]][23:16] <= vlsu_wdata[23:16];
            if (vlsu_be[3]) mem[vlsu_addr[AW+1:2]][31:24] <= vlsu_wdata[31:24];
        end
    end

    // ── Port A read (scalar / video mux) — OLD_DATA (registered output) ──────
    // Both s_rdata and vid_rdata share the same registered output; the address
    // mux above ensures the correct word is latched for whichever port was active.
    logic [31:0] port_a_q;
    always_ff @(posedge clk) begin
        if (a_rden)
            port_a_q <= mem[a_word];
    end

    assign s_rdata   = port_a_q;
    assign vid_rdata = port_a_q;

    // ── Port B read (VLSU) — OLD_DATA ─────────────────────────────────────────
    always_ff @(posedge clk) begin
        if (vlsu_req && !vlsu_we)
            vlsu_rdata <= mem[vlsu_addr[AW+1:2]];
    end

    // ── Port B ready handshake ────────────────────────────────────────────────
    // Writes ack immediately (combinational); reads ack 1 cycle later.
    logic vlsu_rd_pending_r;
    always_ff @(posedge clk) begin
        if (!rst_n) vlsu_rd_pending_r <= 1'b0;
        else        vlsu_rd_pending_r <= vlsu_req & ~vlsu_we;
    end

    assign vlsu_ready = vlsu_we ? vlsu_req : vlsu_rd_pending_r;

    // ── Simulation-only: catch simultaneous same-address write conflict ────────
    // On real M10K TDP, same-cycle same-address writes from both ports corrupt
    // the word unpredictably. This should never fire in correct firmware because:
    //   (a) scalar writes DMEM[0x0000–0xBFFF], VLSU writes DMEM[0xC000–0xFFFF]
    //   (b) vpu_stall holds scalar (s_we=0) for the entire duration VLSU is busy
    // pragma translate_off
    always_ff @(posedge clk) begin
        if (s_we && vlsu_req && vlsu_we &&
            (s_addr[AW+1:2] == vlsu_addr[AW+1:2])) begin
            $display("[HAZARD] dmem_sync: Port A+B simultaneous write to word 0x%04x @ %0t",
                     s_addr[AW+1:2], $time);
            $display("         scalar  addr=0x%08x wdata=0x%08x be=%b", s_addr, s_wdata, s_be);
            $display("         vlsu    addr=0x%08x wdata=0x%08x be=%b", vlsu_addr, vlsu_wdata, vlsu_be);
        end
    end
    // pragma translate_on

endmodule
