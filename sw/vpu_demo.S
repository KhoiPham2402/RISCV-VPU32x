# =============================================================================
# vpu_demo.S — VPU full-path demo program
#
# Chạy toàn bộ data path:
#   Scalar store → DMEM → vle32.v → VRF → VPU ops → VRF → vse32.v → DMEM
#
# Data:
#   DMEM[0x0800]: Input A = {10, 20, 30, 40}    (4 × int32)
#   DMEM[0x0810]: Input B = {1,  2,  3,  4}     (4 × int32)
#   DMEM[0x0820]: Result  vadd.vv  = {11,22,33,44}
#   DMEM[0x0830]: Result  vsub.vv  = {9,18,27,36}
#   DMEM[0x0840]: Result  vmul.vv  = {10,40,90,160}
#   DMEM[0x0850]: Result  vxor.vv  = {11,22,29,44}
#   DMEM[0x0860]: Result  vadd.vx  = {60,70,80,90}   (scalar=50)
#   DMEM[0x0870]: Result  vredsum  = {101,0,0,0}      (1+10+20+30+40)
#
# HEX0 display (active-low 7-seg): tiến trình chương trình
#   '0' = khởi tạo xong
#   '1' = data đã ghi vào DMEM
#   '2' = VPU đã cấu hình (vsetvli xong)
#   '3' = vectors đã load vào VRF (vle32.v)
#   '4' = vadd/vsub/vmul/vxor xong
#   '5' = vadd.vx + vredsum xong
#   'd' = kết quả đã store về DMEM + done
#
# Địa chỉ IO: HEXL=0x10002000 (bits[15:12]=2)
# =============================================================================

.section .text
.global _start

# ── Địa chỉ bộ nhớ ──
.equ HEXL,    0x10002000
.equ DMEM_A,  0x0800       # Input vector A base
.equ DMEM_B,  0x0810       # Input vector B base
.equ DMEM_R0, 0x0820       # Result base (vadd)
.equ DMEM_R1, 0x0830       # vsub
.equ DMEM_R2, 0x0840       # vmul
.equ DMEM_R3, 0x0850       # vxor
.equ DMEM_R4, 0x0860       # vadd.vx
.equ DMEM_R5, 0x0870       # vredsum

# ── Active-low 7-segment codes ──
.equ SEG_0,  0x7F7F7F40    # HEX="0"
.equ SEG_1,  0x7F7F7F79    # HEX="1"
.equ SEG_2,  0x7F7F7F24    # HEX="2"
.equ SEG_3,  0x7F7F7F30    # HEX="3"
.equ SEG_4,  0x7F7F7F19    # HEX="4"
.equ SEG_5,  0x7F7F7F12    # HEX="5"
.equ SEG_d,  0x7F7F7F5E    # HEX="d" (done)

_start:
    # ── [HEX=0] Bắt đầu ───────────────────────────────────────────────────────
    li   t0, HEXL
    li   t1, SEG_0
    sw   t1, 0(t0)

    # ── [STEP 1] Scalar store: ghi data A={10,20,30,40} vào DMEM ──────────────
    li   a0, DMEM_A
    li   t1, 10;   sw t1,  0(a0)
    li   t1, 20;   sw t1,  4(a0)
    li   t1, 30;   sw t1,  8(a0)
    li   t1, 40;   sw t1, 12(a0)

    # Ghi data B={1,2,3,4} vào DMEM
    li   a1, DMEM_B
    li   t1, 1;    sw t1,  0(a1)
    li   t1, 2;    sw t1,  4(a1)
    li   t1, 3;    sw t1,  8(a1)
    li   t1, 4;    sw t1, 12(a1)

    # ── [HEX=1] Data đã ghi vào DMEM ─────────────────────────────────────────
    li   t1, SEG_1
    sw   t1, 0(t0)

    # ── [STEP 2] VPU config: vsetvli e32 m1 vl=4 ─────────────────────────────
    # Gọi vsetvli: rd=t2 nhận lại vl thực tế từ VPU qua vpu_vl_remain
    li   a2, 4
    vsetvli t2, a2, e32, m1, ta, ma

    # ── [HEX=2] VPU đã được cấu hình ─────────────────────────────────────────
    li   t1, SEG_2
    sw   t1, 0(t0)

    # ── [STEP 3] Vector load từ DMEM vào VRF ──────────────────────────────────
    vle32.v  v8, (a0)      # v8 = DMEM[a0..a0+12] = {10, 20, 30, 40}
    vle32.v  v9, (a1)      # v9 = DMEM[a1..a1+12] = {1,  2,  3,  4}

    # ── [HEX=3] Vectors đã load xong ─────────────────────────────────────────
    li   t1, SEG_3
    sw   t1, 0(t0)

    # ── [STEP 4] Arithmetic vector operations ─────────────────────────────────
    # v2 = v8 + v9  →  {11, 22, 33, 44}
    vadd.vv  v2, v8, v9

    # v3 = v8 - v9  →  {9, 18, 27, 36}
    vsub.vv  v3, v8, v9

    # v4 = v8 * v9  →  {10, 40, 90, 160}
    vmul.vv  v4, v8, v9

    # v5 = v8 XOR v9  →  {10^1, 20^2, 30^3, 40^4} = {11, 22, 29, 44}
    vxor.vv  v5, v8, v9

    # ── [HEX=4] ALU ops (vadd/vsub/vmul/vxor) xong ───────────────────────────
    li   t1, SEG_4
    sw   t1, 0(t0)

    # ── [STEP 5] Scalar-vector ops + reduction ────────────────────────────────
    # v6 = v8 + scalar(50)  →  {60, 70, 80, 90}
    li   s0, 50
    vadd.vx  v6, v8, s0

    # v7[0] = v9[0] + sum(v8)  →  1 + (10+20+30+40) = 101
    # vredsum.vs vd, vs2, vs1: result = vs1[0] + sum(vs2)
    vredsum.vs v7, v8, v9

    # ── [HEX=5] Scalar+reduction xong ────────────────────────────────────────
    li   t1, SEG_5
    sw   t1, 0(t0)

    # ── [STEP 6] Store results về DMEM ────────────────────────────────────────
    li   a3, DMEM_R0
    vse32.v  v2, (a3)          # {11, 22, 33, 44}
    addi a3, a3, 16
    vse32.v  v3, (a3)          # {9, 18, 27, 36}
    addi a3, a3, 16
    vse32.v  v4, (a3)          # {10, 40, 90, 160}
    addi a3, a3, 16
    vse32.v  v5, (a3)          # {11, 22, 29, 44}
    addi a3, a3, 16
    vse32.v  v6, (a3)          # {60, 70, 80, 90}
    addi a3, a3, 16
    vse32.v  v7, (a3)          # {101, 0, 0, 0}

    # ── [STEP 7] Scalar read-back verify ──────────────────────────────────────
    # Đọc lại kết quả vadd từ DMEM về thanh ghi scalar để verify
    # Kỳ vọng: s1=11, s2=22, s3=33, s4=44
    li   a4, DMEM_R0
    lw   s1,  0(a4)   # s1 = result_vadd[0] = 11
    lw   s2,  4(a4)   # s2 = result_vadd[1] = 22
    lw   s3,  8(a4)   # s3 = result_vadd[2] = 33
    lw   s4, 12(a4)   # s4 = result_vadd[3] = 44

    # Đọc kết quả vmul để có pattern đẹp khi nhìn waveform
    li   a5, DMEM_R2
    lw   s5,  0(a5)   # s5 = vmul[0] = 10
    lw   s6,  4(a5)   # s6 = vmul[1] = 40
    lw   s7,  8(a5)   # s7 = vmul[2] = 90
    lw   s8, 12(a5)   # s8 = vmul[3] = 160

    # Đọc kết quả vredsum
    li   a6, DMEM_R5
    lw   s9,  0(a6)   # s9 = vredsum = 101

    # ── [HEX=d] DONE ─────────────────────────────────────────────────────────
    li   t1, SEG_d
    sw   t1, 0(t0)

done:
    j    done
