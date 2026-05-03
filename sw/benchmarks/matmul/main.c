/*
 * Matmul benchmark: C = A * B, 4x4 int32.
 * A = [[1..4],[5..8],[9..12],[13..16]], B = all-ones.
 * Expected C row sums: row0=10, row1=26, row2=42, row3=58.
 * mailbox[0..3] = C[0][0], C[1][0], C[2][0], C[3][0].
 *
 * Harvard arch: all data stack-allocated (no static const).
 */
#include <stdint.h>

void matmul_4x4(const int32_t A[4][4], const int32_t B[4][4], int32_t C[4][4]);

int main(void) {
    int32_t A[4][4], B[4][4], C[4][4];
    int i, j;

    for (i = 0; i < 4; i++)
        for (j = 0; j < 4; j++)
            A[i][j] = i * 4 + j + 1;   /* 1..16 row-major */

    for (i = 0; i < 4; i++)
        for (j = 0; j < 4; j++)
            B[i][j] = 1;

    matmul_4x4(A, B, C);

    volatile int32_t *mailbox = (volatile int32_t *)0x1E0;
    mailbox[0] = C[0][0];  /* expected: 10 */
    mailbox[1] = C[1][0];  /* expected: 26 */
    mailbox[2] = C[2][0];  /* expected: 42 */
    mailbox[3] = C[3][0];  /* expected: 58 */

    return 0;
}
