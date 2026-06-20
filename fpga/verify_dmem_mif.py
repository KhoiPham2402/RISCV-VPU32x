#!/usr/bin/env python3
"""
verify_dmem_mif.py — Verify dmem_b*.mif contains correct RGB + grayscale data.

Reads the 4 byte-lane MIF files from the Quartus project dir, reconstructs
the 128×128 RGB and grayscale images, then compares byte-exact against the
reference hex files and saves PNGs for visual inspection.

Usage (from repo root):
    python fpga/verify_dmem_mif.py
"""

import os, sys, re

SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
QUARTUS_DIR = r"C:\CapstoneProject2\FPGA\riscv_vpu"
LENA_DIR    = os.path.join(REPO_ROOT, "sw", "benchmarks", "lena_gray")

DMEM_HEX_RGB = os.path.join(LENA_DIR, "lena_dmem_init.hex")   # R/G/B source
Y_HEX        = os.path.join(LENA_DIR, "lena_y_reference.hex") # Y reference
OUT_DIR      = os.path.join(SCRIPT_DIR, "verify_out")

IMG_SIZE   = 128
N_PIXELS   = IMG_SIZE * IMG_SIZE   # 16384
DEPTH      = 16384
R_BASE     = 0
G_BASE     = 4096
B_BASE     = 8192
Y_BASE     = 12288


# ── Read MIF files → 16384 × 32-bit words ────────────────────────────────────

def read_mif_lane(path):
    """Parse a WIDTH=8 MIF and return a list of DEPTH byte values."""
    data = [0] * DEPTH
    with open(path) as f:
        content = f.read()

    # Handle range assignments: [XXXX..YYYY] : VV;
    for m in re.finditer(r'\[([0-9A-Fa-f]+)\.\.([0-9A-Fa-f]+)\]\s*:\s*([0-9A-Fa-f]+)\s*;', content):
        lo, hi, val = int(m.group(1), 16), int(m.group(2), 16), int(m.group(3), 16)
        for i in range(lo, hi + 1):
            if i < DEPTH:
                data[i] = val

    # Handle individual entries: XXXX : VV;
    for m in re.finditer(r'^\s*([0-9A-Fa-f]{1,4})\s*:\s*([0-9A-Fa-f]{1,2})\s*;', content, re.MULTILINE):
        addr, val = int(m.group(1), 16), int(m.group(2), 16)
        if addr < DEPTH:
            data[addr] = val

    return data


def reconstruct_words():
    lanes = []
    for i in range(4):
        path = os.path.join(QUARTUS_DIR, f"dmem_b{i}.mif")
        if not os.path.exists(path):
            print(f"ERROR: {path} not found")
            sys.exit(1)
        lanes.append(read_mif_lane(path))
        print(f"  Read {path}  ({DEPTH} entries)")

    words = [lanes[0][w] | (lanes[1][w] << 8) | (lanes[2][w] << 16) | (lanes[3][w] << 24)
             for w in range(DEPTH)]
    return words


# ── Unpack one channel from word array ────────────────────────────────────────

def unpack_channel(words, base):
    """Extract 16384 pixel bytes from words[base..base+4095]."""
    pixels = []
    for w in words[base:base + N_PIXELS // 4]:
        pixels.append(w & 0xFF)
        pixels.append((w >> 8) & 0xFF)
        pixels.append((w >> 16) & 0xFF)
        pixels.append((w >> 24) & 0xFF)
    return pixels


# ── Load reference hex ────────────────────────────────────────────────────────

def load_ref_hex_channel(path, offset_words, n_words):
    """Read n_words 32-bit words from hex file at word offset, return pixel bytes."""
    with open(path) as f:
        all_words = [int(l.strip(), 16) for l in f if l.strip()]
    pixels = []
    for w in all_words[offset_words:offset_words + n_words]:
        pixels.append(w & 0xFF)
        pixels.append((w >> 8) & 0xFF)
        pixels.append((w >> 16) & 0xFF)
        pixels.append((w >> 24) & 0xFF)
    return pixels


# ── Compare and report ────────────────────────────────────────────────────────

def compare(name, got, ref):
    errors = [(i, got[i], ref[i]) for i in range(len(ref)) if got[i] != ref[i]]
    if not errors:
        print(f"  {name}: PASS — {len(ref)} pixels match exactly")
    else:
        print(f"  {name}: FAIL — {len(errors)} mismatches (first 5 shown):")
        for idx, g, r in errors[:5]:
            row, col = divmod(idx, IMG_SIZE)
            print(f"    pixel[{row}][{col}] got=0x{g:02X} ref=0x{r:02X}")
    return len(errors)


# ── Save PNG ──────────────────────────────────────────────────────────────────

def save_rgb_png(r, g, b, path):
    try:
        from PIL import Image
        img = Image.new("RGB", (IMG_SIZE, IMG_SIZE))
        img.putdata(list(zip(r, g, b)))
        img.save(path)
        print(f"  Saved {path}")
    except ImportError:
        print("  (Pillow not installed — skipping PNG output)")


def save_gray_png(y, path):
    try:
        from PIL import Image
        img = Image.new("L", (IMG_SIZE, IMG_SIZE))
        img.putdata(y)
        img.save(path)
        print(f"  Saved {path}")
    except ImportError:
        print("  (Pillow not installed — skipping PNG output)")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    print("=== Reading DMEM MIF files ===")
    words = reconstruct_words()

    print("\n=== Extracting channels ===")
    r_got = unpack_channel(words, R_BASE)
    g_got = unpack_channel(words, G_BASE)
    b_got = unpack_channel(words, B_BASE)
    y_got = unpack_channel(words, Y_BASE)
    print(f"  R[0..3] = {r_got[:4]}  G[0..3] = {g_got[:4]}  B[0..3] = {b_got[:4]}")
    print(f"  Y[0..3] = {y_got[:4]}")

    print("\n=== Comparing against reference ===")
    total_errors = 0

    # RGB: compare against lena_dmem_init.hex (words 0..12287 = R/G/B)
    r_ref = load_ref_hex_channel(DMEM_HEX_RGB, 0,    4096)
    g_ref = load_ref_hex_channel(DMEM_HEX_RGB, 4096, 4096)
    b_ref = load_ref_hex_channel(DMEM_HEX_RGB, 8192, 4096)
    total_errors += compare("R channel", r_got, r_ref)
    total_errors += compare("G channel", g_got, g_ref)
    total_errors += compare("B channel", b_got, b_ref)

    # Y: compare against lena_y_reference.hex (4096 words)
    y_ref = load_ref_hex_channel(Y_HEX, 0, 4096)
    total_errors += compare("Y channel", y_got, y_ref)

    print("\n=== Saving output PNGs ===")
    save_rgb_png(r_got, g_got, b_got, os.path.join(OUT_DIR, "mif_rgb.png"))
    save_gray_png(y_got,              os.path.join(OUT_DIR, "mif_gray.png"))

    # Also save reference for side-by-side comparison
    save_rgb_png(r_ref, g_ref, b_ref, os.path.join(OUT_DIR, "ref_rgb.png"))
    save_gray_png(y_ref,              os.path.join(OUT_DIR, "ref_gray.png"))

    print(f"\n{'='*40}")
    if total_errors == 0:
        print("RESULT: ALL PASS — DMEM MIF is correct for both RGB and grayscale display")
    else:
        print(f"RESULT: FAIL — {total_errors} total pixel errors across all channels")
    print(f"Output PNGs written to: {OUT_DIR}")


if __name__ == "__main__":
    main()
