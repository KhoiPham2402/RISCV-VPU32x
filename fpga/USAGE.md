# FPGA Demo — Lena Grayscale via UART + HDMI

Chạy demo xử lý ảnh Lena 128×128 trên DE10-Standard:
- Host gửi ảnh RGB qua UART
- RISC-V+VPU tính grayscale BT.601 trên FPGA
- Kết quả hiển thị lên màn hình qua HDMI (640×480, 3× zoom)

---

## Yêu cầu

| Thành phần | Phiên bản tối thiểu |
|---|---|
| DE10-Standard (Cyclone V SX) | — |
| Quartus Prime 18.1 Standard Edition | — |
| Python 3.8+ | — |
| Thư viện Python: `pyserial`, `Pillow` | `pip install pyserial Pillow` |
| Màn hình HDMI | — |

---

## Bước 1 — Chuẩn bị ảnh đầu vào

Ảnh phải là JPEG/PNG grayscale (hoặc màu, sẽ được đổi sang RGB planar), kích thước 128×128.

Tạo file `prepare_lena.py` để sinh 3 file channel:

```python
# prepare_lena.py
from PIL import Image
import sys

img_path = sys.argv[1] if len(sys.argv) > 1 else "lena.png"
img = Image.open(img_path).resize((128, 128)).convert("RGB")
r, g, b = img.split()

r.tobytes() ; open("lena_R.bin","wb").write(r.tobytes())
g.tobytes() ; open("lena_G.bin","wb").write(g.tobytes())
b.tobytes() ; open("lena_B.bin","wb").write(b.tobytes())
print(f"Saved lena_R.bin, lena_G.bin, lena_B.bin (16384 bytes each)")
```

Chạy:
```
python prepare_lena.py lena.png
```

---

## Bước 2 — Nạp bitstream lên board

1. Mở **Quartus 18.1**, menu **Tools → Programmer**
2. Chọn **USB-Blaster** ở mục Hardware Setup
3. Thêm file `output_files/riscv_vpu.sof`
4. Tick **Program/Configure**, nhấn **Start**

Board sẽ khởi động ngay sau khi nạp xong. HDMI sẽ hiển thị màn hình đen (chờ dữ liệu).

---

## Bước 3 — Xác định cổng COM

**Windows:**
- Mở Device Manager → Ports (COM & LPT)
- Tìm cổng của `USB-Serial` hoặc `CP210x` (tùy USB-UART trên board)
- Ghi nhớ số cổng, ví dụ `COM5`

**Linux/macOS:**
```bash
ls /dev/ttyUSB*   # hoặc /dev/ttyACM*
```

---

## Bước 4 — Gửi ảnh qua UART

Tạo file `send_lena.py`:

```python
# send_lena.py
import serial, sys, time

PORT  = sys.argv[1] if len(sys.argv) > 1 else "COM5"
BAUD  = 115200

ser = serial.Serial(PORT, BAUD, timeout=30)
time.sleep(0.5)  # đợi board ổn định sau reset

def send_file(path, label):
    data = open(path, "rb").read()
    assert len(data) == 16384, f"{path} must be 16384 bytes"
    print(f"Sending {label} ({len(data)} bytes)...", end="", flush=True)
    ser.write(data)
    print(" done")

send_file("lena_R.bin", "R channel")
send_file("lena_G.bin", "G channel")
send_file("lena_B.bin", "B channel")

print("Waiting for ACK...", end="", flush=True)
ack = ser.read(1)
if ack == b'\xAA':
    print(" [PASS] ACK=0xAA — VPU processing complete")
else:
    print(f" [FAIL] Expected 0xAA, got {ack.hex()}")

ser.close()
```

Chạy:
```
python send_lena.py COM5
```

Ví dụ output thành công:
```
Sending R channel (16384 bytes)... done
Sending G channel (16384 bytes)... done
Sending B channel (16384 bytes)... done
Waiting for ACK... [PASS] ACK=0xAA — VPU processing complete
```

---

## Bước 5 — Kết quả HDMI

Sau khi nhận ACK, HDMI controller tự động đọc buffer grayscale từ DMEM và hiển thị:

| Vùng màn hình | Nội dung |
|---|---|
| Trung tâm 384×384 px | Ảnh Lena grayscale (3× zoom) |
| Viền ngoài | Đen (0x000000) |

Độ phân giải output: **640×480 @ 60 Hz**, pixel clock 25 MHz.

---

## Thông số kỹ thuật

| Tham số | Giá trị |
|---|---|
| Ảnh đầu vào | 128×128 RGB planar |
| Công thức grayscale | `Y = R×77 + G×150 + B×29` (>> 8 bits, BT.601) |
| Tốc độ UART | 115200 baud, 8N1 |
| Tổng dữ liệu gửi | 3 × 16384 = 49152 bytes |
| Thời gian xử lý VPU | 1024 vòng lặp × 16 elements |
| ACK byte | `0xAA` |
| HDMI timing | 640×480 @ 60 Hz (VGA standard) |

---

## Xử lý sự cố

**Board không nhận dữ liệu:**
- Kiểm tra đúng cổng COM và baud rate 115200
- Thử nhấn nút **KEY0** (reset) trên board rồi gửi lại

**HDMI không có tín hiệu:**
- Cắm lại cáp HDMI sau khi board đã khởi động xong
- Đảm bảo màn hình hỗ trợ 640×480 @ 60 Hz

**Timeout / không nhận ACK:**
- Kiểm tra UART TX/RX không bị hoán đổi
- Dùng terminal (e.g. PuTTY) để kiểm tra board có echo dữ liệu không

**Màn hình trắng thay vì grayscale:**
- Bitstream chưa được nạp đúng file `.sof`
- Thử Programmer → **Erase** rồi nạp lại
