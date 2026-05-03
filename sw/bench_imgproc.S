# bench_imgproc.S — RGB-to-Grayscale benchmark (BT.601 integer approximation)
#
# Algorithm: Y_raw = R*77 + G*150 + B*29
# 4 pixels processed in parallel (SEW=32, LMUL=1, VL=4, VLEN=128)
#
# Coefficients loaded via vmv.v.x, pixel data loaded via vle32.v.
# Multiplication done with vmul.vv (coefficients broadcast to vectors first).
# No shift needed — verify Y_raw directly.
#
# DMEM layout (byte addresses):
#   0x00-0x0F : R[0..3] = [100, 200,  50, 255]
#   0x10-0x1F : G[0..3] = [150, 100, 200, 255]
#   0x20-0x2F : B[0..3] = [ 50,  50, 200, 255]
#   0x30-0x3F : Y_raw output = [31650, 31850, 39650, 65280]
#
# Expected (scalar verify): t1=31650 t2=31850 t3=39650 t4=65280

.section .text
.globl _start
_start:
    # ── Write R pixels to DMEM ──────────────────────────────────────────────
    addi    a0, x0, 100
    sw      a0,  0(x0)
    addi    a0, x0, 200
    sw      a0,  4(x0)
    addi    a0, x0, 50
    sw      a0,  8(x0)
    addi    a0, x0, 255
    sw      a0, 12(x0)

    # ── Write G pixels to DMEM ──────────────────────────────────────────────
    addi    a0, x0, 150
    sw      a0, 16(x0)
    addi    a0, x0, 100
    sw      a0, 20(x0)
    addi    a0, x0, 200
    sw      a0, 24(x0)
    addi    a0, x0, 255
    sw      a0, 28(x0)

    # ── Write B pixels to DMEM ──────────────────────────────────────────────
    addi    a0, x0, 50
    sw      a0, 32(x0)
    addi    a0, x0, 50
    sw      a0, 36(x0)
    addi    a0, x0, 200
    sw      a0, 40(x0)
    addi    a0, x0, 255
    sw      a0, 44(x0)

    # ── VPU config: e32 m1 vl=4 ─────────────────────────────────────────────
    addi    a0, x0, 4
    vsetvli t0, a0, e32, m1, ta, ma     # t0 = vl = 4

    # ── Broadcast coefficients into vector regs via vmv.v.x ─────────────────
    addi    a2, x0, 77
    vmv.v.x v10, a2                     # v10 = [77, 77, 77, 77]

    # 150 > 127 so build with two addi
    addi    a2, x0, 0
    addi    a2, a2, 127
    addi    a2, a2, 23                  # a2 = 150
    vmv.v.x v11, a2                     # v11 = [150, 150, 150, 150]

    addi    a2, x0, 29
    vmv.v.x v12, a2                     # v12 = [29, 29, 29, 29]

    # ── Load pixel channels from DMEM ────────────────────────────────────────
    addi    a1, x0,  0
    vle32.v v1, (a1)                    # v1 = [100, 200,  50, 255]  (R)

    addi    a1, x0, 16
    vle32.v v2, (a1)                    # v2 = [150, 100, 200, 255]  (G)

    addi    a1, x0, 32
    vle32.v v3, (a1)                    # v3 = [ 50,  50, 200, 255]  (B)

    # ── Luma: Y_raw = R*77 + G*150 + B*29 ───────────────────────────────────
    vmul.vv v4, v1, v10                 # v4 = R * 77  = [7700,15400, 3850,19635]
    vmul.vv v5, v2, v11                 # v5 = G * 150 = [22500,15000,30000,38250]
    vmul.vv v6, v3, v12                 # v6 = B * 29  = [1450, 1450, 5800, 7395]

    vadd.vv v7, v4, v5                  # v7 = R*77 + G*150
    vadd.vv v7, v7, v6                  # v7 = Y_raw = [31650,31850,39650,65280]

    # ── Store Y_raw results ──────────────────────────────────────────────────
    addi    a1, x0, 48
    vse32.v v7, (a1)                    # DMEM[48..60] = Y_raw values

    # ── Barrier: stall until VLSU store complete (waits for vpu_ready) ───────
    addi    a0, x0, 4
    vsetvli t0, a0, e32, m1, ta, ma

    # ── Scalar verification ──────────────────────────────────────────────────
    lw      t1, 48(x0)                  # t1 = y0 = 31650 = 0x7BA2
    lw      t2, 52(x0)                  # t2 = y1 = 31850 = 0x7C6A
    lw      t3, 56(x0)                  # t3 = y2 = 39650 = 0x9AE2
    lw      t4, 60(x0)                  # t4 = y3 = 65280 = 0xFF00

success_end:
    addi    x0, x0, 0
    j       success_end
