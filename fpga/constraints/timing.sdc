# timing.sdc — Timing constraints for riscv_vpu on DE10-Standard (Cyclone V)
# Top-level: de10_standard_top → riscv_vpu_top_fpga

# ── Primary clock (50 MHz, CLOCK_50 pin P11) ──────────────────────────────────
create_clock -name clk -period 20.0 [get_ports CLOCK_50]

# ── PLL-derived clocks ────────────────────────────────────────────────────────
# derive_pll_clocks auto-creates generated_clock for each PLL output.
# outclk_0 = 40 MHz system clock (sclk), outclk_1 = 25 MHz pixel clock (pclk).
derive_pll_clocks

# ── System clock constraint (40 MHz = outclk_0) ───────────────────────────────
# Constrain paths in the sclk domain to 25 ns (40 MHz).
set_multicycle_path -from [get_clocks {*outclk_0*}] \
                    -to   [get_clocks {*outclk_0*}] \
                    -setup 1

# ── VGA output delay (now 40 MHz = outclk_0, same as sclk) ─────────────────
# VGA runs at sclk (40 MHz = 800x600@60Hz), no CDC with DMEM.
set_output_delay -clock [get_clocks {*outclk_0*}] -max 3.0 \
    [get_ports {VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS VGA_BLANK_N VGA_SYNC_N}]

set_false_path -to [get_ports VGA_CLK]

# ── UART I/O (sclk domain) ───────────────────────────────────────────────────
set_input_delay  -clock [get_clocks {*outclk_0*}] -max 8.0 [get_ports {GPIO_0_RX}]
set_output_delay -clock [get_clocks {*outclk_0*}] -max 8.0 [get_ports {GPIO_0_TX}]

# ── Board I/O: LEDs, HEX, switches ───────────────────────────────────────────
set_output_delay -clock [get_clocks {*outclk_0*}] -max 8.0 \
    [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]
set_input_delay  -clock [get_clocks {*outclk_0*}] -max 8.0 [get_ports {SW[*]}]

# ── Async reset ───────────────────────────────────────────────────────────────
set_false_path -from [get_ports {KEY[*]}]

# ── CDC: outclk_1 (25 MHz, unused for VGA) ───────────────────────────────────
# pclk_int (outclk_1) no longer connected to any logic. False path to suppress.
set_false_path -from [get_clocks {*outclk_1*}] -to [get_clocks {*outclk_0*}]
set_false_path -from [get_clocks {*outclk_0*}] -to [get_clocks {*outclk_1*}]

derive_clock_uncertainty
