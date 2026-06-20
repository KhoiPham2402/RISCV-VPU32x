// =============================================================================
// tl_ul_xbar.sv  —  TileLink-UL 1-Master / 2-Slave Crossbar
//
// Routes a single TL-UL master (CPU) to one of two slaves based on address:
//   Slave 0 (DMEM) : address[31:16] == 16'h0000  (0x0000_0000–0x0000_FFFF)
//   Slave 1 (UART) : address[31:8]  == 24'hFF0000 (0xFF00_00xx)
//
// Response latency: combinatorial path for slave 1 (UART regs),
//                   1-cycle registered path for slave 0 (DMEM).
// The CPU stall logic must hold channel A valid until channel D valid.
// =============================================================================
import tl_pkg::*;

module tl_ul_xbar (
    input  logic   clk,
    input  logic   rst_n,

    // ── Master port (CPU) ────────────────────────────────────────────────────
    input  tl_a_t  m_a,           // request from CPU
    output tl_d_t  m_d,           // response to CPU

    // ── Slave 0 port (DMEM) ─────────────────────────────────────────────────
    output tl_a_t  s0_a,
    input  tl_d_t  s0_d,

    // ── Slave 1 port (UART / IO) ─────────────────────────────────────────────
    output tl_a_t  s1_a,
    input  tl_d_t  s1_d
);
    // ── Address decode ────────────────────────────────────────────────────────
    logic sel1;   // 1 = route to slave 1 (UART/IO)
    assign sel1 = (m_a.address[31:8] == 24'hFF0000);

    // ── Fanout A channel to selected slave ───────────────────────────────────
    always_comb begin
        s0_a = TL_A_IDLE;
        s1_a = TL_A_IDLE;
        if (m_a.valid) begin
            if (sel1) s1_a = m_a;
            else      s0_a = m_a;
        end
    end

    // ── Mux D channel back to master ─────────────────────────────────────────
    assign m_d = sel1 ? s1_d : s0_d;

endmodule
