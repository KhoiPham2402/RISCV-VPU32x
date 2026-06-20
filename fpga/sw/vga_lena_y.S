# vga_lena_y.S — Trivial firmware for VGA-only display test.
#
# DMEM is pre-initialized with Lena Y (grayscale) at 0xC000–0xFFFF
# via dmem_b*.mif. VGA controller reads from that area directly.
# Firmware has nothing to do — just spin forever.
.section .text
.global _start
_start:
    j _start
