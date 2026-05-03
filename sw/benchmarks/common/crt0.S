/* Minimal C runtime for bare-metal RISC-V VPU benchmarks.
 * Harvard arch: IMEM at 0x0, DMEM is separate 2KB space.
 * Stack top at 0x7F0 (leaves 0x1E0-0x1EC for results mailbox).
 * Testbench monitors t1-t4 after _exit_loop for PASS/FAIL check.
 */
.section .text.init
.align 2
.globl _start
_start:
    li    sp, 0x7F0         /* top of DMEM stack */
    call  main

    /* Load results mailbox into t1-t4 for testbench */
    lw    t1, 0x1E0(x0)
    lw    t2, 0x1E4(x0)
    lw    t3, 0x1E8(x0)
    lw    t4, 0x1EC(x0)

_exit_loop:
    /* Testbench detects PC stuck here (j _exit_loop = 0xFFDFF06F) */
    j     _exit_loop
