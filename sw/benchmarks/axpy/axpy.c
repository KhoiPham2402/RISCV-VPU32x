#include <stdint.h>
#include <riscv_vector.h>

/* y[i] += a * x[i]  for i in [0, n) */
void axpy(int32_t a, const int32_t *x, int32_t *y, int n) {
    while (n > 0) {
        size_t vl = __riscv_vsetvl_e32m1(n);
        vint32m1_t vx = __riscv_vle32_v_i32m1(x, vl);
        vint32m1_t vy = __riscv_vle32_v_i32m1(y, vl);
        vint32m1_t vt = __riscv_vmul_vx_i32m1(vx, a, vl);
        vy = __riscv_vadd_vv_i32m1(vy, vt, vl);
        __riscv_vse32_v_i32m1(y, vy, vl);
        x += vl;
        y += vl;
        n -= vl;
    }
}
