/*
 * lena_gray.c — RGB to grayscale conversion using RVV intrinsics
 *
 * BT.601 approximation (exact match to assembly version):
 *   Y[i] = floor(R[i]*77/256) + floor(G[i]*150/256) + floor(B[i]*29/256)
 *
 * DMEM layout (loaded by testbench before execution):
 *   0x00000–0x03FFF  R channel  (16384 uint8 pixels, 128×128)
 *   0x04000–0x07FFF  G channel
 *   0x08000–0x0BFFF  B channel
 *   0x0C000–0x0FFFF  Y output   (written by this function)
 *
 * VPU config: SEW=8, LMUL=1 → VLMAX = VLEN/SEW = 128/8 = 16 elements/reg
 */

#include <riscv_vector.h>
#include <stdint.h>
#include <stddef.h>

#define N_PIXELS 16384   /* 128 × 128 */

#define R_ADDR  ((const uint8_t *)0x00000u)
#define G_ADDR  ((const uint8_t *)0x04000u)
#define B_ADDR  ((const uint8_t *)0x08000u)
#define Y_ADDR  ((      uint8_t *)0x0C000u)

void main(void)
{
    const uint8_t *r = R_ADDR;
    const uint8_t *g = G_ADDR;
    const uint8_t *b = B_ADDR;
    uint8_t       *y = Y_ADDR;

    /* AVL > 31 forces vsetvli (register form, inst[31]=0).
     * vl = min(N_PIXELS, VLMAX=16) = 16 — fixed for the full loop. */
    size_t vl = __riscv_vsetvl_e8m1(N_PIXELS);

    for (int i = 0; i < N_PIXELS; i += 16) {
        /* Load 16 pixels per channel */
        vuint8m1_t vr = __riscv_vle8_v_u8m1(r + i, vl);
        vuint8m1_t vg = __riscv_vle8_v_u8m1(g + i, vl);
        vuint8m1_t vb = __riscv_vle8_v_u8m1(b + i, vl);

        /* vmulhu.vx: high byte of (element × scalar) = floor(element * k / 256) */
        vuint8m1_t yr = __riscv_vmulhu_vx_u8m1(vr, 77,  vl);
        vuint8m1_t yg = __riscv_vmulhu_vx_u8m1(vg, 150, vl);
        vuint8m1_t yb = __riscv_vmulhu_vx_u8m1(vb, 29,  vl);

        /* Accumulate: max sum = 76+149+28 = 253 — no 8-bit overflow */
        vuint8m1_t vy = __riscv_vadd_vv_u8m1(yr, yg, vl);
        vy             = __riscv_vadd_vv_u8m1(vy, yb, vl);

        /* Store 16 grayscale pixels */
        __riscv_vse8_v_u8m1(y + i, vy, vl);
    }
}
