# FIX_REPORT.md — Báo cáo sửa lỗi & bổ sung test

> Ngày thực hiện: 2026-04-27
> Mục tiêu: Chuẩn bị hệ thống chạy benchmark thực tế ở tần số thấp trên single-cycle core

---

## Tổng quan

Sau khi đọc toàn bộ source code từ `lsu.sv`, `vproc_fsm.sv`, `vproc_vec_lsu.sv`, `vproc_system_wrapper.sv`, `control_unit.sv` và `vproc_cycle_counter.sv`, tìm thấy **3 bug thực sự** và **3 vùng test còn thiếu hoàn toàn**.

---

## BUG #1 — `control_unit.sv`: `rd_wren=1` cho MỌI lệnh OP-V

### Vấn đề
**File:** [rtl/riscv/control_unit.sv](rtl/riscv/control_unit.sv) — dòng 238–241

```systemverilog
// CODE CŨ (SAI)
if (func3 == 3'b111)
    is_vpu_config = 1'b1;
    rd_wren      = 1'b1;   // ← KHÔNG có begin/end → luôn chạy!
```

Trong SystemVerilog, `if` không có `begin`/`end` chỉ bao một câu lệnh. Dòng `rd_wren = 1'b1` nằm NGOÀI if, nên nó luôn được thực thi với MỌI lệnh OP-V, kể cả `vadd`, `vsub`, `vmul`...

### Hậu quả

Với mọi lệnh vector như `vadd.vv v3, v1, v2`:
- `inst[11:7] = 3` → đây là địa chỉ của scalar register x3 (gp)
- `rd_wren=1` → register file **ghi đè x3** với giá trị rác từ DMEM
- Bất kỳ scalar register nào trùng số với `vd` của lệnh vector đều bị hỏng

**Ví dụ thiệt hại:**
| Lệnh vector | vd | Scalar bị hỏng |
|-------------|-----|----------------|
| `vadd.vv v1, ...` | 1 | x1 = ra (return address!) |
| `vmul.vv v5, ...` | 5 | x5 = t0 |
| `vadd.vx v10, ...` | 10 | x10 = a0 (argument/return) |

Lý do test hiện tại chưa bắt được: `test_alu.S` không kiểm tra lại giá trị scalar sau lệnh vector.

### Fix

```systemverilog
// CODE MỚI (ĐÚNG)
if (func3 == 3'b111) begin
    is_vpu_config = 1'b1;
    rd_wren      = 1'b1;   // chỉ set cho vsetvl/vsetvli
end
```

**Tại sao rd_wren=1 lại cần cho vsetvli?** Vì writeback của vsetvli đi qua path:
```
wire rd_wren_eff = i_vpu_cfg_done | rd_wren;
wire wb_data_eff = i_vpu_cfg_done ? i_vpu_vl_remain : wb_data;
```
Khi `cfg_done` fire, `rd_wren_eff=1` và dữ liệu là `vl_remain` (đúng). Với fix mới, các lệnh OP-V thông thường không còn ghi nhầm vào scalar register nữa.

---

## BUG #2 — `vproc_cycle_counter.sv`: `done` không phân biệt "chưa bắt đầu" và "đã xong"

### Vấn đề
**File:** [rtl/vproc_cycle_counter.sv](rtl/vproc_cycle_counter.sv) — dòng 141

```systemverilog
// CODE CŨ
assign done = (cycles_left_r == 4'd0);
```

Sau reset: `cycles_left_r=0`, `running_r=0` → `done=1` ngay từ đầu, dù chưa có lệnh nào chạy.

### Hậu quả

Nếu FSM vì lý do nào đó bước vào trạng thái `ST_EXEC` mà không kèm theo `counter_start` (ví dụ sau reset, hay do timing issue trong tương lai), `done=1` ngay lập tức và FSM thoát `ST_EXEC` **mà không thực thi gì**. Lệnh vector bị bỏ qua hoàn toàn.

Về tapeout: một tín hiệu `done=1` khi hệ thống idle là mầm mống gây lỗi khó debug nếu logic phụ thuộc vào nó sau này.

### Fix

```systemverilog
// CODE MỚI
assign done = (cycles_left_r == 4'd0) && running_r;
```

Bây giờ `done=1` CHỈ KHI đang thực sự chạy (`running_r=1`) VÀ đã đếm xong. Khi idle: `running_r=0` → `done=0`. Không còn spurious done.

**Lưu ý:** Fix này không thay đổi timing cho hoạt động bình thường:
- m1: sau `start`, `cycles_left_r=0` và `running_r=1` → `done=1` đúng từ chu kỳ EXEC đầu tiên ✓
- m2: `cycles_left_r=1` sau start → `done=0` → FSM ở lại EXEC → sau 1 chu kỳ `cycles_left_r→0` → `done=1` ✓

---

## BUG #3 — `vproc_system_wrapper.sv`: `is_compare_r` bỏ sót 5/8 lệnh compare

### Vấn đề
**File:** [rtl/vproc_system_wrapper.sv](rtl/vproc_system_wrapper.sv) — dòng 147

```systemverilog
// CODE CŨ (CHỈ COVER 3/8)
wire is_compare_r = (funct6_r == 6'b011000) ||   // vmseq  ✓
                    (funct6_r == 6'b011011) ||   // vmslt  ✓
                    (funct6_r == 6'b011010);     // vmsltu ✓
// THIẾU:
//   vmsne  = 6'b011001
//   vmsleu = 6'b011100
//   vmsle  = 6'b011101
//   vmsgtu = 6'b011110
//   vmsgt  = 6'b011111
```

### Hậu quả

Signal `is_compare` được truyền vào processor_lane để chọn output đúng (mask result vs ALU result). Nếu `is_compare=0` khi đang chạy `vmsne`/`vmsle`/`vmsgt`..., processor_lane sẽ ghi kết quả sai vào VRF — lệnh so sánh bị silent fail.

### Fix

```systemverilog
// CODE MỚI — tất cả 8 lệnh compare đều có funct6[5:3] = 3'b011
wire is_compare_r = (funct6_r[5:3] == 3'b011);
```

Tất cả lệnh compare trong Zve32x có funct6 từ 011000–011111, tức `funct6[5:3]=011`. Không lệnh nào khác trong subset này dùng pattern này.

---

## TEST MỚI #1 — `sw/test_vlsu.S`: Kiểm tra VLE32.V / VSE32.V

### Tại sao phải có test này?

**Toàn bộ path VLE/VSE chưa có test nào.** Đây là chức năng QUAN TRỌNG NHẤT vì:
- Mọi benchmark thực tế đều đọc dữ liệu từ memory vào VRF
- Mọi benchmark đều phải ghi kết quả ra memory
- Không có test VLE/VSE → không biết VLSU có đúng không

### Cách test hoạt động

```
Scalar SW → DMEM[0..3]  = [10, 20, 30, 40]
VLE32.V  → v1           = [10, 20, 30, 40]   ← đọc từ DMEM
VADD.VX  → v2 = v1+1    = [11, 21, 31, 41]
VSE32.V  → DMEM[0x100..0x10F] = [11, 21, 31, 41]  ← ghi xuống
Scalar LW → kiểm tra từng word
```

Nếu `s0=0` sau khi chạy → PASS. Nếu `s0 = 0x10/0x14/0x18/0x1C` → FAIL tại element 0/1/2/3.

---

## TEST MỚI #2 — `sw/test_loop.S`: Kiểm tra multi-iteration loop

### Tại sao phải có test này?

Với VLEN=128 và SEW=32: `vlmax = 128/32 = 4 phần tử`. Mọi mảng > 4 phần tử đòi hỏi **nhiều vòng lặp**. Đây là trường hợp phổ biến nhất trong benchmark thực tế.

Hiện tại `test_alu.S` chỉ dùng `avl=4` (đúng bằng vlmax), không bao giờ test trường hợp loop.

### Cách test hoạt động

```
Mảng nguồn: src[12] = [1, 2, 3, ..., 12]
Phép toán:  vmul.vx x3 (nhân 3)
Kết quả:    dst[12] = [3, 6, 9, ..., 36]

Vòng lặp (3 lần, mỗi lần xử lý 4 phần tử):
  vsetvli x0, a4, e32, m1, ...   # vl = min(a4, 4)
  csrr t0, vl                     # đọc vl từ CSR (tránh phụ thuộc rd_wren path)
  vle32.v v1, (a5)
  vmul.vx v2, v1, a7
  vse32.v v2, (a6)
  advance pointers, a4 -= vl
```

`csrr vl` được dùng để đọc vl thực tế — tránh phụ thuộc vào giá trị rd của vsetvli (avl_remain vs vl).

---

## TEST MỚI #3 — `sw/test_reduction.S`: Kiểm tra vredsum/vredmax/vredmin

### Tại sao phải có test này?

FSM có `ST_REDUCTION` và `ST_REDUCTION_DONE`, module `vproc_reduction.sv` tồn tại, nhưng chưa có test nào verify path này. Reduction là operation quan trọng cho các benchmark tính tổng, cực trị.

### Cách test hoạt động

```
v1 = [5, 12, 3, 8]   (load từ DMEM)

Test 1: vredsum.vs v3, v1, v2  (v2[0]=0)  → v3[0] = 0+5+12+3+8 = 28
Test 2: vredmax.vs v4, v1, v2  (v2[0]=0)  → v4[0] = max(0,5,12,3,8) = 12
Test 3: vredmin.vs v5, v1, v2  (v2[0]=100)→ v5[0] = min(100,5,12,3,8) = 3

Kiểm tra: VSE32.V + scalar LW để đọc v_result[0] và so sánh
```

`s0=0` → PASS, `s0=1/2/3` → FAIL tại test 1/2/3.

---

## Tóm tắt tất cả thay đổi (lần 1 — 2026-04-27)

| # | File | Loại | Mô tả |
|---|------|-------|-------|
| B1 | [rtl/riscv/control_unit.sv](rtl/riscv/control_unit.sv) | Bug fix | Thêm `begin`/`end` cho if trong OP_V case — ngăn `rd_wren=1` với mọi lệnh vector |
| B2 | [rtl/vproc_cycle_counter.sv](rtl/vproc_cycle_counter.sv) | Bug fix | `done = ... && running_r` — ngăn spurious done khi hệ thống idle |
| B3 | [rtl/vproc_system_wrapper.sv](rtl/vproc_system_wrapper.sv) | Bug fix | `is_compare_r = funct6[5:3]==011` — cover đủ 8 lệnh compare thay vì chỉ 3 |
| T1 | [sw/test_vlsu.S](sw/test_vlsu.S) | New test | VLE32.V + VSE32.V với kiểm tra scalar |
| T2 | [sw/test_loop.S](sw/test_loop.S) | New test | Multi-iteration loop, 12 phần tử, 3 lần vòng lặp |
| T3 | [sw/test_reduction.S](sw/test_reduction.S) | New test | vredsum, vredmax, vredmin trên array 4 phần tử |

---

## VLSU Compliance Fixes (lần 2 — 2026-04-27)

Sau khi kiểm tra theo RISC-V V Extension spec, phát hiện 3 lỗi vi phạm spec trong VLSU:

---

### VLSU BUG #1 — `vproc_vec_lsu.sv`: Tail bytes bị ghi vào DMEM (VSE8/VSE16)

**File:** [rtl/vproc_vec_lsu.sv](rtl/vproc_vec_lsu.sv)

**Vấn đề:**
`mem_be = 4'b1111` cứng — tất cả store đều ghi full word. Với VSE8 VL=5:
- Cần 2 words: word 0 (4 bytes = 4 elements), word 1 (chỉ 1 byte = element 4)
- Nhưng word 1 được ghi toàn bộ 4 bytes → ghi 3 bytes rác vào vùng nhớ sau element 4

**Hậu quả:** Vi phạm spec "tail elements are not written to memory".

**Fix:**
```systemverilog
// Tính last_word_be_comb khi issue (vls_sew và vls_vl[1:0]):
// e8 vl%4: 1→0001, 2→0011, 3→0111, 0→1111
// e16 vl%2: 1→0011, 0→1111
// e32: luôn 1111

// Áp dụng vào mem_be:
assign mem_be = (state_r == ST_STORE)
                ? ((last_word ? last_word_be_r : 4'b1111) & mask_be)
                : 4'b1111;
```

---

### VLSU BUG #2 — `vproc_vec_lsu.sv`: Masked store không được support (vm=0)

**File:** [rtl/vproc_vec_lsu.sv](rtl/vproc_vec_lsu.sv)

**Vấn đề:**
VLSU không có port `vm` — mọi VSE đều ghi tất cả elements bất kể mask. Theo spec:
> "For store instructions, if an element is not active (mask bit 0), it is not written to memory."

Đây là hard requirement, không phải optional.

**Fix — Thêm 2 port mới:**
```systemverilog
input logic         vm_i,       // 1=unmasked, 0=masked
input logic [127:0] v0_flat_i,  // v0 mask register
```

**Tính mask_be per word:**
```systemverilog
// e32: 1 elem/word → mask_be = v0[word_ctr] ? 1111 : 0000
// e16: 2 elems/word → lower 2B from v0[2k], upper 2B from v0[2k+1]
// e8:  4 elems/word → each byte from v0[4k+j]
```

---

### VLSU BUG #3 — `vproc_system_wrapper.sv`: is_vls_insn không lọc mop/lumop

**File:** [rtl/vproc_system_wrapper.sv](rtl/vproc_system_wrapper.sv)

**Vấn đề:**
```systemverilog
// CODE CŨ — chỉ check opcode
wire is_vls_insn = is_vls_load_raw || is_vls_store_raw;
```

Điều này kích hoạt VLSU cho CẢ các lệnh:
- Strided load (mop=10): VLE32.V stride
- Indexed load (mop=11): VLOXEI32.V
- Fault-only-first (lumop=10000): VLE32FF.V
- Whole-register (lumop=01000): VL1RE32.V

Những lệnh này chưa được implement và sẽ gây hành vi sai nếu VLSU nhận.

**Fix:**
```systemverilog
wire is_vls_unit_stride = (instruction[27:26] == 2'b00);    // mop=00
wire is_vls_regular     = (instruction[24:20] == 5'b00000); // lumop/sumop=00000
wire is_vls_insn = (is_vls_load_raw || is_vls_store_raw)
                   && is_vls_unit_stride && is_vls_regular;
```

---

### Testbench update — `bench/tb_vproc_vlsu.sv`

**Các thay đổi:**
1. **vm=1 trong tất cả build functions** — code cũ dùng vm=0 ngầm định, sẽ block store sau khi fix mask logic
2. **Thêm Test 2: e8 VL sweep 1–16** — verify partial last word byte enables
3. **Thêm Test 3: e16 VL sweep 1–8** — verify partial last halfword handling
4. **Thêm Test 4: e32 masked store** — verify vm=0 + v0 mask suppress inactive elements
5. **File report output** — `$fopen("vlsu_test_report.rpt")` ghi kết quả ra file

Verification helper `check_result()` kiểm tra byte-by-byte:
- Active elements: so sánh với src
- Tail bytes trong last word: phải giữ nguyên DEADBEEF
- Word sau last active word: phải giữ nguyên DEADBEEF (boundary check)

---

## Tóm tắt tất cả thay đổi (lần 2)

| # | File | Loại | Mô tả |
|---|------|-------|-------|
| B4 | [rtl/vproc_vec_lsu.sv](rtl/vproc_vec_lsu.sv) | Bug fix | Thêm `last_word_be_r` — không ghi tail bytes của last word (e8/e16) |
| B5 | [rtl/vproc_vec_lsu.sv](rtl/vproc_vec_lsu.sv) | Bug fix | Thêm `vm_i`/`v0_flat_i` ports + `mask_be` logic — support masked store (vm=0) |
| B6 | [rtl/vproc_system_wrapper.sv](rtl/vproc_system_wrapper.sv) | Bug fix | Lọc `is_vls_insn` theo mop=00 và lumop=00000 — chỉ kích hoạt unit-stride regular |
| B7 | [rtl/vproc_system_wrapper.sv](rtl/vproc_system_wrapper.sv) | Feature | Wire `instruction[25]` và `v0_mask_flat` vào VLSU instance |
| TB | [bench/tb_vproc_vlsu.sv](bench/tb_vproc_vlsu.sv) | Testbench | Rewrite: thêm e8/e16 tests, masked store test, file report output |

---

## Hướng dẫn chạy VLSU testbench

```bash
# Chạy VLSU testbench (từ project root)
vsim -do run_tb_vlsu.do
# → kết quả in ra console
# → file report: bench/vlsu_test_report.rpt
```

Sau khi chạy, kiểm tra `vlsu_test_report.rpt`:
- `RESULT: ALL PASS` → tất cả 75 test case pass (50 + 16 + 8 + 1)
- Nếu có FAIL: xem dòng chi tiết để biết word/byte nào sai

---

## Các việc cần làm tiếp theo

- [ ] Cập nhật `sw/Makefile` để có thể chọn test target (thêm `make TEST=test_vlsu`)
- [ ] Thêm test case cho `vmsne`, `vmsle`, `vmsgt` vào `tb_vproc_all_instr.sv`
- [ ] Xác nhận `vmv.v.x` được hỗ trợ trong decoder (dùng trong test_reduction.S)
- [ ] Implement strided load/store (mop=10) nếu cần cho benchmark
- [ ] Implement VLE8FF (fault-only-first) nếu cần cho production use
- [ ] Thay SRAM model combinational → synchronous khi tapeout
