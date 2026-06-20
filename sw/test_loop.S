# =============================================================================
# test_loop.S — Kiểm tra multi-iteration loop (avl > vlmax)
#
# Bài toán: Nhân mỗi phần tử trong mảng 12 phần tử với scalar 3
#           Sử dụng LMUL=1, SEW=32 → vlmax=4 → cần 3 vòng lặp
#
# Thuật toán:
#   for each chunk of 4 elements:
#     vle32.v   v1, (src_ptr)        # nạp 4 phần tử
#     vmul.vx   v2, v1, multiplier   # nhân với 3
#     vse32.v   v2, (dst_ptr)        # lưu kết quả
#     advance pointers, decrement avl
#
# Bố cục DMEM (byte addr):
#   0x000–0x02F : src[12] = [1,2,3,4, 5,6,7,8, 9,10,11,12]
#   0x100–0x12F : dst[12] = kết quả mong đợi = [3,6,9,12, 15,18,21,24, 27,30,33,36]
#
# Kiểm tra: đọc lại từng phần tử, so sánh với giá trị mong đợi
# s0 = 0 → PASS | s0 = index (1-based) của phần tử sai → FAIL
# =============================================================================

.text
.globl _start

_start:
    # -----------------------------------------------------------------
    # Bước 1: Khởi tạo mảng nguồn [1..12] bằng scalar SW
    # -----------------------------------------------------------------
    li      a0, 0x000           # src base address
    li      t0, 1
    sw      t0,  0(a0)
    li      t0, 2
    sw      t0,  4(a0)
    li      t0, 3
    sw      t0,  8(a0)
    li      t0, 4
    sw      t0, 12(a0)
    li      t0, 5
    sw      t0, 16(a0)
    li      t0, 6
    sw      t0, 20(a0)
    li      t0, 7
    sw      t0, 24(a0)
    li      t0, 8
    sw      t0, 28(a0)
    li      t0, 9
    sw      t0, 32(a0)
    li      t0, 10
    sw      t0, 36(a0)
    li      t0, 11
    sw      t0, 40(a0)
    li      t0, 12
    sw      t0, 44(a0)

    # -----------------------------------------------------------------
    # Bước 2: Multi-iteration loop
    #   a4 = avl (số phần tử còn lại cần xử lý)
    #   a5 = src_ptr (con trỏ nguồn, tính bằng byte)
    #   a6 = dst_ptr (con trỏ đích, tính bằng byte)
    #   a7 = multiplier = 3
    # -----------------------------------------------------------------
    li      a4, 12              # avl = 12 phần tử
    li      a5, 0x000           # src_ptr
    li      a6, 0x100           # dst_ptr
    li      a7, 3               # scalar nhân = 3

loop:
    vsetvli x0, a4, e32, m1, ta, ma    # đặt vl = min(a4, 4), bỏ rd (x0)
    csrr    t0, vl                      # t0 = vl thực tế từ CSR

    vle32.v  v1, 0(a5)                  # nạp t0 phần tử từ src
    vmul.vx  v2, v1, a7                 # v2 = v1 * 3
    vse32.v  v2, 0(a6)                  # lưu t0 phần tử vào dst

    slli    t1, t0, 2                   # t1 = vl * 4 (byte offset)
    add     a5, a5, t1                  # src_ptr += vl*4
    add     a6, a6, t1                  # dst_ptr += vl*4
    sub     a4, a4, t0                  # avl -= vl
    bnez    a4, loop                    # tiếp tục nếu còn phần tử

    # -----------------------------------------------------------------
    # Bước 3: Kiểm tra kết quả [3,6,9,12,15,18,21,24,27,30,33,36]
    # -----------------------------------------------------------------
    li      s0, 0               # PASS flag
    li      a6, 0x100           # dst base

    # Kiểm tra từng phần tử (dùng loop để gọn)
    li      s1, 1               # expected value bắt đầu từ 3 (= 1*3)
    li      s2, 0               # index = 0
check_loop:
    slli    t2, s2, 2
    add     t2, t2, a6          # addr = dst + index*4
    lw      t3, 0(t2)           # đọc kết quả

    li      t4, 3
    mul     t4, s1, t4          # expected = index_1based * 3
    bne     t3, t4, check_fail

    addi    s1, s1, 1
    addi    s2, s2, 1
    li      t4, 12
    blt     s2, t4, check_loop

pass:
    li      s0, 0
    j       done

check_fail:
    addi    s0, s2, 1           # s0 = 1-based index của phần tử sai
    j       done

done:
    j       done
