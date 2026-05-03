# bench_matmul.S — 4×4 integer matrix multiply  C = A * B
#
# Algorithm: outer-product accumulation (standard RVV pattern)
#   For each row i of C:
#     acc[0..3] = 0
#     For k = 0..3:
#       scalar a_ik = A[i][k]
#       vmv.v.x v_a,  a_ik          # broadcast scalar to all 4 lanes
#       vle32.v v_b,  B_row_k       # load B row k (unit-stride, 4 elements)
#       vmul.vv v_p,  v_a, v_b      # element-wise product
#       vadd.vv acc,  acc,  v_p     # accumulate
#     vse32.v acc, C_row_i
#
# This pattern exercises the RAW scoreboard: vle32.v marks vd busy;
# vmul.vv stalls in FIFO until the load commits to VRF.
#
# DMEM layout (byte addresses, SEW=32, VL=4):
#   0x000–0x03F : A[4][4] = rows [1..4],[5..8],[9..12],[13..16]
#   0x040–0x07F : B[4][4] = all-ones matrix [[1,1,1,1],...]
#   0x080–0x0BF : C[4][4] = result (written by VPU)
#
# Expected C (C[i][j] = sum of row i of A, since B = all-ones):
#   C[0] = [10, 10, 10, 10]    (1+2+3+4   = 10)
#   C[1] = [26, 26, 26, 26]    (5+6+7+8   = 26)
#   C[2] = [42, 42, 42, 42]    (9+10+11+12= 42)
#   C[3] = [58, 58, 58, 58]    (13+14+15+16=58)
#
# Scalar verify (first element of each C row):
#   t1 = C[0][0] = 10 = 0x0000000A
#   t2 = C[1][0] = 26 = 0x0000001A
#   t3 = C[2][0] = 42 = 0x0000002A
#   t4 = C[3][0] = 58 = 0x0000003A

.section .text
.globl _start
_start:

    # ── Write A to DMEM[0x000..0x03F] ────────────────────────────────────────
    addi  a0, x0,  1;  sw a0,  0(x0)
    addi  a0, x0,  2;  sw a0,  4(x0)
    addi  a0, x0,  3;  sw a0,  8(x0)
    addi  a0, x0,  4;  sw a0, 12(x0)

    addi  a0, x0,  5;  sw a0, 16(x0)
    addi  a0, x0,  6;  sw a0, 20(x0)
    addi  a0, x0,  7;  sw a0, 24(x0)
    addi  a0, x0,  8;  sw a0, 28(x0)

    addi  a0, x0,  9;  sw a0, 32(x0)
    addi  a0, x0, 10;  sw a0, 36(x0)
    addi  a0, x0, 11;  sw a0, 40(x0)
    addi  a0, x0, 12;  sw a0, 44(x0)

    addi  a0, x0, 13;  sw a0, 48(x0)
    addi  a0, x0, 14;  sw a0, 52(x0)
    addi  a0, x0, 15;  sw a0, 56(x0)
    addi  a0, x0, 16;  sw a0, 60(x0)

    # ── Write B = all-ones to DMEM[0x040..0x07F] ─────────────────────────────
    addi  a0, x0, 1
    sw    a0,  64(x0);  sw a0,  68(x0);  sw a0,  72(x0);  sw a0,  76(x0)
    sw    a0,  80(x0);  sw a0,  84(x0);  sw a0,  88(x0);  sw a0,  92(x0)
    sw    a0,  96(x0);  sw a0, 100(x0);  sw a0, 104(x0);  sw a0, 108(x0)
    sw    a0, 112(x0);  sw a0, 116(x0);  sw a0, 120(x0);  sw a0, 124(x0)

    # ── VPU config: e32, m1, vl=4 ────────────────────────────────────────────
    addi  a0, x0, 4
    vsetvli t0, a0, e32, m1, ta, ma

    # ═══════════════════════════════════════════════════════════════════════════
    # C row 0:  acc = sum_k( A[0][k] * B_row_k )
    # ═══════════════════════════════════════════════════════════════════════════
    vmv.v.x v8, x0              # acc = [0,0,0,0]

    lw    a2,  0(x0)            # A[0][0] = 1
    vmv.v.x v10, a2
    addi  a1, x0, 64
    vle32.v v1, (a1)            # B row 0 — RAW: vmul must wait for this load
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    lw    a2,  4(x0)            # A[0][1] = 2
    vmv.v.x v10, a2
    addi  a1, x0, 80
    vle32.v v1, (a1)            # B row 1
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    lw    a2,  8(x0)            # A[0][2] = 3
    vmv.v.x v10, a2
    addi  a1, x0, 96
    vle32.v v1, (a1)            # B row 2
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    lw    a2, 12(x0)            # A[0][3] = 4
    vmv.v.x v10, a2
    addi  a1, x0, 112
    vle32.v v1, (a1)            # B row 3
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    addi  a1, x0, 128
    vse32.v v8, (a1)            # store C row 0

    # ═══════════════════════════════════════════════════════════════════════════
    # C row 1:  acc = sum_k( A[1][k] * B_row_k )
    # ═══════════════════════════════════════════════════════════════════════════
    vmv.v.x v8, x0

    lw    a2, 16(x0)            # A[1][0] = 5
    vmv.v.x v10, a2
    addi  a1, x0, 64
    vle32.v v1, (a1)
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    lw    a2, 20(x0)            # A[1][1] = 6
    vmv.v.x v10, a2
    addi  a1, x0, 80
    vle32.v v1, (a1)
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    lw    a2, 24(x0)            # A[1][2] = 7
    vmv.v.x v10, a2
    addi  a1, x0, 96
    vle32.v v1, (a1)
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    lw    a2, 28(x0)            # A[1][3] = 8
    vmv.v.x v10, a2
    addi  a1, x0, 112
    vle32.v v1, (a1)
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    addi  a1, x0, 144
    vse32.v v8, (a1)            # store C row 1

    # ═══════════════════════════════════════════════════════════════════════════
    # C row 2:  acc = sum_k( A[2][k] * B_row_k )
    # ═══════════════════════════════════════════════════════════════════════════
    vmv.v.x v8, x0

    lw    a2, 32(x0)            # A[2][0] = 9
    vmv.v.x v10, a2
    addi  a1, x0, 64
    vle32.v v1, (a1)
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    lw    a2, 36(x0)            # A[2][1] = 10
    vmv.v.x v10, a2
    addi  a1, x0, 80
    vle32.v v1, (a1)
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    lw    a2, 40(x0)            # A[2][2] = 11
    vmv.v.x v10, a2
    addi  a1, x0, 96
    vle32.v v1, (a1)
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    lw    a2, 44(x0)            # A[2][3] = 12
    vmv.v.x v10, a2
    addi  a1, x0, 112
    vle32.v v1, (a1)
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    addi  a1, x0, 160
    vse32.v v8, (a1)            # store C row 2

    # ═══════════════════════════════════════════════════════════════════════════
    # C row 3:  acc = sum_k( A[3][k] * B_row_k )
    # ═══════════════════════════════════════════════════════════════════════════
    vmv.v.x v8, x0

    lw    a2, 48(x0)            # A[3][0] = 13
    vmv.v.x v10, a2
    addi  a1, x0, 64
    vle32.v v1, (a1)
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    lw    a2, 52(x0)            # A[3][1] = 14
    vmv.v.x v10, a2
    addi  a1, x0, 80
    vle32.v v1, (a1)
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    lw    a2, 56(x0)            # A[3][2] = 15
    vmv.v.x v10, a2
    addi  a1, x0, 96
    vle32.v v1, (a1)
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    lw    a2, 60(x0)            # A[3][3] = 16
    vmv.v.x v10, a2
    addi  a1, x0, 112
    vle32.v v1, (a1)
    vmul.vv v11, v10, v1
    vadd.vv v8, v8, v11

    addi  a1, x0, 176
    vse32.v v8, (a1)            # store C row 3

    # ── Barrier: second vsetvli stalls until all stores complete ─────────────
    addi  a0, x0, 4
    vsetvli t0, a0, e32, m1, ta, ma

    # ── Scalar verification: first element of each C row ─────────────────────
    lw    t1, 128(x0)           # C[0][0] = 10 = 0x0A
    lw    t2, 144(x0)           # C[1][0] = 26 = 0x1A
    lw    t3, 160(x0)           # C[2][0] = 42 = 0x2A
    lw    t4, 176(x0)           # C[3][0] = 58 = 0x3A

success_end:
    addi  x0, x0, 0
    j     success_end
