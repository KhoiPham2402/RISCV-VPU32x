# uart_echo.S — VPU BT.601 grayscale + echo 16 Y bytes back via UART
#
# Protocol:
#   Host  → DUT:  16 R bytes, 16 G bytes, 16 B bytes
#   DUT   → Host: 16 Y bytes (BT.601 result) then ACK byte 0xAA
#
# DMEM layout:
#   0x0000–0x000F  R channel
#   0x4000–0x400F  G channel
#   0x8000–0x800F  B channel
#   0xC000–0xC00F  Y output (written by VPU vse8.v)
#
# UART registers (base 0xFF000000):
#   STAT  +0x04  [1]=RX_VALID  [0]=TX_BUSY
#   TXDAT +0x08  write byte to transmit
#   RXDAT +0x0C  read next RX byte (dequeues)

.section .text
.global _start

_start:
    li    s0, 0xFF000000          # UART base

    # ── Receive R channel ────────────────────────────────────────────────────
    li    a0, 0x0000
    li    a1, 16
    call  recv_block

    # ── Receive G channel ────────────────────────────────────────────────────
    li    a0, 0x4000
    li    a1, 16
    call  recv_block

    # ── Receive B channel ────────────────────────────────────────────────────
    li    a0, 0x8000
    li    a1, 16
    call  recv_block

    # ── VPU: BT.601 grayscale — Y = vmulhu(R,77) + vmulhu(G,150) + vmulhu(B,29) ──
    li    a0, 0x0000
    li    a1, 0x4000
    li    a2, 0x8000
    li    a3, 0xC000

    li    t3, 77
    li    t4, 150
    li    t5, 29

    li    t1, 16
    vsetvli t1, t1, e8, m1, ta, ma   # vl=16, SEW=8

    vle8.v    v1, (a0)
    vle8.v    v2, (a1)
    vle8.v    v3, (a2)

    vmulhu.vx v4, v1, t3           # R*77 >> 8
    vmulhu.vx v5, v2, t4           # G*150 >> 8
    vmulhu.vx v6, v3, t5           # B*29 >> 8

    vadd.vv   v7, v4, v5
    vadd.vv   v7, v7, v6           # Y = Yr + Yg + Yb

    vse8.v    v7, (a3)             # store Y to DMEM 0xC000

    # ── Send 16 Y bytes back via UART ────────────────────────────────────────
    li    a0, 0xC000
    li    a1, 16
    call  send_block

    # ── Send ACK ─────────────────────────────────────────────────────────────
    li    a0, 0xAA
    call  uart_tx_byte

done:
    j     done

# ─────────────────────────────────────────────────────────────────────────────
# recv_block: receive a1 bytes via UART, store starting at byte addr a0.
# Clobbers t0, t1.
# ─────────────────────────────────────────────────────────────────────────────
recv_block:
    add   t0, a0, a1
recv_loop:
    bge   a0, t0, recv_done
rx_wait:
    lw    t1, 4(s0)
    andi  t1, t1, 2
    beqz  t1, rx_wait
    lw    t1, 12(s0)
    sb    t1, 0(a0)
    addi  a0, a0, 1
    j     recv_loop
recv_done:
    ret

# ─────────────────────────────────────────────────────────────────────────────
# send_block: send a1 bytes from byte addr a0 via UART.
# Uses s1 to save ra across inner uart_tx_byte calls. Clobbers t0, t2, t3.
# ─────────────────────────────────────────────────────────────────────────────
send_block:
    mv    s1, ra                  # save caller return address
    mv    t2, a0                  # t2 = current byte pointer
    add   t3, a0, a1              # t3 = end pointer
send_loop_b:
    bge   t2, t3, send_done_b
    lbu   a0, 0(t2)               # a0 = byte to transmit
    call  uart_tx_byte
    addi  t2, t2, 1
    j     send_loop_b
send_done_b:
    mv    ra, s1                  # restore return address
    ret

# ─────────────────────────────────────────────────────────────────────────────
# uart_tx_byte: transmit a0[7:0] via UART. Clobbers t0.
# ─────────────────────────────────────────────────────────────────────────────
uart_tx_byte:
tx_wait:
    lw    t0, 4(s0)
    andi  t0, t0, 1
    bnez  t0, tx_wait
    sw    a0, 8(s0)
    ret
