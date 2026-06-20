#-------------------------------------------------------------------------
# Testbench: VALU Comprehensive (No vmv)
# Cấu hình: VLEN=128, SEW=32, LMUL=1
#-------------------------------------------------------------------------

.text
.globl _start

_start:
    # 1. CẤU HÌNH HỆ THỐNG
    li      a0, 4           # AVL = 4
    vsetvli t0, a0, e32, m1, ta, ma
    
    # 2. "NẠP" DỮ LIỆU BẰNG VADD.VX (Giả sử v0 đang bằng 0)
    # v1 = v0 + 50 = [50, 50, 50, 50]
    li      a1, 50
    vadd.vx v1, v0, a1      
    
    # v2 = v0 + 10 = [10, 10, 10, 10]
    li      a2, 10
    vadd.vx v2, v0, a2      

    # 3. KIỂM TRA HÀNG ĐỢI (FIFO) & SCALAR PARALLEL
    # Nạp liên tục 3 lệnh Vector vào FIFO
    vadd.vv v3, v1, v2      # v3 = 60
    vsub.vv v4, v1, v2      # v4 = 40
    vmul.vv v5, v2, v2      # v5 = 100
    
    # Lệnh Scalar xen kẽ (Scalar Core phải chạy ngay, không đợi VPU)
    addi    s1, x0, 1       # Marker 1
    li      s2, 0xAAAA      # Marker 2

    # 4. TEST LOGIC & COMPARE (TẠO MASK)
    # v7 = v1 + 10 = 60
    vadd.vx v7, v1, a2      
    
    # So sánh: v0 = (v7 == 60) ? 1 : 0
    # Vì v7=[60,60,60,60] nên v0 sẽ nhận mask 0xF (tất cả bit 1)
    vmseq.vi v0, v7, 60     

    # 5. TEST MASKED OPERATION
    # v8 = v1 (50) + v2 (10) chỉ tại những vị trí v0.t = 1
    # Trước đó nạp v8 = 0 bằng cách cộng v0 với x0
    vadd.vx v8, v0, x0      # Khởi tạo v8 = 0
    vadd.vv v8, v1, v2, v0.t # v8 sẽ thành [60, 60, 60, 60]

    # 6. TEST WIDENING (32-bit -> 64-bit)
    # vwadd.vv vd, vs2, vs1
    # v10 (đích) sẽ chiếm v10 và v11 vì kết quả là 64-bit
    vwadd.vv v10, v1, v2    # v10, v11 = 60 (64-bit)

    # 7. LỆNH SCALAR CUỐI CÙNG
    addi    s1, s1, 1       # s1 phải bằng 2
    
    # Đọc CSR để kiểm tra lần cuối
    csrr    t1, vl
    csrr    t2, vtype

success_end:
    j       success_end