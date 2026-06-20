// imem_sync.sv — Wrapper for 4 × altsyncram ROM:1-PORT (8-bit × 2048 each).
//
// IP configuration (set inside each IP during Quartus generation):
//   OPERATION_MODE   = ROM
//   WIDTH_A          = 8,  NUMWORDS_A = 2048,  WIDTHAD_A = 11
//   OUTDATA_REG_A    = UNREGISTERED   ← address registered inside M10K,
//                                       output is combinational (no output FF)
//   MIF path baked into each IP at generation time.
//
// Why UNREGISTERED output:
//   The wrapper needs to inject NOP on flush in the same cycle (aligning with
//   the original imem_sync behavior). With a registered IP output we cannot
//   override the FF that cycle. UNREGISTERED output gives combinational q_raw;
//   the wrapper's always_ff then provides the single pipeline register with
//   full flush/stall control. Total latency = 1 cycle (same as before).
//
// Simulation: compile fpga/ip/imem_b0..b3.sv (behavioral, UNREGISTERED model).

module imem_sync #(
    parameter int DEPTH = 2048
) (
    input  logic        clk,
    input  logic        reset,   // active-high synchronous
    input  logic        flush,   // inject NOP (branch/jump taken)
    input  logic        stall,   // hold current output
    input  logic [31:0] pc,
    output logic [31:0] instr
);
    localparam int AW = $clog2(DEPTH);
    localparam logic [31:0] NOP = 32'h00000013;

    wire [AW-1:0] word_addr = pc[AW+1:2];

    // ── 4 × altsyncram ROM:1-PORT instantiation ────────────────────────────────
    // Synthesis: Quartus replaces these with the real QIP modules.
    // Simulation: fpga/ip/imem_b0..b3.sv behavioral models.
    logic [7:0] q0, q1, q2, q3;

    imem_b0 u_b0 (.clock(clk), .address(word_addr), .q(q0));
    imem_b1 u_b1 (.clock(clk), .address(word_addr), .q(q1));
    imem_b2 u_b2 (.clock(clk), .address(word_addr), .q(q2));
    imem_b3 u_b3 (.clock(clk), .address(word_addr), .q(q3));

    wire [31:0] q_raw = {q3, q2, q1, q0};  // little-endian concatenation

    // ── Output register: flush / stall / reset control ─────────────────────────
    // q_raw is combinational (UNREGISTERED IP mode) → this FF is the only
    // pipeline register; captures NOP or ROM data each cycle.
    always_ff @(posedge clk) begin
        if (reset || flush)    instr <= NOP;
        else if (!stall)       instr <= q_raw;
    end

endmodule
