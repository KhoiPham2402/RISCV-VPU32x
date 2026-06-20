# scalar_axpy.S — AXPY y[i] = a*x[i] + y[i], N=16, SCALAR ONLY
# a=3, x[0..15] = {1,2,..,16} at 0x100, y[0..15] = {1,2,..,16} at 0x200

.section .text
.global _start
_start:
    li    a0, 0x100         # x base
    li    a1, 0x200         # y base
    li    a2, 3             # scalar a
    li    t0, 16            # N

    # init: x[i] = i+1, y[i] = i+1
    li    t2, 0x100
    li    t3, 1
init_x:
    sw    t3, 0(t2)
    addi  t2, t2, 4
    addi  t3, t3, 1
    addi  t4, t3, -17
    bnez  t4, init_x
    li    t2, 0x200
    li    t3, 1
init_y:
    sw    t3, 0(t2)
    addi  t2, t2, 4
    addi  t3, t3, 1
    addi  t4, t3, -17
    bnez  t4, init_y

    li    t0, 16
loop:
    lw    t1, 0(a0)         # x[i]
    lw    t2, 0(a1)         # y[i]
    mul   t1, t1, a2        # a * x[i]
    add   t2, t2, t1        # y[i] + a*x[i]
    sw    t2, 0(a1)         # store
    addi  a0, a0, 4
    addi  a1, a1, 4
    addi  t0, t0, -1
    bnez  t0, loop

done:
    li    t0, 0x10000
    li    t1, 0xBEEF
    sw    t1, 0(t0)
    j     done
