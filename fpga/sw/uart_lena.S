# uart_lena.S — 128×128 RGB planar → BT.601 grayscale via VPU, data via UART
#
# Protocol: host sends 3×16384 bytes in order R, G, B (planar).
#           Firmware processes all pixels, then sends ACK byte 0xAA.
#
# DMEM layout (64 KB, byte-addressed by LSU):
#   0x0000–0x3FFF  R channel  (16384 bytes)
#   0x4000–0x7FFF  G channel
#   0x8000–0xBFFF  B channel
#   0xC000–0xFFFF  Y output   (written by VPU)
#
# UART registers (base 0xFF000000, already enabled at reset):
#   STAT  +0x04  [1]=RX_VALID  [0]=TX_BUSY
#   TXDAT +0x08  write byte to transmit
#   RXDAT +0x0C  read next RX byte (dequeues; 0xFFFFFFFF if empty)
#
# VPU: SEW=8, LMUL=1 → VLMAX=16 elements/reg
# 1024 iterations × 16 elements = 16384 pixels total.

.section .text
.global _start

_start:
    li    s0, 0xFF000000          # UART base address

    # ── Receive R channel ──────────────────────────────────────────────────────
    li    a0, 0x0000
    li    a1, 16384
    call  recv_block

    # ── Receive G channel ──────────────────────────────────────────────────────
    li    a0, 0x4000
    li    a1, 16384
    call  recv_block

    # ── Receive B channel ──────────────────────────────────────────────────────
    li    a0, 0x8000
    li    a1, 16384
    call  recv_block

    # ── VPU: BT.601 grayscale ─────────────────────────────────────────────────
    # Y = floor(R*77/256) + floor(G*150/256) + floor(B*29/256)
    # Max: 76+149+28 = 253 — no 8-bit overflow.
    li    a0, 0x0000              # R base
    li    a1, 0x4000              # G base
    li    a2, 0x8000              # B base
    li    a3, 0xC000              # Y output base

    li    t3, 77                  # R coefficient
    li    t4, 150                 # G coefficient
    li    t5, 29                  # B coefficient

    li    t1, 16
    vsetvli t1, t1, e8, m1, ta, ma   # vl=16, SEW=8, LMUL=1

    li    t0, 1024                # 1024 groups × 16 = 16384 pixels

vpu_loop:
    vle8.v    v1, (a0)
    vle8.v    v2, (a1)
    vle8.v    v3, (a2)

    vmulhu.vx v4, v1, t3
    vmulhu.vx v5, v2, t4
    vmulhu.vx v6, v3, t5

    vadd.vv   v7, v4, v5
    vadd.vv   v7, v7, v6

    vse8.v    v7, (a3)

    addi  a0, a0, 16
    addi  a1, a1, 16
    addi  a2, a2, 16
    addi  a3, a3, 16

    addi  t0, t0, -1
    bnez  t0, vpu_loop

    # ── Send ACK ───────────────────────────────────────────────────────────────
    li    a0, 0xAA
    call  uart_tx_byte

done:
    j     done                    # spin — testbench detects 0x0000006f

# ─────────────────────────────────────────────────────────────────────────────
# recv_block: receive a1 bytes via UART, store at byte address a0.
# s0 = UART base (caller must set). Advances a0, clobbers a1, t0, t1.
# ─────────────────────────────────────────────────────────────────────────────
recv_block:
    add   t0, a0, a1              # t0 = end address
recv_loop:
    bge   a0, t0, recv_done
rx_wait:
    lw    t1, 4(s0)               # STAT: [1]=RX_VALID
    andi  t1, t1, 2
    beqz  t1, rx_wait
    lw    t1, 12(s0)              # RXDAT: dequeues one byte
    sb    t1, 0(a0)
    addi  a0, a0, 1
    j     recv_loop
recv_done:
    ret

# ─────────────────────────────────────────────────────────────────────────────
# uart_tx_byte: transmit byte in a0[7:0]. Clobbers t0.
# ─────────────────────────────────────────────────────────────────────────────
uart_tx_byte:
tx_wait:
    lw    t0, 4(s0)               # STAT: [0]=TX_BUSY
    andi  t0, t0, 1
    bnez  t0, tx_wait
    sw    a0, 8(s0)               # TXDAT: push byte
    ret
