# uart_pin_test.S — UART RX pin detection, continuous loop
#
# Liên tục check RX_VALID:
#   HEX0 = "0" khi không có data (idle)
#   HEX0 = "1" khi có data trong RX FIFO
#   Sau khi nhận, dequeue byte rồi check lại → tự reset về "0" nếu FIFO rỗng
#
# Dùng để dò pin: cắm adapter TX vào từng chân JP1, reset board.
# Nếu HEX hiện "1" ngay (không gửi gì) → pin đó float → thử chân khác.
# Nếu HEX hiện "0" khi idle, đổi sang "1" khi gửi byte → đúng pin!
#
# UART base  0xFF000000  STAT+4: [1]=RX_VALID  RXDAT+0xC: dequeue
# HEX base   0x10002000  bits[6:0]=HEX0 (active-LOW)
#   "0" = 0x40,  "1" = 0x79,  blank = 0x7F

.section .text
.global _start

_start:
    li   s0, 0xFF000000
    li   s1, 0x10002000
    li   s2, 0x7F7F7F40     # "0" trên HEX0, blank HEX1-3
    li   s3, 0x7F7F7F79     # "1" trên HEX0, blank HEX1-3

loop:
    lw   t0, 4(s0)          # đọc UART STAT
    andi t0, t0, 2          # bit[1] = RX_VALID
    beqz t0, show_zero      # không có data → hiện "0"

    # Có data → hiện "1", dequeue byte, rồi loop lại
    sw   s3, 0(s1)
    lw   x0, 12(s0)         # dequeue 1 byte (RXDAT), bỏ đi
    j    loop

show_zero:
    sw   s2, 0(s1)
    j    loop
