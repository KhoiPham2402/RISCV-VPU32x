/*
 * AXPY benchmark: y[i] += a * x[i], N=16 elements, a=3
 * Results mailbox at DMEM[0x1E0..0x1EC]: y[0], y[4], y[8], y[12]
 *
 * Harvard arch constraint: all data must be stack-allocated (not static/global)
 * because .rodata lives in IMEM and is not accessible via lw/vle32.v.
 *
 * Expected: x[i]=i+1, y[i]=1, a=3 → y[i] = 1 + 3*(i+1)
 *   y[0]=4, y[4]=16, y[8]=28, y[12]=40
 */
#include <stdint.h>

void axpy(int32_t a, const int32_t *x, int32_t *y, int n);

#define N 16

int main(void) {
    int32_t x[N], y[N];
    int i;

    /* Initialize on stack — cannot use static const arrays */
    for (i = 0; i < N; i++) {
        x[i] = i + 1;   /* 1, 2, ..., 16 */
        y[i] = 1;
    }

    axpy(3, x, y, N);

    /* Write 4 sample results to mailbox so testbench can verify */
    volatile int32_t *mailbox = (volatile int32_t *)0x1E0;
    mailbox[0] = y[0];   /* expected: 4  */
    mailbox[1] = y[4];   /* expected: 16 */
    mailbox[2] = y[8];   /* expected: 28 */
    mailbox[3] = y[12];  /* expected: 40 */

    return 0;
}
