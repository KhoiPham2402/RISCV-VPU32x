# uart_lena_test.S — 16-pixel UART RX → VPU grayscale simulation smoke test
#
# Test pattern: R[i]=G[i]=B[i]=128 for all 16 pixels.
# Expected:     Y[i] = floor(128*77/256) + floor(128*150/256) + floor(128*29/256)
#                     = 38 + 75 + 14 = 127 = 0x7F
#
# DMEM layout:
#   0x000  R channel  (16 bytes)
#   0x010  G channel  (16 bytes)
#   0x020  B channel  (16 bytes)
#   0x030  Y output   (16 bytes, written by VPU)
#
# UART registers at 0xFF000000 (enabled and baud set at reset):
#   STAT  +0x04  [1]=RX_VALID  [0]=TX_BUSY
#   TXDAT +0x08
#   RXDAT +0x0C  (dequeues on read)

.section .text
.global _start

_start:
    li    s0, 0xFF000000

    # ── Receive R: 16 bytes → 0x000 ───────────────────────────────────────────
    li    a0, 0x000
    li    a1, 16
    call  recv_block

    # ── Receive G: 16 bytes → 0x010 ───────────────────────────────────────────
    li    a0, 0x010
    li    a1, 16
    call  recv_block

    # ── Receive B: 16 bytes → 0x020 ───────────────────────────────────────────
    li    a0, 0x020
    li    a1, 16
    call  recv_block

    # ── VPU: 1 iteration, 16 pixels ───────────────────────────────────────────
    li    a0, 0x000
    li    a1, 0x010
    li    a2, 0x020
    li    a3, 0x030

    li    t3, 77
    li    t4, 150
    li    t5, 29

    li    t1, 16
    vsetvli t1, t1, e8, m1, ta, ma

    vle8.v    v1, (a0)
    vle8.v    v2, (a1)
    vle8.v    v3, (a2)

    vmulhu.vx v4, v1, t3
    vmulhu.vx v5, v2, t4
    vmulhu.vx v6, v3, t5

    vadd.vv   v7, v4, v5
    vadd.vv   v7, v7, v6

    vse8.v    v7, (a3)

    # ── ACK ───────────────────────────────────────────────────────────────────
    li    a0, 0xAA
    call  uart_tx_byte

done:
    j     done                    # testbench detects spin at 0x0000006f

# ─────────────────────────────────────────────────────────────────────────────
recv_block:
    add   t0, a0, a1
recv_loop_t:
    bge   a0, t0, recv_done_t
rx_wait_t:
    lw    t1, 4(s0)
    andi  t1, t1, 2
    beqz  t1, rx_wait_t
    lw    t1, 12(s0)
    sb    t1, 0(a0)
    addi  a0, a0, 1
    j     recv_loop_t
recv_done_t:
    ret

# ─────────────────────────────────────────────────────────────────────────────
uart_tx_byte:
tx_wait_t:
    lw    t0, 4(s0)
    andi  t0, t0, 1
    bnez  t0, tx_wait_t
    sw    a0, 8(s0)
    ret
