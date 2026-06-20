// =============================================================================
// de10_lena_demo_top.sv — Minimal VGA demo: Lena grayscale from ROM, no UART.
//
// Pipeline (all on pclk = 25 MHz):
//   vga_timing → address gen → lena_rom → vga_ctrl pixel mux → ADV7123
//
// Reuses:
//   vga_timing.sv  (existing)
//   vga_ctrl.sv    (existing — vid_addr/vid_rdata interface)
//   pll.qip        (existing — 50 MHz → 25 MHz)
//   lena_rom.sv    (new, this PR)
//
// Setup before compile:
//   copy sw/benchmarks/lena_gray/lena_y_reference.hex
//        → <quartus_project>/lena_rom.hex
// =============================================================================
module de10_lena_demo_top (
    input  logic        CLOCK_50,
    input  logic [1:0]  KEY,        // KEY[0] active-low reset

    // VGA — ADV7123 DAC
    output logic [7:0]  VGA_R,
    output logic [7:0]  VGA_G,
    output logic [7:0]  VGA_B,
    output logic        VGA_CLK,
    output logic        VGA_HS,
    output logic        VGA_VS,
    output logic        VGA_BLANK_N,
    output logic        VGA_SYNC_N,

    // Keep unused board I/O quiet (no latch warnings)
    output logic [9:0]  LEDR,
    output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,

    // Tie-off UART (not used)
    input  logic        GPIO_0_RX,
    output logic        GPIO_0_TX
);
    // ── Tie-offs ──────────────────────────────────────────────────────────────
    assign LEDR  = 10'b0;
    assign HEX0  = 7'h7F; assign HEX1 = 7'h7F; assign HEX2 = 7'h7F;
    assign HEX3  = 7'h7F; assign HEX4 = 7'h7F; assign HEX5 = 7'h7F;
    assign GPIO_0_TX = 1'b1;    // UART idle high

    // ── PLL: 50 MHz → 25 MHz pixel clock ─────────────────────────────────────
    logic pclk, pll_locked;
    pll u_pll (
        .refclk   (CLOCK_50),
        .rst      (1'b0),
        .outclk_0 (),           // unused
        .outclk_1 (pclk),
        .locked   (pll_locked)
    );

    logic rst_n;
    assign rst_n = KEY[0] & pll_locked;   // KEY[0]=1 normal; =0 reset (active-low)

    // ── VGA controller (reads from lena_rom via vid_* interface) ─────────────
    logic [13:0] vid_addr;
    logic        vid_re;
    logic [31:0] vid_rdata;

    vga_ctrl u_vga (
        .pclk         (pclk),
        .rst_n        (rst_n),
        .vid_addr_o   (vid_addr),
        .vid_re_o     (vid_re),
        .vid_rdata_i  (vid_rdata),
        .vga_r_o      (VGA_R),
        .vga_g_o      (VGA_G),
        .vga_b_o      (VGA_B),
        .vga_clk_o    (VGA_CLK),
        .vga_hs_o     (VGA_HS),
        .vga_vs_o     (VGA_VS),
        .vga_blank_n_o(VGA_BLANK_N),
        .vga_sync_n_o (VGA_SYNC_N)
    );

    // ── Lena ROM ──────────────────────────────────────────────────────────────
    lena_rom u_rom (
        .clk   (pclk),
        .addr  (vid_addr),
        .re    (vid_re),
        .rdata (vid_rdata)
    );

endmodule
