# de10_standard_pins.tcl — Pin assignments for DE10-Standard (Cyclone V)
#
# Top-level entity: de10_standard_top
# Source from Quartus Tcl console:
#   source C:/CapstoneProject2/riscv_vpu/fpga/constraints/de10_standard_pins.tcl
#
# References: DE10-Standard User Manual v1.0 — Terasic Technologies
#   Table 3-1 (CLOCK_50), Table 3-2 (KEY), Table 3-3 (SW)
#   Table 3-4 (LEDR), Table 3-5 (HEX), Table 3-11 (GPIO), Table 3-15 (VGA)
#
# NOTE: FAMILY/DEVICE intentionally not set here — keep whatever the QSF has.

# ── Top-level entity ──────────────────────────────────────────────────────────
set_global_assignment -name TOP_LEVEL_ENTITY de10_standard_top

# ── Clock (50 MHz oscillator on PIN_P11) ──────────────────────────────────────
set_location_assignment PIN_AF14  -to CLOCK_50
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CLOCK_50

# ── Push-buttons KEY[1:0] — Table 3-7 ───────────────────────────────────────
# KEY[0] = system reset (pressed → reset asserted in de10_standard_top)
set_location_assignment PIN_AJ4  -to KEY[0]
set_location_assignment PIN_AK4  -to KEY[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to KEY[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to KEY[1]

# ── Slide switches SW[9:0] — Table 3-6 ───────────────────────────────────────
# IO standard depends on JP3 jumper setting (default 3.3V position)
set_location_assignment PIN_AB30 -to SW[0]
set_location_assignment PIN_Y27  -to SW[1]
set_location_assignment PIN_AB28 -to SW[2]
set_location_assignment PIN_AC30 -to SW[3]
set_location_assignment PIN_W25  -to SW[4]
set_location_assignment PIN_V25  -to SW[5]
set_location_assignment PIN_AC28 -to SW[6]
set_location_assignment PIN_AD30 -to SW[7]
set_location_assignment PIN_AC29 -to SW[8]
set_location_assignment PIN_AA30 -to SW[9]
foreach i {0 1 2 3 4 5 6 7 8 9} {
    set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to "SW[$i]"
}

# ── Red LEDs LEDR[9:0] — Table 3-8 ───────────────────────────────────────────
set_location_assignment PIN_AA24 -to LEDR[0]
set_location_assignment PIN_AB23 -to LEDR[1]
set_location_assignment PIN_AC23 -to LEDR[2]
set_location_assignment PIN_AD24 -to LEDR[3]
set_location_assignment PIN_AG25 -to LEDR[4]
set_location_assignment PIN_AF25 -to LEDR[5]
set_location_assignment PIN_AE24 -to LEDR[6]
set_location_assignment PIN_AF24 -to LEDR[7]
set_location_assignment PIN_AB22 -to LEDR[8]
set_location_assignment PIN_AC22 -to LEDR[9]
foreach i {0 1 2 3 4 5 6 7 8 9} {
    set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to "LEDR[$i]"
}

# ── 7-Segment displays HEX0–HEX5 (active-low) — Table 3-9 ───────────────────
# HEX0
set_location_assignment PIN_W17  -to HEX0[0]
set_location_assignment PIN_V18  -to HEX0[1]
set_location_assignment PIN_AG17 -to HEX0[2]
set_location_assignment PIN_AG16 -to HEX0[3]
set_location_assignment PIN_AH17 -to HEX0[4]
set_location_assignment PIN_AG18 -to HEX0[5]
set_location_assignment PIN_AH18 -to HEX0[6]

# HEX1
set_location_assignment PIN_AF16 -to HEX1[0]
set_location_assignment PIN_V16  -to HEX1[1]
set_location_assignment PIN_AE16 -to HEX1[2]
set_location_assignment PIN_AD17 -to HEX1[3]
set_location_assignment PIN_AE18 -to HEX1[4]
set_location_assignment PIN_AE17 -to HEX1[5]
set_location_assignment PIN_V17  -to HEX1[6]

# HEX2
set_location_assignment PIN_AA21 -to HEX2[0]
set_location_assignment PIN_AB17 -to HEX2[1]
set_location_assignment PIN_AA18 -to HEX2[2]
set_location_assignment PIN_Y17  -to HEX2[3]
set_location_assignment PIN_Y18  -to HEX2[4]
set_location_assignment PIN_AF18 -to HEX2[5]
set_location_assignment PIN_W16  -to HEX2[6]

# HEX3
set_location_assignment PIN_Y19  -to HEX3[0]
set_location_assignment PIN_W19  -to HEX3[1]
set_location_assignment PIN_AD19 -to HEX3[2]
set_location_assignment PIN_AA20 -to HEX3[3]
set_location_assignment PIN_AC20 -to HEX3[4]
set_location_assignment PIN_AA19 -to HEX3[5]
set_location_assignment PIN_AD20 -to HEX3[6]

# HEX4
set_location_assignment PIN_AD21 -to HEX4[0]
set_location_assignment PIN_AG22 -to HEX4[1]
set_location_assignment PIN_AE22 -to HEX4[2]
set_location_assignment PIN_AE23 -to HEX4[3]
set_location_assignment PIN_AG23 -to HEX4[4]
set_location_assignment PIN_AF23 -to HEX4[5]
set_location_assignment PIN_AH22 -to HEX4[6]

# HEX5
set_location_assignment PIN_AF21 -to HEX5[0]
set_location_assignment PIN_AG21 -to HEX5[1]
set_location_assignment PIN_AF20 -to HEX5[2]
set_location_assignment PIN_AG20 -to HEX5[3]
set_location_assignment PIN_AE19 -to HEX5[4]
set_location_assignment PIN_AF19 -to HEX5[5]
set_location_assignment PIN_AB21 -to HEX5[6]

foreach d {HEX0 HEX1 HEX2 HEX3 HEX4 HEX5} {
    foreach i {0 1 2 3 4 5 6} {
        set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to "${d}[$i]"
    }
}

# ── UART — routed to GPIO_0 header (JP1) ─────────────────────────────────────
# DE10-Standard on-board UART (PIN_AA21/AA22) belongs to HPS — not usable from
# FPGA fabric. Use GPIO_0 (JP1) header with a USB-UART adapter (CP2102/CH340).
#
# Physical wiring on JP1 (40-pin header, 2×20, 2.54 mm pitch):
#
#   JP1 header viewed from above (key notch at top-left):
#   ┌──────────────────────────────────────────────────────┐
#   │ 1[3.3V] 3[GPIO_0[0]] 5[GPIO_0[2]] ... 11[GPIO_0[8]] │
#   │ 2[GND]  4[GPIO_0[1]] 6[GPIO_0[3]] ... 12[GND]       │
#   └──────────────────────────────────────────────────────┘
#
#   JP1 pin 3 → GPIO_0[0] = FPGA PIN_W15  → GPIO_0_RX (UART_RX) → adapter TX
#   JP1 pin 4 → GPIO_0[1] = FPGA PIN_AK2  → GPIO_0_TX (UART_TX) → adapter RX
#   JP1 pin 2 → GND                        → adapter GND
#
# Source: DE10-Standard User Manual Table 3-11 (verified).
# Use 3.3 V adapter only (CP2102/CH340). Do NOT connect adapter VCC to board.
set_location_assignment PIN_W15  -to GPIO_0_RX
set_location_assignment PIN_AK2  -to GPIO_0_TX
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to GPIO_0_RX
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to GPIO_0_TX

# ── VGA — ADV7123 DAC (DE10-Standard User Manual Table 3-15) ─────────────────
# No I2C config needed. Connect a standard VGA monitor to J9 (DB-15 connector).
# IO standard: 3.3-V LVTTL for all VGA pins.
set_location_assignment PIN_AK21  -to VGA_CLK
set_location_assignment PIN_AK19  -to VGA_HS
set_location_assignment PIN_AK18  -to VGA_VS
set_location_assignment PIN_AK22  -to VGA_BLANK_N
set_location_assignment PIN_AJ22  -to VGA_SYNC_N

# VGA_R[7:0]
set_location_assignment PIN_AK29  -to VGA_R[0]
set_location_assignment PIN_AK28  -to VGA_R[1]
set_location_assignment PIN_AK27  -to VGA_R[2]
set_location_assignment PIN_AJ27  -to VGA_R[3]
set_location_assignment PIN_AH27  -to VGA_R[4]
set_location_assignment PIN_AF26  -to VGA_R[5]
set_location_assignment PIN_AG26  -to VGA_R[6]
set_location_assignment PIN_AJ26  -to VGA_R[7]

# VGA_G[7:0]
set_location_assignment PIN_AK26   -to VGA_G[0]
set_location_assignment PIN_AJ25  -to VGA_G[1]
set_location_assignment PIN_AH25  -to VGA_G[2]
set_location_assignment PIN_AK24  -to VGA_G[3]
set_location_assignment PIN_AJ24  -to VGA_G[4]
set_location_assignment PIN_AH24  -to VGA_G[5]
set_location_assignment PIN_AK23  -to VGA_G[6]
set_location_assignment PIN_AH23  -to VGA_G[7]

# VGA_B[7:0]
set_location_assignment PIN_AJ21  -to VGA_B[0]
set_location_assignment PIN_AJ20  -to VGA_B[1]
set_location_assignment PIN_AH20  -to VGA_B[2]
set_location_assignment PIN_AJ19  -to VGA_B[3]
set_location_assignment PIN_AH19  -to VGA_B[4]
set_location_assignment PIN_AJ17   -to VGA_B[5]
set_location_assignment PIN_AJ16   -to VGA_B[6]
set_location_assignment PIN_AK16   -to VGA_B[7]

foreach sig {VGA_CLK VGA_HS VGA_VS VGA_BLANK_N VGA_SYNC_N} {
    set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to $sig
}
foreach i {0 1 2 3 4 5 6 7} {
    set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to "VGA_R[$i]"
    set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to "VGA_G[$i]"
    set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to "VGA_B[$i]"
}

puts "INFO: Pin assignments loaded for DE10-Standard (de10_standard_top) — VGA mode."
puts "WARN: Verify HEX2-HEX5 segment pins against User Manual Table 3-5."
puts "WARN: Verify VGA pins against User Manual Table 3-15 before programming."
puts "WARN: UART routed to GPIO — connect CP2102 module to GPIO_0[0]/[1]."
