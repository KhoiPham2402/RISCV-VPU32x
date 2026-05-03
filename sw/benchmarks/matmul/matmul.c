#include <stdint.h>
#include <riscv_vector.h>

/*
 * 4x4 int32 matrix multiply: C = A * B (row-major).
 * Outer-product pattern: for each scalar A[i][k], load B[k][*], scale by A[i][k],
 * add into C[i][*].  Uses vmul.vx + vadd.vv (matches verified bench_matmul.S).
 * vmacc is NOT used — not implemented in this RTL.
 */
void matmul_4x4(const int32_t A[4][4], const int32_t B[4][4], int32_t C[4][4]) {
    int i, k;

    for (i = 0; i < 4; i++) {
        size_t vl = __riscv_vsetvl_e32m1(4);
        vint32m1_t vzero = __riscv_vmv_v_x_i32m1(0, vl);
        __riscv_vse32_v_i32m1(C[i], vzero, vl);

        for (k = 0; k < 4; k++) {
            vl = __riscv_vsetvl_e32m1(4);
            vint32m1_t vb  = __riscv_vle32_v_i32m1(B[k], vl);
            vint32m1_t vp  = __riscv_vmul_vx_i32m1(vb, (int32_t)A[i][k], vl);
            vint32m1_t vc  = __riscv_vle32_v_i32m1(C[i], vl);
            vint32m1_t vs  = __riscv_vadd_vv_i32m1(vc, vp, vl);
            __riscv_vse32_v_i32m1(C[i], vs, vl);
        }
    }
}
