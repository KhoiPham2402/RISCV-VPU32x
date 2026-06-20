# uart_loopback.S — UART RX/TX loopback test firmware
#
# Protocol: host sends any byte; firmware replies with (byte + 1) mod 256.
# Runs forever. Used to verify UART RX and TX are both functional.
#
# UART registers (base 0xFF000000):
#   STAT  +0x04  [1]=RX_VALID  [0]=TX_BUSY
#   TXDAT +0x08  write byte to transmit
#   RXDAT +0x0C  read next RX byte (dequeues)

.section .text
.global _start

_start:
    li s0, 0xFF000000       # UART base

loop:
    # ── Wait for incoming byte ────────────────────────────────────────────
rx_wait:
    lw   t0, 4(s0)          # STAT
    andi t0, t0, 2          # isolate RX_VALID
    beqz t0, rx_wait

    lw   a0, 12(s0)         # RXDAT: read and dequeue byte
    andi a0, a0, 0xFF       # mask to 8 bits

tx_wait:
    lw   t0, 4(s0)          # STAT
    andi t0, t0, 1          # isolate TX_BUSY
    bnez t0, tx_wait

    sw   a0, 8(s0)          # TXDAT: push byte to TX FIFO

    j    loop

done:
    j    done               # unreachable; satisfies assembler
