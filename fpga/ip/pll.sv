`timescale 1ns/1ps
// pll.sv — Behavioral PLL model (simulation only)
//
// Replaces the Quartus ALTPLL IP for simulation.
//   outclk_0 = refclk      (50 MHz pass-through, unused in design)
//   outclk_1 = refclk / 2  (25 MHz pixel clock)
//   locked   = 1 after 16 reference rising edges
//
// Generate the real IP in Quartus:
//   IP Catalog → Basic Functions → Clocks; PLLs and Resets → PLL (ALTPLL)
//   refclk=50 MHz, outclk_0=50 MHz, outclk_1=25 MHz.  Output name: pll → pll.qip

module pll (
    input  logic refclk,
    input  logic rst,
    output logic outclk_0,
    output logic outclk_1,
    output logic locked
);
    // 40 MHz behavioral: independent 25 ns half-period oscillator.
    // Not derived from refclk on purpose — simulation only.
    logic outclk_0_r = 1'b0;
    initial forever #12.5 outclk_0_r = ~outclk_0_r;
    assign outclk_0 = outclk_0_r;

    // Divide-by-2 pixel clock.
    // Initial 0 is required: without it outclk_1 starts as 'x', and ~x = x,
    // so the clock never toggles — vga_ctrl would never generate VGA signals.
    logic outclk_1_r = 1'b0;
    always_ff @(posedge refclk or posedge rst) begin
        if (rst) outclk_1_r <= 1'b0;
        else     outclk_1_r <= ~outclk_1_r;
    end
    assign outclk_1 = outclk_1_r;

    // Lock after 16 cycles.
    // lock_cnt and locked_r MUST have inline init (= 0) because rst is tied
    // to 1'b0 in the instantiation — the async-reset branch never fires, so
    // without init these signals start as X, poisoning rst_n = ~i_reset & locked.
    logic [4:0] lock_cnt  = '0;
    logic       locked_r  = 1'b0;
    assign locked = locked_r;

    always_ff @(posedge refclk or posedge rst) begin
        if (rst) begin
            lock_cnt <= '0;
            locked_r <= 1'b0;
        end else if (!locked_r) begin
            lock_cnt <= lock_cnt + 5'd1;
            if (lock_cnt == 5'd15) locked_r <= 1'b1;
        end
    end

endmodule
