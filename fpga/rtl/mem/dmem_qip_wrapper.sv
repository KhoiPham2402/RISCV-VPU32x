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
// Single shared logical port: the scalar core, VPU/VLSU and video/VGA no
// longer get their own dedicated physical port each — they arbitrate for
// this one port through fpga/rtl/bus/dmem_arbiter.sv, the same way any other
// bus-attached peripheral (e.g. UART) is accessed. Only Port A of the
// underlying M10K banks is used; Port B is tied off and could be reclaimed
// later by regenerating dmem_bank as a single-port altsyncram.
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

    input  logic        re,
    input  logic        we,
    input  logic [31:0] addr,
    input  logic [ 3:0] be,
    input  logic [31:0] wdata,
    output logic [31:0] rdata
);
    localparam int AW = $clog2(DEPTH);   // 14 bits for 16384 words

    wire [AW-1:0] word  = addr[AW+1:2];
    wire [3:0]    wren  = {4{we}} & be;

    // ── 4 × 8-bit True Dual-Port M10K banks (Port A only; Port B tied off) ──
    // Each dmem_bank_bN wrapper sets init_file = "dmem_bN.mif" via defparam,
    // pre-loading Lena RGB at synthesis time (no UART needed).
    // MIF layout: words 0-4095=R, 4096-8191=G, 8192-12287=B, 12288-16383=0.
    dmem_bank_b0 bank0 (
        .clock     (clk),
        .address_a (word),   .data_a    (wdata[ 7: 0]),
        .wren_a    (wren[0]),.rden_a    (re),
        .q_a       (rdata[ 7: 0]),
        .address_b ('0),     .data_b    (8'h0),
        .wren_b    (1'b0),   .rden_b    (1'b0),
        .q_b       ()
    );
    dmem_bank_b1 bank1 (
        .clock     (clk),
        .address_a (word),   .data_a    (wdata[15: 8]),
        .wren_a    (wren[1]),.rden_a    (re),
        .q_a       (rdata[15: 8]),
        .address_b ('0),     .data_b    (8'h0),
        .wren_b    (1'b0),   .rden_b    (1'b0),
        .q_b       ()
    );
    dmem_bank_b2 bank2 (
        .clock     (clk),
        .address_a (word),   .data_a    (wdata[23:16]),
        .wren_a    (wren[2]),.rden_a    (re),
        .q_a       (rdata[23:16]),
        .address_b ('0),     .data_b    (8'h0),
        .wren_b    (1'b0),   .rden_b    (1'b0),
        .q_b       ()
    );
    dmem_bank_b3 bank3 (
        .clock     (clk),
        .address_a (word),   .data_a    (wdata[31:24]),
        .wren_a    (wren[3]),.rden_a    (re),
        .q_a       (rdata[31:24]),
        .address_b ('0),     .data_b    (8'h0),
        .wren_b    (1'b0),   .rden_b    (1'b0),
        .q_b       ()
    );

endmodule
