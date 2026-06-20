# scalar_bt601.S — BT.601 grayscale, SCALAR ONLY (no VPU), 5-stage pipeline
#
# Interleaved to hide load-use stalls:
#   lbu R, lbu G, lbu B  ← 3 loads with no dependent use between them
#   mul/srli × 3         ← uses loaded values after enough gap
#
# DMEM layout (pre-loaded via lena_dmem_init.hex):
#   0x0000-0x3FFF  R channel
#   0x4000-0x7FFF  G channel
#   0x8000-0xBFFF  B channel
#   0xC000-0xFFFF  Y output
#
# Cycle counter:
#   t_start = cycle at loop entry, t_end = cycle at done
#   Use mcycle CSR (0xC00)

.section .text
.global _start
_start:
    li    a0, 0x0000        # R base
    li    a1, 0x4000        # G base
    li    a2, 0x8000        # B base
    li    a3, 0xC000        # Y base

    li    s1, 77            # BT.601 R coeff
    li    s2, 150           # BT.601 G coeff
    li    s3, 29            # BT.601 B coeff

    li    t0, 16384         # pixel count

loop:
    lbu   t1, 0(a0)         # load R[i]
    lbu   t2, 0(a1)         # load G[i]  — hides t1 load stall
    lbu   t3, 0(a2)         # load B[i]  — hides t2 load stall
    addi  a0, a0, 1         #            — hides t3 load stall

    mul   t1, t1, s1        # R * 77     — t1 ready (3 cycles after lbu)
    mul   t2, t2, s2        # G * 150
    mul   t3, t3, s3        # B * 29

    srli  t1, t1, 8         # >> 8
    srli  t2, t2, 8
    srli  t3, t3, 8

    add   t1, t1, t2        # Y = Yr + Yg
    add   t1, t1, t3        #   + Yb

    sb    t1, 0(a3)         # store Y[i]

    addi  a1, a1, 1
    addi  a2, a2, 1
    addi  a3, a3, 1

    addi  t0, t0, -1
    bnez  t0, loop

done:
    li    t1, 0x10000       # IO base (ledr register)
    li    t2, 0xBEEF        # sentinel value
    sw    t2, 0(t1)         # write to LED → testbench detects done
    j     done
