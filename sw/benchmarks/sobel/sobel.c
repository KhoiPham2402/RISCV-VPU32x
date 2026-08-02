/*
 * sobel.c — 3x3 Sobel edge detection, |Gx|+|Gy| approximation, RVV intrinsics.
 *
 * DMEM layout (loaded by testbench before execution):
 *   0x1000–0x4FFF  input   64x64 grayscale pixels, 1 pixel / 32-bit word
 *   0x5000–0x8FFF  output  64x64 edge magnitude,   1 pixel / 32-bit word
 *                          (pre-zeroed by prep_sobel.py — this function only
 *                          writes the interior [1..62]x[1..62] region)
 *
 * Why 1 pixel / word instead of 1 byte / word like lena_gray.c:
 *   The VLSU discards addr[1:0] (vproc_vec_lsu.sv address arithmetic, and
 *   every DMEM consumer indexes with addr[15:2]) — there is no byte or
 *   halfword rotation for vector loads/stores. A +-1-pixel horizontal tap
 *   is only a valid, distinct, *aligned* load if 1 pixel occupies exactly
 *   one 32-bit word. Do NOT switch this to an 8- or 16-bit-per-pixel plane;
 *   the left/right taps below would silently alias onto the center pixel.
 *   (Tracked as project issue #25 — VLSU sub-word addressing.)
 *
 * Why no shift instructions anywhere in this file:
 *   fpga/rtl/vpu/vproc_vdecoder.sv / vproc_processor_lane.sv encode
 *   vsll/vsrl/vsra with funct6 values that don't match real RVV 1.0. Real
 *   RVV vsll (funct6=100101) collides with this RTL's own VMUL encoding —
 *   GCC-compiled shift intrinsics would silently execute as a multiply (or
 *   hit no case at all for vsrl/vsra). "x2" below is done as vadd_vv(x,x)
 *   instead. (Tracked as project issue #24.) `make check-isa` greps the
 *   disassembly for forbidden instructions and fails the build if any slip
 *   in — see Makefile.
 *
 * Arithmetic: all unsigned, SEW=32/LMUL=1 (VLMAX=4 for VLEN=128). Every
 * intermediate sum is <= 1020 (4 taps x 255 max), well within 32 bits, so
 * there is no overflow at any step — no widening needed either. |Gx|/|Gy|
 * are computed as max(pos,neg) - min(pos,neg) (both operands non-negative
 * by construction, so the unsigned subtraction is always safe) instead of
 * a compare+select-based abs(), since vminu/vmaxu are simpler and already
 * proven working (used by matmul.c's vmv.v.x zero-init path indirectly,
 * and directly here).
 *
 * Border rows/columns (0 and 63) have no full 3x3 neighborhood and are
 * left at 0 by the output pre-zero in prep_sobel.py.
 */
#include <riscv_vector.h>
#include <stdint.h>
#include <stddef.h>

#define W 64
#define H 64
#define IN_BASE  ((const uint32_t *)0x1000u)
#define OUT_BASE ((      uint32_t *)0x5000u)

void main(void)
{
    for (int r = 1; r < H - 1; r++) {
        const uint32_t *pu = IN_BASE + (size_t)(r - 1) * W;  /* row above  */
        const uint32_t *pc = IN_BASE + (size_t)(r    ) * W;  /* this row   */
        const uint32_t *pd = IN_BASE + (size_t)(r + 1) * W;  /* row below  */
        uint32_t       *po = OUT_BASE + (size_t)r * W;

        int j = 1, n = W - 2;
        while (n > 0) {
            size_t vl = __riscv_vsetvl_e32m1((size_t)n);

            vuint32m1_t uL = __riscv_vle32_v_u32m1(pu + j - 1, vl);
            vuint32m1_t uC = __riscv_vle32_v_u32m1(pu + j,     vl);
            vuint32m1_t uR = __riscv_vle32_v_u32m1(pu + j + 1, vl);
            vuint32m1_t cL = __riscv_vle32_v_u32m1(pc + j - 1, vl);
            vuint32m1_t cR = __riscv_vle32_v_u32m1(pc + j + 1, vl);
            vuint32m1_t dL = __riscv_vle32_v_u32m1(pd + j - 1, vl);
            vuint32m1_t dC = __riscv_vle32_v_u32m1(pd + j,     vl);
            vuint32m1_t dR = __riscv_vle32_v_u32m1(pd + j + 1, vl);

            /* Gx kernel: [-1 0 1; -2 0 2; -1 0 1] -> posX (right col taps)
             * minus negX (left col taps); center column has weight 0. */
            vuint32m1_t posX = __riscv_vadd_vv_u32m1(cR, cR, vl);
            posX = __riscv_vadd_vv_u32m1(posX, uR, vl);
            posX = __riscv_vadd_vv_u32m1(posX, dR, vl);
            vuint32m1_t negX = __riscv_vadd_vv_u32m1(cL, cL, vl);
            negX = __riscv_vadd_vv_u32m1(negX, uL, vl);
            negX = __riscv_vadd_vv_u32m1(negX, dL, vl);
            vuint32m1_t gx = __riscv_vsub_vv_u32m1(
                                __riscv_vmaxu_vv_u32m1(posX, negX, vl),
                                __riscv_vminu_vv_u32m1(posX, negX, vl), vl);

            /* Gy kernel: [-1 -2 -1; 0 0 0; 1 2 1] -> posY (bottom row taps)
             * minus negY (top row taps); center row has weight 0. */
            vuint32m1_t posY = __riscv_vadd_vv_u32m1(dC, dC, vl);
            posY = __riscv_vadd_vv_u32m1(posY, dL, vl);
            posY = __riscv_vadd_vv_u32m1(posY, dR, vl);
            vuint32m1_t negY = __riscv_vadd_vv_u32m1(uC, uC, vl);
            negY = __riscv_vadd_vv_u32m1(negY, uL, vl);
            negY = __riscv_vadd_vv_u32m1(negY, uR, vl);
            vuint32m1_t gy = __riscv_vsub_vv_u32m1(
                                __riscv_vmaxu_vv_u32m1(posY, negY, vl),
                                __riscv_vminu_vv_u32m1(posY, negY, vl), vl);

            /* Magnitude approximation |Gx|+|Gy| (no sqrt unit exists),
             * saturated to 255 so the output stays a valid pixel value. */
            vuint32m1_t g = __riscv_vadd_vv_u32m1(gx, gy, vl);
            g = __riscv_vminu_vx_u32m1(g, 255u, vl);

            __riscv_vse32_v_u32m1(po + j, g, vl);
            j += (int)vl;
            n -= (int)vl;
        }
    }
}
