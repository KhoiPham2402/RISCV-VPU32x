# Hướng dẫn chạy Testbench trên ModelSim

## Tổng quan
Testbench `tb_vproc_lane.sv` sử dụng golden model để kiểm tra tính logic của module `vproc_processor_lane`.

### File chính:
- `tb_vproc_lane.sv` - Testbench chính với golden model
- `run_tb_lane.do` - Script ModelSim để compile và chạy

## Yêu cầu
- ModelSim (hoặc Questa Sim)
- Verilog compiler hỗ trợ SystemVerilog

## Cách chạy

### Phương pháp 1: Chạy trực tiếp từ ModelSim GUI

1. **Mở ModelSim**
   - Khởi động ứng dụng ModelSim

2. **Chọn thư mục làm việc**
   ```
   File → Change Directory...
   Điều hướng đến: c:\CapstoneProject2\riscv_vpu\bench
   ```

3. **Chạy script**
   ```
   Transcript → Execute Macro → Chọn "run_tb_lane.do"
   ```
   Hoặc bấm Ctrl+O và mở file `run_tb_lane.do`

4. **Xem kết quả**
   - Output sẽ hiển thị trực tiếp trong Transcript window
   - Mỗi test sẽ có status [PASS] hoặc [FAIL]
   - Cuối cùng là TEST SUMMARY với số lượng passed/failed

---

### Phương pháp 2: Chạy từ Command Line (Windows PowerShell)

```powershell
# Trong PowerShell, điều hướng đến thư mục bench:
cd c:\CapstoneProject2\riscv_vpu\bench

# Chạy ModelSim với script
vsim -do run_tb_lane.do -batch
```

Nếu VSim không được nhận diện, hãy thêm đường dẫn ModelSim vào PATH hoặc sử dụng đường dẫn đầy đủ:
```powershell
& "C:\ModelSim\<version>\bin\vsim.exe" -do run_tb_lane.do -batch
```

---

### Phương pháp 3: Chạy từ Terminal ModelSim

1. Mở ModelSim
2. Trong Transcript, gõ lệnh:
```tcl
cd c:/CapstoneProject2/riscv_vpu/bench
do run_tb_lane.do
```

---

## Giải thích Output

### Ví dụ Output:
```
==========================================
  VPROC_PROCESSOR_LANE COMPREHENSIVE TEST
==========================================

--- Testing VADD ---
[PASS] Test   1: VADD_32b SEW=0
[PASS] Test   2: VADD_16b SEW=1
[PASS] Test   3: VADD_8b SEW=2
...
--- Testing VCMPEQ (Equal) ---
[PASS] Test  34: VCMPEQ_32b_eq SEW=0
...
--- Testing VCMPLT (Less Than) ---
[PASS] Test  37: VCMPEQ_32b_lt SEW=0
...
--- Testing VCMPGT (Greater Than) ---
[PASS] Test  40: VCMPEQ_32b_gt SEW=0
...

==========================================
              TEST SUMMARY
==========================================
Total Tests:   75
Passed:        75
Failed:         0
Result:        *** ALL TESTS PASSED ***
==========================================
```

### Giải thích:
- **[PASS]**: Test thành công - kết quả DUT khớp với golden model
- **[FAIL]**: Test thất bại - hiển thị chi tiết:
  - Input operands (vs1, vs2, rs1)
  - Kết quả thực tế từ DUT
  - Kết quả kỳ vọng từ golden model

---

## Chi tiết Testbench

### Các operation được test:
1. **Arithmetic**: VADD, VSUB (3 element widths: 32b, 16b, 8b)
2. **Multiply**: VMUL, VMULH, VMULHU, VMULHSU
3. **Logic**: VAND, VOR, VXOR
4. **Shift**: VSLL, VSRL, VSRA (multiple widths)
5. **Compare**: VCMPEQ với 3 loại:
   - Equal (cmp_op=2'b00)
   - Less Than signed (cmp_op=2'b01)
   - Greater Than derived (cmp_op=2'b10)

### Golden Model:
- Tính toán đầu ra kỳ vọng dựa trên golden reference
- Hỗ trợ signed/unsigned operands
- Kiểm tra widening operations
- Kiểm tra multi-lane operations (SEW)

---

## Troubleshooting

### Lỗi: "Cannot find vproc_*.sv"
**Giải pháp**: Đảm bảo đường dẫn đúng. Script hiện tại sử dụng:
```tcl
vlog -sv ../rtl/vproc_adder.sv
```
Nếu cần sửa đường dẫn, hãy chỉnh sửa file `run_tb_lane.do`

### Lỗi: Trace/WLF file lớn
Nếu simulation tạo file lớn:
```tcl
# Thêm dòng này vào trước vsim:
vsim -novopt -nolog work.tb_vproc_lane
```

### Muốn lưu VCD file
Thêm vào testbench:
```systemverilog
initial begin
    $dumpfile("tb_vproc_lane.vcd");
    $dumpvars(0, tb_vproc_lane);
    ...
end
```

---

## Customization

### Thay đổi số lượng test:
Sửa trong `tb_vproc_lane.sv`:
```systemverilog
localparam NUM_TESTS = 100;  // Thay đổi giá trị này
```

### Thêm specific test:
```systemverilog
// Thêm vào main initial block:
funct6 = VADD;
sew = 3'd0;
vs1_data = 32'h12345678;
vs2_data = 32'h87654321;
#10 golden_model();
#5 check_result("Custom VADD test");
```

---

## Notes
- Simulation chạy không có clock: tất cả logic là combinational
- Time unit: 1ns, precision: 1ps
- Testbench tự động kết thúc sau khi hoàn tất tất cả test

Para sa mga tanong o pagsusuri karagdagang, huwag mag-atubili na kontakin kami!
