# crt0.S — Minimal C runtime startup
# Harvard RISC-V: IMEM=0x0000-0x1FFF (code), DMEM=0x0000-0x07FF (data/stack)
#
# Sequence:
#   1. Set stack pointer to top of DMEM
#   2. Zero BSS section (zero-initialized C globals)
#   3. call main()
#   4. Spin (jal x0,0 — testbench detects 0x0000006f and stops)

.section .text.init, "ax"
.global _start
.type   _start, @function

_start:
    li    sp, 0x7F0             # stack at top of DMEM (16-byte aligned)

    # Zero .bss (__bss_start .. __bss_end, word-aligned, in DMEM)
    la    a0, __bss_start
    la    a1, __bss_end
    bgeu  a0, a1, .Lcall_main  # skip if empty
.Lbss_loop:
    sw    zero, 0(a0)
    addi  a0, a0, 4
    bltu  a0, a1, .Lbss_loop

.Lcall_main:
    call  main

.Ldone:
    j     .Ldone               # 0x0000006f — testbench stop marker

.size _start, . - _start
