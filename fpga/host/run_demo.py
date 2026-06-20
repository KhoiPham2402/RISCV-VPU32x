"""
run_demo.py — One-command demo: prepare image + send to board.

Usage:
    python run_demo.py --port COM5 --image lena.png
    python run_demo.py --port COM5 --image photo.jpg --baud 115200

Steps performed automatically:
  1. Resize image to 128x128, save R/G/B planes to ./demo_data/
  2. Open serial port and send all 3 planes (49152 bytes total)
  3. Wait for ACK 0xAA from firmware
  4. Print result — HDMI output active after ACK

After this script exits with [PASS], look at the HDMI monitor:
  - Center 384x384 region: grayscale version of your input image (3x zoom)
  - Surrounding area: black background
"""

import argparse
import sys
from prepare_image import prepare
from send_image import run as send_run


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--port",    required=True,  help="Serial port (e.g. COM5 or /dev/ttyUSB0)")
    p.add_argument("--image",   required=True,  help="Input image (any format, any size)")
    p.add_argument("--baud",    type=int, default=115200)
    p.add_argument("--timeout", type=int, default=120)
    args = p.parse_args()

    print("=" * 55)
    print(" RISC-V VPU Lena Demo")
    print("=" * 55)

    # Step 1 — prepare
    print(f"\n[1/2] Preparing image: {args.image}")
    try:
        prepare(args.image, out_dir="./demo_data")
    except FileNotFoundError:
        print(f"ERROR: Image not found: {args.image}")
        sys.exit(1)
    except Exception as e:
        print(f"ERROR preparing image: {e}")
        sys.exit(1)

    # Step 2 — send
    print(f"\n[2/2] Sending to board on {args.port} @ {args.baud} baud")
    send_run(port=args.port, baud=args.baud, data_dir="./demo_data",
             chunk=256, timeout=args.timeout)

    print("\n" + "=" * 55)
    print(" Done! Check HDMI monitor for grayscale output.")
    print("=" * 55)


if __name__ == "__main__":
    main()
