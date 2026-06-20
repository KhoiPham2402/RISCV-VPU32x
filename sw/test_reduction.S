# =============================================================================
# test_reduction.S — Kiểm tra reduction operations (vredsum, vredmax, vredmin)
#
# Bài toán:
#   Cho mảng: v1 = [5, 12, 3, 8]  (4 phần tử, SEW=32, LMUL=1)
#   Accumulator ban đầu: vs1[0] = 0
#
#   Test 1: vredsum.vs v3, v1, v2  (vs1=v2, initial acc=0)
#           → v3[0] = 0 + 5+12+3+8 = 28
#
#   Test 2: vredmax.vs v4, v1, v2
#           → v4[0] = max(0, 5,12,3,8) = 12
#
#   Test 3: vredmin.vs v5, v1, v2  (vs1=v2, initial acc=100)
#           → v5[0] = min(100, 5,12,3,8) = 3
#
# Kết quả kiểm tra:
#   Dùng VMV.X.S (nếu hỗ trợ) hoặc VSE32.V + LW để đọc kết quả từ VRF
#
# s0 = 0 → PASS | s0 != 0 → FAIL (mã lỗi)
# =============================================================================

.text
.globl _start

_start:
    # -----------------------------------------------------------------
    # Cấu hình: SEW=32, LMUL=1, 4 phần tử
    # -----------------------------------------------------------------
    li      a0, 4
    vsetvli x0, a0, e32, m1, ta, ma

    # -----------------------------------------------------------------
    # Khởi tạo vector nguồn v1 = [5, 12, 3, 8]
    # Dùng scalar SW + VLE32.V qua DMEM
    # -----------------------------------------------------------------
    li      a1, 0x000           # src base

    li      t0, 5
    sw      t0,  0(a1)
    li      t0, 12
    sw      t0,  4(a1)
    li      t0, 3
    sw      t0,  8(a1)
    li      t0, 8
    sw      t0, 12(a1)

    vle32.v v1, 0(a1)           # v1 = [5, 12, 3, 8]

    # -----------------------------------------------------------------
    # Khởi tạo accumulator v2[0] = 0 (dùng VMV.V.X)
    # -----------------------------------------------------------------
    vmv.v.x v2, x0              # v2 = [0, 0, 0, 0]

    # -----------------------------------------------------------------
    # Test 1: vredsum.vs — tổng của tất cả phần tử
    # Kết quả: v3[0] = 0 + 5 + 12 + 3 + 8 = 28
    # -----------------------------------------------------------------
    vredsum.vs v3, v1, v2       # v3[0] = sum(v1) + v2[0] = 28

    # Đọc kết quả qua DMEM
    li      a2, 0x100           # dst_base
    vse32.v v3, 0(a2)
    lw      t1, 0(a2)           # t1 = v3[0]

    li      t2, 28
    bne     t1, t2, fail_sum

    # -----------------------------------------------------------------
    # Test 2: vredmax.vs — giá trị lớn nhất
    # Kết quả: v4[0] = max(v2[0]=0, 5,12,3,8) = 12
    # -----------------------------------------------------------------
    vredmax.vs v4, v1, v2       # v4[0] = max(0, 5,12,3,8) = 12

    vse32.v v4, 0(a2)
    lw      t1, 0(a2)

    li      t2, 12
    bne     t1, t2, fail_max

    # -----------------------------------------------------------------
    # Test 3: vredmin.vs — giá trị nhỏ nhất
    # Khởi tạo accumulator v2[0] = 100 (lớn hơn mọi phần tử)
    # Kết quả: v5[0] = min(100, 5,12,3,8) = 3
    # -----------------------------------------------------------------
    li      t0, 100
    vmv.v.x v2, t0              # v2 = [100, 100, 100, 100]

    vredmin.vs v5, v1, v2       # v5[0] = min(100, 5,12,3,8) = 3

    vse32.v v5, 0(a2)
    lw      t1, 0(a2)

    li      t2, 3
    bne     t1, t2, fail_min

pass:
    li      s0, 0               # PASS
    j       done

fail_sum: li s0, 1 ; j done     # vredsum sai
fail_max: li s0, 2 ; j done     # vredmax sai
fail_min: li s0, 3 ; j done     # vredmin sai

done:
    j       done
