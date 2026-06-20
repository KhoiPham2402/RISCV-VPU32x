# dmem_lena.S — BT.601 grayscale via VPU, image pre-loaded in DMEM (no UART)
#
# DMEM layout (64 KB, byte-addressed):
#   0x0000–0x3FFF  R channel  (pre-initialized via dmem_b*.mif at synthesis)
#   0x4000–0x7FFF  G channel
#   0x8000–0xBFFF  B channel
#   0xC000–0xFFFF  Y output   (written by VPU; VGA reads from here)
#
# VPU: SEW=8, LMUL=1, VLMAX=16 elements/reg
# 1024 iterations × 16 elements = 16384 pixels

.section .text
.global _start

_start:
    li    a0, 0x0000              # R channel base
    li    a1, 0x4000              # G channel base
    li    a2, 0x8000              # B channel base
    li    a3, 0xC000              # Y output base

    li    t3, 77                  # BT.601 R coefficient
    li    t4, 150                 # BT.601 G coefficient
    li    t5, 29                  # BT.601 B coefficient

    li    t1, 16
    vsetvli t1, t1, e8, m1, ta, ma   # vl=16, SEW=8, LMUL=1

    li    t0, 1024               # loop counter: 1024 × 16 = 16384 pixels

vpu_loop:
    vle8.v    v1, (a0)           # load 16 R pixels
    vle8.v    v2, (a1)           # load 16 G pixels
    vle8.v    v3, (a2)           # load 16 B pixels

    vmulhu.vx v4, v1, t3         # v4 = R × 77 >> 8
    vmulhu.vx v5, v2, t4         # v5 = G × 150 >> 8
    vmulhu.vx v6, v3, t5         # v6 = B × 29 >> 8

    vadd.vv   v7, v4, v5         # v7 = v4 + v5
    vadd.vv   v7, v7, v6         # v7 = Y (max 253, no 8-bit overflow)

    vse8.v    v7, (a3)           # store 16 Y pixels

    addi  a0, a0, 16
    addi  a1, a1, 16
    addi  a2, a2, 16
    addi  a3, a3, 16

    addi  t0, t0, -1
    bnez  t0, vpu_loop

done:
    j     done                   # spin — VGA keeps displaying from DMEM
