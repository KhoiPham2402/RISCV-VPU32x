#!/usr/bin/env python3
"""
vga_reconstruct.py — Reconstruct VGA output image from ModelSim capture log.

Usage:
    python sw/vga_reconstruct.py fpga/sim/vga_capture.txt

Outputs (in same directory as input file):
    vga_frame_full.png   — full 640×480 VGA frame (black borders + scaled image)
    vga_image_384.png    — 384×384 cropped image region (as seen on monitor)
    vga_image_128.png    — 128×128 original resolution (every 3rd pixel sampled)

The VGA output maps the 128×128 Y-channel image to a 384×384 region
centred on the 640×480 frame (3× pixel scaling):
    Left edge  : hc = 128
    Top edge   : vc = 48
    Right edge : hc = 511
    Bottom edge: vc = 431
"""

import sys
import os
from pathlib import Path

FRAME_W  = 640
FRAME_H  = 480
IMG_LEFT = 128
IMG_TOP  = 48
IMG_SIZE = 384   # 128 × 3

def load_pixels(filepath):
    pixels = []
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != 3:
                continue
            r, g, b = int(parts[0]), int(parts[1]), int(parts[2])
            pixels.append((r, g, b))
    return pixels


def save_png(pixels, width, height, path):
    """Write a minimal PNG without external dependencies."""
    import struct, zlib

    def png_chunk(tag, data):
        chunk = tag + data
        return struct.pack('>I', len(data)) + chunk + struct.pack('>I', zlib.crc32(chunk) & 0xFFFFFFFF)

    raw_rows = []
    for row in range(height):
        row_bytes = b'\x00'  # filter type: None
        for col in range(width):
            idx = row * width + col
            if idx < len(pixels):
                r, g, b = pixels[idx]
            else:
                r, g, b = 0, 0, 0
            row_bytes += bytes([r, g, b])
        raw_rows.append(row_bytes)

    idat_data = zlib.compress(b''.join(raw_rows))

    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(png_chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)))
        f.write(png_chunk(b'IDAT', idat_data))
        f.write(png_chunk(b'IEND', b''))


def main():
    if len(sys.argv) < 2:
        print("Usage: python vga_reconstruct.py <vga_capture.txt>")
        sys.exit(1)

    capfile = sys.argv[1]
    outdir  = Path(capfile).parent

    print(f"Reading {capfile} ...")
    pixels = load_pixels(capfile)

    total = FRAME_W * FRAME_H
    if len(pixels) != total:
        print(f"WARNING: expected {total} pixels, got {len(pixels)}")
        # Pad with black if short
        pixels += [(0, 0, 0)] * max(0, total - len(pixels))

    # ── 1. Full 640×480 frame ────────────────────────────────────────────────
    out_full = str(outdir / "vga_frame_full.png")
    save_png(pixels, FRAME_W, FRAME_H, out_full)
    print(f"Saved: {out_full}  ({FRAME_W}×{FRAME_H} full frame)")

    # ── 2. 384×384 cropped image region ──────────────────────────────────────
    img_384 = []
    for row in range(IMG_SIZE):
        for col in range(IMG_SIZE):
            vga_row = IMG_TOP + row
            vga_col = IMG_LEFT + col
            if vga_row < FRAME_H and vga_col < FRAME_W:
                img_384.append(pixels[vga_row * FRAME_W + vga_col])
            else:
                img_384.append((0, 0, 0))

    out_384 = str(outdir / "vga_image_384.png")
    save_png(img_384, IMG_SIZE, IMG_SIZE, out_384)
    print(f"Saved: {out_384}  ({IMG_SIZE}×{IMG_SIZE} image region)")

    # ── 3. 128×128 original resolution (sample center of each 3×3 block) ────
    img_128 = []
    for row in range(128):
        for col in range(128):
            # Center pixel of each 3×3 scaled block
            vga_row = IMG_TOP + row * 3 + 1
            vga_col = IMG_LEFT + col * 3 + 1
            if vga_row < FRAME_H and vga_col < FRAME_W:
                img_128.append(pixels[vga_row * FRAME_W + vga_col])
            else:
                img_128.append((0, 0, 0))

    out_128 = str(outdir / "vga_image_128.png")
    save_png(img_128, 128, 128, out_128)
    print(f"Saved: {out_128}  (128×128 original resolution)")

    # ── Verification: print first row Y values ────────────────────────────────
    print("\nVerification — Y values at image top row (cols 0..15):")
    print("  col:  ", end="")
    for col in range(16):
        print(f"{col:3d}", end="")
    print()
    print("  R:    ", end="")
    for col in range(16):
        vga_row = IMG_TOP + 0 * 3 + 1
        vga_col = IMG_LEFT + col * 3 + 1
        r, g, b = pixels[vga_row * FRAME_W + vga_col]
        print(f"{r:3d}", end="")
    print()

    # Check test pattern zone 1 (rows 0-31: H-bars → row/8 alternates 0/255)
    print("\nZone check (row 0 = H-bar, expect 0x00):")
    vga_row = IMG_TOP + 0 * 3 + 1
    vga_col = IMG_LEFT + 0 * 3 + 1
    r, g, b = pixels[vga_row * FRAME_W + vga_col]
    status = "OK" if r == 0 else f"FAIL (got {r})"
    print(f"  Y[0][0] = {r} ({status})")

    print("\nZone check (row 8 = H-bar row, expect 0xFF):")
    vga_row = IMG_TOP + 8 * 3 + 1
    vga_col = IMG_LEFT + 0 * 3 + 1
    r, g, b = pixels[vga_row * FRAME_W + vga_col]
    status = "OK" if r == 255 else f"FAIL (got {r})"
    print(f"  Y[8][0] = {r} ({status})")

    print("\nZone check (row 96, cols 0-7: ramp col*2):")
    for col in range(8):
        vga_row = IMG_TOP + 96 * 3 + 1
        vga_col = IMG_LEFT + col * 3 + 1
        r, g, b = pixels[vga_row * FRAME_W + vga_col]
        expected = col * 2
        status = "OK" if r == expected else f"FAIL (expected {expected})"
        print(f"  Y[96][{col}] = {r} ({status})")


if __name__ == "__main__":
    main()
