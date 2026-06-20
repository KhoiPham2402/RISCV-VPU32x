// =============================================================================
// tl_ul_dmem_adapter.sv  —  TL-UL slave adapter for dmem_sync
//
// Translates TL-UL channel A/D to the flat scalar port of dmem_sync.
// Read latency = 1 cycle (DMEM registered output).
//   - A channel captured → s_re asserted
//   - D channel driven 1 cycle later when DMEM data is valid
// Write latency = 0 cycles (D AccessAck same cycle as A).
// =============================================================================
import tl_pkg::*;

module tl_ul_dmem_adapter (
    input  logic   clk,
    input  logic   rst_n,

    // ── TL-UL slave port ────────────────────────────────────────────────────
    input  tl_a_t  tl_a,
    output tl_d_t  tl_d,

    // ── dmem_sync scalar port ────────────────────────────────────────────────
    output logic [31:0] s_addr,
    output logic [31:0] s_wdata,
    output logic        s_we,
    output logic [3:0]  s_be,
    output logic        s_re,
    input  logic [31:0] s_rdata   // valid 1 cycle after s_re
);
    // Pass address/data to DMEM directly
    assign s_addr  = tl_a.address;
    assign s_wdata = tl_a.data;
    assign s_be    = tl_a.mask;
    assign s_we    = tl_a.valid && (tl_a.opcode == TL_A_PUT_FULL || tl_a.opcode == TL_A_PUT_PARTIAL);
    assign s_re    = tl_a.valid && (tl_a.opcode == TL_A_GET);

    // D channel: writes get immediate ack; reads get data 1 cycle later
    logic        rd_pending_r;
    logic [2:0]  rd_size_r;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd_pending_r <= 1'b0;
            rd_size_r    <= 3'd2;
        end else begin
            rd_pending_r <= s_re;
            rd_size_r    <= tl_a.size;
        end
    end

    always_comb begin
        tl_d = TL_D_IDLE;
        if (rd_pending_r) begin
            // Read response (1 cycle after request)
            tl_d.valid  = 1'b1;
            tl_d.opcode = TL_D_ACCESS_ACK_DATA;
            tl_d.size   = rd_size_r;
            tl_d.data   = s_rdata;
            tl_d.error  = 1'b0;
        end else if (s_we) begin
            // Write ack (same cycle as request)
            tl_d.valid  = 1'b1;
            tl_d.opcode = TL_D_ACCESS_ACK;
            tl_d.size   = tl_a.size;
            tl_d.data   = 32'd0;
            tl_d.error  = 1'b0;
        end
    end

endmodule
