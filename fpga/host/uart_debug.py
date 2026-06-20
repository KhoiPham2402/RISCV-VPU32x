"""
uart_debug.py — Step-by-step UART debug for DE10-Standard VPU demo.

Diagnoses exactly where the failure is:
  Stage 1: Host TX works (can we open port and send?)
  Stage 2: Board RX works (does firmware receive first byte?)
  Stage 3: VPU runs (do LEDs show activity?)
  Stage 4: Board TX works (does ACK come back?)

Usage:
    python uart_debug.py --port COM6

Steps:
  1. Power-cycle the board (or press+release KEY[0])
  2. IMMEDIATELY run this script
"""

import argparse
import sys
import time
import serial

BAUD       = 115200
ACK        = 0xAA
CHUNK_SIZE = 64     # small chunk — sends slowly so we can observe

def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--port", required=True, help="COM port (e.g. COM6)")
    p.add_argument("--baud", type=int, default=BAUD)
    args = p.parse_args()

    # ── Open port ─────────────────────────────────────────────────────────────
    print(f"\n[Stage 1] Opening {args.port} @ {args.baud} baud...")
    try:
        ser = serial.Serial(args.port, args.baud,
                            bytesize=8, parity='N', stopbits=1,
                            rtscts=False, dsrdtr=False,  # NO flow control
                            timeout=2)
    except serial.SerialException as e:
        print(f"  FAIL: {e}")
        print("  → Check if port is correct and not used by another program")
        sys.exit(1)

    print(f"  OK — port opened")
    time.sleep(0.5)      # give board extra time to settle after reset
    ser.reset_input_buffer()
    ser.reset_output_buffer()

    # ── Send 1 test byte and listen for anything ───────────────────────────────
    print("\n[Stage 2] Sending 1 byte (0x00), listening for any echo (1s)...")
    ser.write(bytes([0x00]))
    time.sleep(1.0)
    n = ser.in_waiting
    if n > 0:
        resp = ser.read(n)
        print(f"  Board sent back {n} bytes: {resp.hex()}")
        print("  → Board TX is working!")
    else:
        print("  No response — Board TX silent (may be normal at this stage)")

    # ── Send small R-channel snippet ───────────────────────────────────────────
    print("\n[Stage 3] Sending 64 bytes of R channel (value=200)...")
    ser.write(bytes([200] * 64))
    time.sleep(0.5)
    n = ser.in_waiting
    if n > 0:
        resp = ser.read(n)
        print(f"  Unexpected response during R-send: {resp.hex()}")
    else:
        print(f"  No premature response (expected)")

    # ── Send full R channel ────────────────────────────────────────────────────
    print("\n[Stage 4] Sending full R channel (16384 × 200)...")
    r_data = bytes([200] * 16384)
    t0 = time.time()
    ser.write(r_data)
    print(f"  Sent R in {time.time()-t0:.2f}s")

    print("\n[Stage 5] Sending full G channel (16384 × 100)...")
    g_data = bytes([100] * 16384)
    t0 = time.time()
    ser.write(g_data)
    print(f"  Sent G in {time.time()-t0:.2f}s")

    print("\n[Stage 6] Sending full B channel (16384 × 50)...")
    b_data = bytes([50] * 16384)
    t0 = time.time()
    ser.write(b_data)
    print(f"  Sent B in {time.time()-t0:.2f}s")

    # ── Wait for ACK ───────────────────────────────────────────────────────────
    print("\n[Stage 7] Waiting for ACK 0xAA (up to 30s)...")
    print("          >>> Watch the LEDs on the board now! <<<")
    print("          LEDR[9] should blink when VPU is running")

    deadline = time.time() + 30
    received = b""
    while time.time() < deadline:
        remaining = deadline - time.time()
        n = ser.in_waiting
        if n > 0:
            received += ser.read(n)
            print(f"\n  Board sent: {received.hex()}")
            if received[-1:] == bytes([ACK]):
                print("\n[PASS] ACK = 0xAA received!")
                print("       VPU + UART both working. Check HDMI for grayscale image.")
                ser.close()
                return
            else:
                print(f"[WARN] Unexpected data (not 0xAA). Continuing to wait...")
        time.sleep(0.1)

    # ── Timeout diagnosis ──────────────────────────────────────────────────────
    ser.close()
    print(f"\n[FAIL] No ACK after 30s. Diagnosis:")
    print()
    if not received:
        print("  Board sent NOTHING back.")
        print("  Possible causes (check in order):")
        print("  1. Board not reset before script run → reset KEY[0] and retry")
        print("  2. UART RX line not connected (check JP1 pin 3 wiring)")
        print("  3. New bitstream not programmed (re-run Quartus programmer)")
        print("  4. Baud rate mismatch (terminal check: 115200 8N1 no flow control)")
    else:
        print(f"  Board sent: {received.hex()}")
        print("  Board TX works but data is wrong.")
        print("  Possible causes:")
        print("  1. VPU hung → check LEDR during VPU phase")
        print("  2. Firmware bug → try simulation first")

if __name__ == "__main__":
    main()
