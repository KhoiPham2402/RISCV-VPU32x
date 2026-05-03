#!/usr/bin/env python3
"""
prep_lena.py — Prepare DMEM initialization for the lena_gray VPU benchmark.

Searches for a Lena image file (lena_raw.png first, then common names);
falls back to a synthetic color test pattern if none is found.

Output files written to the same directory as this script:
  lena_dmem_init.hex    16384 x 32-bit words (one hex word per line)
                          words     0– 4095 : R channel (16384 pixels, LE byte order)
                          words  4096– 8191 : G channel
                          words  8192–12287 : B channel
                          words 12288–16383 : zeros (Y output area)
  lena_input.png/.pgm   128x128 colour source (for visual inspection)
  lena_reference.png/.pgm  128x128 BT.601 reference grayscale
  lena_y_reference.hex  4096 words — expected Y channel (for reconstruct.py)
"""

import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

IMG_SIZE  = 128
N_PIXELS  = IMG_SIZE * IMG_SIZE   # 16384


# ---------------------------------------------------------------------------
# Image loading / synthetic generation
# ---------------------------------------------------------------------------

def _synthetic_rgb():
    """128x128 colour ramp: R increases left→right, G top→bottom, B diagonal."""
    r, g, b = [], [], []
    for row in range(IMG_SIZE):
        for col in range(IMG_SIZE):
            r.append((col * 2) & 0xFF)
            g.append((row * 2) & 0xFF)
            b.append(((row + col)) & 0xFF)
    return r, g, b


def load_image():
    """Return (r, g, b) lists of N_PIXELS uint8 values for a 128x128 image."""
    search_paths = [
        os.path.join(SCRIPT_DIR, "lena_raw.png"),
        os.path.join(SCRIPT_DIR, "lena_raw.jpg"),
        os.path.join(SCRIPT_DIR, "lena.png"),
        os.path.join(SCRIPT_DIR, "lena.jpg"),
        os.path.join(SCRIPT_DIR, "lena.bmp"),
        os.path.join(SCRIPT_DIR, "..", "..", "..", "lena.png"),
        os.path.join(SCRIPT_DIR, "..", "..", "..", "lena.jpg"),
    ]

    try:
        from PIL import Image
        for path in search_paths:
            if os.path.exists(path):
                img = Image.open(path).convert("RGB").resize(
                    (IMG_SIZE, IMG_SIZE), Image.LANCZOS)
                print(f"Loaded: {path}")
                pixels = list(img.getdata())
                r = [p[0] for p in pixels]
                g = [p[1] for p in pixels]
                b = [p[2] for p in pixels]
                _save_png(img, os.path.join(SCRIPT_DIR, "lena_input.png"))
                return r, g, b
        print("Lena image not found — using synthetic colour ramp.")
        r, g, b = _synthetic_rgb()
        _save_synthetic_png(r, g, b, os.path.join(SCRIPT_DIR, "lena_input.png"))
        return r, g, b
    except ImportError:
        print("Pillow not installed — using synthetic colour ramp (no PNG output).")
        return _synthetic_rgb()


def _save_png(img, path):
    try:
        img.save(path)
        print(f"Wrote {path}")
    except Exception as e:
        print(f"Warning: could not save {path}: {e}")


def _save_synthetic_png(r, g, b, path):
    try:
        from PIL import Image
        img = Image.new("RGB", (IMG_SIZE, IMG_SIZE))
        img.putdata(list(zip(r, g, b)))
        _save_png(img, path)
    except ImportError:
        pgm_path = path.replace(".png", ".pgm")
        with open(pgm_path, "wb") as f:
            f.write(f"P6\n{IMG_SIZE} {IMG_SIZE}\n255\n".encode())
            for i in range(N_PIXELS):
                f.write(bytes([r[i], g[i], b[i]]))
        print(f"Wrote {pgm_path}")


# ---------------------------------------------------------------------------
# BT.601 reference (must match VPU vmulhu.vx approximation exactly)
# ---------------------------------------------------------------------------

def bt601_approx(r, g, b):
    """Y[i] = floor(R*77/256) + floor(G*150/256) + floor(B*29/256)"""
    return [(r[i] * 77 >> 8) + (g[i] * 150 >> 8) + (b[i] * 29 >> 8)
            for i in range(N_PIXELS)]


# ---------------------------------------------------------------------------
# Packing helpers
# ---------------------------------------------------------------------------

def pack_channel(ch):
    """N_PIXELS bytes → N_PIXELS//4 little-endian 32-bit words."""
    words = []
    for i in range(0, N_PIXELS, 4):
        w = ch[i] | (ch[i+1] << 8) | (ch[i+2] << 16) | (ch[i+3] << 24)
        words.append(w)
    return words


# ---------------------------------------------------------------------------
# Output writers
# ---------------------------------------------------------------------------

def write_dmem_init(r, g, b, path):
    r_words = pack_channel(r)   # 4096 words — byte addr 0x00000
    g_words = pack_channel(g)   # 4096 words — byte addr 0x04000
    b_words = pack_channel(b)   # 4096 words — byte addr 0x08000
    with open(path, "w") as f:
        for w in r_words:
            f.write(f"{w:08x}\n")
        for w in g_words:
            f.write(f"{w:08x}\n")
        for w in b_words:
            f.write(f"{w:08x}\n")
        for _ in range(4096):   # Y output area — byte addr 0x0C000 (zeros)
            f.write("00000000\n")
    print(f"Wrote {path}")


def write_y_reference(y, path):
    with open(path, "w") as f:
        for i in range(0, N_PIXELS, 4):
            w = y[i] | (y[i+1] << 8) | (y[i+2] << 16) | (y[i+3] << 24)
            f.write(f"{w:08x}\n")
    print(f"Wrote {path}")


def write_reference_image(y, path):
    try:
        from PIL import Image
        img = Image.new("L", (IMG_SIZE, IMG_SIZE))
        img.putdata(y)
        _save_png(img, path)
    except ImportError:
        pgm = path.replace(".png", ".pgm")
        with open(pgm, "wb") as f:
            f.write(f"P5\n{IMG_SIZE} {IMG_SIZE}\n255\n".encode())
            f.write(bytes(y))
        print(f"Wrote {pgm}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    r, g, b = load_image()

    y_ref = bt601_approx(r, g, b)
    print(f"Reference Y[0..7] : {y_ref[:8]}")
    print(f"Y range           : min={min(y_ref)}, max={max(y_ref)}")

    write_dmem_init(r, g, b,
                    os.path.join(SCRIPT_DIR, "lena_dmem_init.hex"))
    write_y_reference(y_ref,
                      os.path.join(SCRIPT_DIR, "lena_y_reference.hex"))
    write_reference_image(y_ref,
                          os.path.join(SCRIPT_DIR, "lena_reference.png"))
