# lena_gray.S — Convert 16x16 RGB planar image to grayscale using VPU
# BT.601 approximation via vmulhu.vx (high half of 8x8 unsigned multiply):
#   Y[i] = floor(R[i]*77/256) + floor(G[i]*150/256) + floor(B[i]*29/256)
# Max value: 76 + 149 + 28 = 253 < 256 — no 8-bit overflow.
#
# DMEM byte-address layout:
#   0x000–0x0FF  R channel  (256 pixels, 4 per 32-bit word)
#   0x100–0x1FF  G channel
#   0x200–0x2FF  B channel
#   0x300–0x3FF  Y output   (written by this program)
#
# VPU config: SEW=8, LMUL=1 → VLMAX=16 elements per register
# Loop: 16 iterations × 16 elements = 256 pixels total

.section .text
.global _start

_start:
    li    a0, 0x000           # R channel base address
    li    a1, 0x100           # G channel base address
    li    a2, 0x200           # B channel base address
    li    a3, 0x300           # Y output base address

    li    t3, 77              # BT.601 R coefficient  (vmulhu: floor(R*77/256))
    li    t4, 150             # BT.601 G coefficient
    li    t5, 29              # BT.601 B coefficient

    li    t1, 16
    vsetvli t1, t1, e8, m1, ta, ma   # vl=16, SEW=8, LMUL=1

    li    t0, 16              # loop counter: 16 groups of 16 pixels

loop:
    vle8.v    v1, (a0)        # load 16 R pixels
    vle8.v    v2, (a1)        # load 16 G pixels
    vle8.v    v3, (a2)        # load 16 B pixels

    vmulhu.vx v4, v1, t3     # v4[i] = floor(R[i] * 77  / 256)
    vmulhu.vx v5, v2, t4     # v5[i] = floor(G[i] * 150 / 256)
    vmulhu.vx v6, v3, t5     # v6[i] = floor(B[i] * 29  / 256)

    vadd.vv   v7, v4, v5     # v7[i] = R_contrib + G_contrib
    vadd.vv   v7, v7, v6     # v7[i] = Y[i]  (sum <= 253, no overflow)

    vse8.v    v7, (a3)        # store 16 grayscale pixels

    addi  a0, a0, 16
    addi  a1, a1, 16
    addi  a2, a2, 16
    addi  a3, a3, 16

    addi  t0, t0, -1
    bnez  t0, loop

    # Verification: load first 16 Y values into scalar regs for testbench
    li    t0, 0x300
    lw    t1, 0(t0)           # Y[3..0]  packed as 32-bit word
    lw    t2, 4(t0)           # Y[7..4]
    lw    t3, 8(t0)           # Y[11..8]
    lw    t4, 12(t0)          # Y[15..12]

done:
    j     done                # spin — testbench detects 0x0000006f and stops
