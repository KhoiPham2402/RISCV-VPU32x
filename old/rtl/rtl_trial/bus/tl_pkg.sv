// =============================================================================
// tl_pkg.sv  —  TileLink-UL (Uncached Lightweight) type definitions
//
// Implements the minimal TL-UL subset sufficient for single-beat, uncached
// reads and writes.  Based on TileLink Specification 1.8.0.
//
// Channel A  : master → slave  (request)
// Channel D  : slave  → master (response)
// =============================================================================
package tl_pkg;

    // ── Channel-A opcodes ────────────────────────────────────────────────────
    localparam logic [2:0] TL_A_PUT_FULL    = 3'd0;  // full-word write
    localparam logic [2:0] TL_A_PUT_PARTIAL = 3'd1;  // byte-masked write
    localparam logic [2:0] TL_A_GET         = 3'd4;  // read

    // ── Channel-D opcodes ────────────────────────────────────────────────────
    localparam logic [2:0] TL_D_ACCESS_ACK      = 3'd0;  // write ack (no data)
    localparam logic [2:0] TL_D_ACCESS_ACK_DATA = 3'd1;  // read ack (with data)

    // ── Channel-A request struct ─────────────────────────────────────────────
    typedef struct packed {
        logic [2:0]  opcode;   // GET / PUT_FULL / PUT_PARTIAL
        logic [2:0]  param;    // always 3'b000 for TL-UL
        logic [2:0]  size;     // log2(bytes): 0=1B,1=2B,2=4B
        logic [31:0] address;  // byte address
        logic [3:0]  mask;     // byte enables (PUT only)
        logic [31:0] data;     // write data (PUT only)
        logic        valid;    // request valid
    } tl_a_t;

    // ── Channel-D response struct ────────────────────────────────────────────
    typedef struct packed {
        logic [2:0]  opcode;   // ACCESS_ACK / ACCESS_ACK_DATA
        logic [2:0]  size;     // echoed from A
        logic [31:0] data;     // read data (GET only)
        logic        error;    // access error
        logic        valid;    // response valid
    } tl_d_t;

    // Default/null values
    localparam tl_a_t TL_A_IDLE = '{opcode:3'd0, param:3'd0, size:3'd2, address:32'd0,
                                     mask:4'b1111, data:32'd0, valid:1'b0};
    localparam tl_d_t TL_D_IDLE = '{opcode:3'd0, size:3'd2, data:32'd0,
                                     error:1'b0, valid:1'b0};

endpackage
