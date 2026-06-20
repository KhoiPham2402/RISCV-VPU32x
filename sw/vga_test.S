# vga_test.S — Fill DMEM Y-buffer with gradient + HEX diagnostic
#
# Writes a top-to-bottom gradient to DMEM[0xC000..0xFFFF] (128×128 grayscale).
# VGA controller reads this region and displays it as 384×384 (3× zoom) on screen.
#
# Pattern: row 0 = black (0x00), row 127 = white (0xFE)
#   gray value = row * 2  (0, 2, 4, ... 254)
#   Each row = 32 words × 4 bytes = 128 pixels, all same gray level.
#
# HEX diagnostic (HEXL base 0x10002000, active-LOW):
#   On entry    : HEX0 = "0"  (firmware started)
#   After loops : HEX0 = "1"  (DMEM write complete — VGA should show gradient)
#
# IO address map: HEXL = 0x10002000 (bits[15:12]=2 in pipelined_vpu)
# Active-low 7-seg: "0"=0x40, "1"=0x79, blank=0x7F

.section .text
.global _start

_start:
    # Signal firmware start: HEX0 = "0", HEX1-3 = blank
    li   t3, 0x10002000
    li   t4, 0x7F7F7F40
    sw   t4, 0(t3)

    li   a0, 0xC000         # base of Y output buffer (byte addr)
    li   a1, 128            # 128 rows
    li   s0, 0              # row counter

row_loop:
    # gray = row * 2, packed as {gray, gray, gray, gray}
    slli t0, s0, 1          # t0 = row * 2
    andi t0, t0, 0xFF
    slli t1, t0, 8
    or   t0, t0, t1
    slli t1, t0, 16
    or   t0, t0, t1         # t0 = {gray, gray, gray, gray}

    # write 32 words (= 128 bytes = 128 pixels) for this row
    li   t2, 32
word_loop:
    sw   t0, 0(a0)
    addi a0, a0, 4
    addi t2, t2, -1
    bnez t2, word_loop

    addi s0, s0, 1
    blt  s0, a1, row_loop

    # Signal completion: HEX0 = "1"  (DMEM fully written, VGA should show gradient)
    li   t4, 0x7F7F7F79
    sw   t4, 0(t3)

done:
    j    done
