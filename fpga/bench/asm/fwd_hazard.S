// =============================================================================
// fwd_hazard.S — directed regression for the EX-stage MEM-forward bug fixed
// 2026-08-02 in fpga/rtl/pipeline/pipelined_vpu.sv (mem_fwd_value). See
// fpga/bench/tb_fwd_hazard.sv for the full explanation and pass criteria.
//
// Exercises three back-to-back 1-cycle-apart RAW hazards through the EX
// "forward from MEM" path:
//   1. lui x7,K ; addi x7,x7,k   (exactly how `li x7,<32-bit const>` expands)
//   2. lw x3,0(x4) ; vle32.v v1,(x3)   (scalar load feeding a VPU load's
//      base address register — generic hazard/forward path, not vector-
//      specific, but confirms it works for a vector consumer too)
//   3. jal x9,jtarget ; sw x9,0(x10)   (JAL's link address, not its jump
//      target, must be what gets forwarded)
// =============================================================================
.section .text.init
.global _start
_start:
    li    x4, 0x100        # address holding the "pointer"
    li    x6, 0x200        # target vector data address
    li    x7, 0x11111111
    sw    x7, 0(x6)
    li    x7, 0x22222222   # lui x7,0x22222 ; addi x7,x7,546 -- hits case 1
    sw    x7, 4(x6)
    li    x7, 0x33333333   # lui x7,0x33333 ; addi x7,x7,819 -- hits case 1
    sw    x7, 8(x6)
    li    x7, 0x44444444
    sw    x7, 12(x6)
    sw    x6, 0(x4)        # DMEM[0x100] = 0x200 (store the pointer)

    vsetvli x0, x0, e32, m1, ta, ma

    lw    x3, 0(x4)        # SCALAR LOAD: x3 = DMEM[0x100] = 0x200
    vle32.v v1, (x3)       # VECTOR LOAD immediately next -- hits case 2

    li    x8, 0x300
    vse32.v v1, (x8)       # dump loaded vector to DMEM[0x300..] for checking

    li    x10, 0x400
    jal   x9, jtarget       # x9 = return address (this instr's PC + 4)
jtarget:
    sw    x9, 0(x10)        # store x9 immediately after jal -- hits case 3

done:
    j done
