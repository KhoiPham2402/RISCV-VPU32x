# uart_hex_test.S
# UART echo + HEX display test
#
# Nhận 1 byte từ UART → hiển thị lên HEX1:HEX0 (2 nibble hex) + LEDR[7:0]
# → echo ngược byte đó về host.
# Trước khi nhận byte đầu tiên: HEX hiển thị "----".
#
# IO map (pipelined_vpu.sv IO_BASE0 = 16'h1000):
#   0xFF000000  UART base  (+0x04=STAT, +0x08=TXDAT, +0x0C=RXDAT)
#   0x10000000  LEDR       (sb vào [7:0] = LEDR[7:0])
#   0x10002000  HEXL       (byte0=HEX0, byte1=HEX1, byte2=HEX2, byte3=HEX3)
#
# 7-segment lookup (active-low, [6]=g [5]=f [4]=e [3]=d [2]=c [1]=b [0]=a):
#   0→0x40  1→0x79  2→0x24  3→0x30  4→0x19  5→0x12  6→0x02  7→0x78
#   8→0x00  9→0x10  A→0x08  b→0x03  C→0x46  d→0x21  E→0x06  F→0x0E
# Stored at DMEM[0x200..0x20F] (4 words × 4 bytes).

.section .text
.global _start

_start:
    # ── Constant registers (never clobbered) ─────────────────────────
    li    s0, 0xFF000000    # UART base
    li    s1, 0x10002000    # HEXL (HEX3..HEX0 via byte offsets)
    li    s2, 0x10000000    # LEDR

    # ── Init 7-segment table in DMEM[0x200] ──────────────────────────
    li    s3, 0x0200        # table base (DMEM, not IMEM)

    # Word 0: seg[0..3] → little-endian bytes 0x40,0x79,0x24,0x30
    li    t0, 0x30247940
    sw    t0, 0(s3)
    # Word 1: seg[4..7] → 0x19,0x12,0x02,0x78
    li    t0, 0x78021219
    sw    t0, 4(s3)
    # Word 2: seg[8..B] → 0x00,0x10,0x08,0x03
    li    t0, 0x03081000
    sw    t0, 8(s3)
    # Word 3: seg[C..F] → 0x46,0x21,0x06,0x0E
    li    t0, 0x0E062146
    sw    t0, 12(s3)

    # ── Show "----" on HEX3..HEX0 (0x3F = minus/dash segment) ────────
    li    t0, 0x3F3F3F3F
    sw    t0, 0(s1)

    # ── Main loop ─────────────────────────────────────────────────────
main_loop:
    call  uart_rx_byte      # a0 = received byte (blocks until data)

    # LEDR[7:0] = raw byte value (binary)
    sb    a0, 0(s2)

    # Decode lower nibble → HEX0
    andi  t1, a0, 0x0F
    add   t1, s3, t1
    lbu   t2, 0(t1)
    sb    t2, 0(s1)         # HEX0

    # Decode upper nibble → HEX1
    srli  t1, a0, 4
    andi  t1, t1, 0x0F
    add   t1, s3, t1
    lbu   t2, 0(t1)
    sb    t2, 1(s1)         # HEX1

    # Echo byte back to host
    call  uart_tx_byte

    j     main_loop

# ── uart_rx_byte: poll RX_VALID, read RXDAT → a0 ─────────────────────
uart_rx_byte:
rx_poll:
    lw    t0, 4(s0)
    andi  t0, t0, 2         # STAT[1] = RX_VALID
    beqz  t0, rx_poll
    lw    a0, 12(s0)        # RXDAT (dequeues one byte)
    ret

# ── uart_tx_byte: wait TX idle, write TXDAT ← a0[7:0] ────────────────
uart_tx_byte:
tx_poll:
    lw    t0, 4(s0)
    andi  t0, t0, 1         # STAT[0] = TX_BUSY
    bnez  t0, tx_poll
    sw    a0, 8(s0)         # TXDAT
    ret
