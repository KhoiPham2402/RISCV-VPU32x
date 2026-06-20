"""
send_image.py — Send R/G/B planes to DE10-Standard RISC-V VPU over UART.

Protocol:
  1. Send lena_R.bin  (16384 bytes, Red   channel)
  2. Send lena_G.bin  (16384 bytes, Green channel)
  3. Send lena_B.bin  (16384 bytes, Blue  channel)
  4. Wait for ACK byte 0xAA from firmware
  After ACK, HDMI output displays the grayscale result automatically.

Usage:
    python send_image.py --port COM5
    python send_image.py --port COM5 --baud 115200 --dir ./data
    python send_image.py --port /dev/ttyUSB0

Options:
    --port  PORT   Serial port (required). Windows: COM3, COM5…  Linux: /dev/ttyUSB0
    --baud  BAUD   Baud rate (default: 115200)
    --dir   DIR    Directory containing lena_R/G/B.bin (default: current dir)
    --chunk SIZE   Send chunk size in bytes (default: 256)
    --timeout SEC  ACK wait timeout in seconds (default: 120)
"""

import argparse
import sys
import time
from pathlib import Path

try:
    import serial
except ImportError:
    print("ERROR: pyserial not installed. Run: pip install pyserial")
    sys.exit(1)


CHANNELS = [("R", "lena_R.bin"), ("G", "lena_G.bin"), ("B", "lena_B.bin")]
EXPECTED_ACK = 0xAA
BYTES_PER_CHANNEL = 16384


def send_file(ser: serial.Serial, path: Path, label: str, chunk: int) -> None:
    data = path.read_bytes()
    if len(data) != BYTES_PER_CHANNEL:
        raise ValueError(f"{path.name}: expected {BYTES_PER_CHANNEL} bytes, got {len(data)}")

    sent = 0
    t0 = time.time()
    while sent < len(data):
        n = ser.write(data[sent : sent + chunk])
        sent += n
        elapsed = time.time() - t0
        pct = sent / len(data) * 100
        rate = sent / elapsed if elapsed > 0 else 0
        print(f"\r  {label}: {sent:5d}/{len(data)}  ({pct:5.1f}%)  {rate/1024:.1f} KB/s  ", end="", flush=True)

    print(f"\r  {label}: {sent}/{len(data)}  (100.0%)  [{time.time()-t0:.1f}s]          ")


def run(port: str, baud: int, data_dir: str, chunk: int, timeout: int) -> None:
    data_dir = Path(data_dir)

    # Verify files exist before opening serial port
    for label, fname in CHANNELS:
        p = data_dir / fname
        if not p.exists():
            print(f"ERROR: {p} not found. Run prepare_image.py first.")
            sys.exit(1)

    print(f"Opening {port} @ {baud} baud …")
    try:
        ser = serial.Serial(port, baud, timeout=timeout)
    except serial.SerialException as e:
        print(f"ERROR: Cannot open {port}: {e}")
        sys.exit(1)

    time.sleep(0.3)   # let board finish reset / UART settle
    ser.reset_input_buffer()

    print("Sending image planes:")
    for label, fname in CHANNELS:
        send_file(ser, data_dir / fname, label, chunk)

    print("Waiting for ACK 0xAA …", end="", flush=True)
    deadline = time.time() + timeout
    ack = b""
    while time.time() < deadline:
        b = ser.read(1)
        if b:
            ack = b
            break

    ser.close()
    print()

    if ack == bytes([EXPECTED_ACK]):
        print(f"[PASS] ACK received: 0x{ack[0]:02X}")
        print("       HDMI output should now show grayscale image.")
    elif ack:
        print(f"[FAIL] Unexpected byte: 0x{ack[0]:02X}  (expected 0xAA)")
        sys.exit(1)
    else:
        print("[FAIL] Timeout — no ACK received within", timeout, "seconds")
        print("       Check: board is programmed, correct COM port, reset board and retry")
        sys.exit(1)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--port",    required=True,  help="Serial port (e.g. COM5 or /dev/ttyUSB0)")
    p.add_argument("--baud",    type=int, default=115200, help="Baud rate (default: 115200)")
    p.add_argument("--dir",     default=".",    help="Directory with lena_R/G/B.bin")
    p.add_argument("--chunk",   type=int, default=256,   help="Write chunk size in bytes")
    p.add_argument("--timeout", type=int, default=120,   help="ACK timeout in seconds")
    args = p.parse_args()
    run(args.port, args.baud, args.dir, args.chunk, args.timeout)


if __name__ == "__main__":
    main()
