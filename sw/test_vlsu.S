# =============================================================================
# test_vlsu.S — Kiểm tra vector load/store (VLE32.V / VSE32.V)
#
# Mục tiêu:
#   1. Ghi dữ liệu vào DMEM bằng scalar SW
#   2. Dùng VLE32.V nạp vào VRF (v1)
#   3. Dùng VADD.VX tính v2 = v1 + 1
#   4. Dùng VSE32.V ghi v2 ngược lại vùng nhớ khác
#   5. Dùng scalar LW đọc lại và kiểm tra kết quả
#
# Kết quả đúng: s0 = 0 (PASS), s0 != 0 (FAIL, s0 = địa chỉ lỗi)
#
# Bố cục DMEM (byte addr):
#   0x000–0x00F : src_array  = [10, 20, 30, 40]  (4 x 32-bit words)
#   0x100–0x10F : dst_array  = kết quả sau VSE32.V = [11, 21, 31, 41]
# =============================================================================

.text
.globl _start

_start:
    # -----------------------------------------------------------------
    # Bước 1: Ghi mảng nguồn vào DMEM bằng SW
    # Địa chỉ base = 0x000
    # -----------------------------------------------------------------
    li      a0, 0x000           # base address của src_array

    li      t0, 10
    sw      t0,  0(a0)          # dmem[0]  = 10

    li      t0, 20
    sw      t0,  4(a0)          # dmem[1]  = 20

    li      t0, 30
    sw      t0,  8(a0)          # dmem[2]  = 30

    li      t0, 40
    sw      t0, 12(a0)          # dmem[3]  = 40

    # -----------------------------------------------------------------
    # Bước 2: Cấu hình VPU: SEW=32, LMUL=1, 4 phần tử
    # -----------------------------------------------------------------
    li      a1, 4
    vsetvli x0, a1, e32, m1, ta, ma     # vl = 4

    # -----------------------------------------------------------------
    # Bước 3: VLE32.V — nạp 4 words từ DMEM[0..3] vào v1
    # -----------------------------------------------------------------
    vle32.v v1, 0(a0)           # v1 = [10, 20, 30, 40]

    # -----------------------------------------------------------------
    # Bước 4: VADD.VX — v2 = v1 + 1 = [11, 21, 31, 41]
    # -----------------------------------------------------------------
    li      t1, 1
    vadd.vx v2, v1, t1          # v2 = [11, 21, 31, 41]

    # -----------------------------------------------------------------
    # Bước 5: VSE32.V — ghi v2 vào DMEM[0x100..0x10F]
    # -----------------------------------------------------------------
    li      a2, 0x100           # base address của dst_array
    vse32.v v2, 0(a2)           # dmem[0x100..0x10F] = [11, 21, 31, 41]

    # -----------------------------------------------------------------
    # Bước 6: Dùng scalar LW đọc lại và kiểm tra
    # s0 = 0 nghĩa là PASS
    # -----------------------------------------------------------------
    li      s0, 0               # PASS flag (0 = pass)

    lw      t2,  0(a2)
    li      t3, 11
    bne     t2, t3, fail_0      # expected[0] = 11

    lw      t2,  4(a2)
    li      t3, 21
    bne     t2, t3, fail_1      # expected[1] = 21

    lw      t2,  8(a2)
    li      t3, 31
    bne     t2, t3, fail_2      # expected[2] = 31

    lw      t2, 12(a2)
    li      t3, 41
    bne     t2, t3, fail_3      # expected[3] = 41

pass:
    li      s0, 0
    j       done

fail_0: li s0, 0x10 ; j done
fail_1: li s0, 0x14 ; j done
fail_2: li s0, 0x18 ; j done
fail_3: li s0, 0x1C ; j done

done:
    j       done                # loop giữ simulation dừng
