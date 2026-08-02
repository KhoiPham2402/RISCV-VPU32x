#!/usr/bin/env python3
"""
prep_sobel.py — Prepare DMEM initialization + reference output for the
Sobel edge-detection VPU benchmark. Reuses lena_gray's Lena source image
and BT.601 grayscale conversion (sw/benchmarks/lena_gray/lena_raw.png,
same bt601_approx formula as prep_lena.py), resized to 64x64.

Why 64x64 and 1 pixel / 32-bit word (not 128x128 @ 1 byte/pixel like
lena_gray): the VLSU discards addr[1:0] (project issue #25) — a +-1-pixel
horizontal tap is only a valid aligned load if 1 pixel = 1 word. 128x128 at
4 bytes/pixel would use the entire 64KB DMEM with no room for the output
plane, so the image is downsized instead of changing the memory layout.

DMEM byte map (must match sobel.c's IN_BASE/OUT_BASE and
fpga/bench/tb_sobel_lena.sv's dump layout):
  0x0000–0x0FFF  unused (below sp; crt0 reserves this for .bss/stack)
  0x1000–0x4FFF  input   64x64 grayscale, 1 pixel / word (word idx 1024..5119)
  0x5000–0x8FFF  output  64x64 edge magnitude, pre-zeroed (word idx 5120..9215)
  0x9000–0xFFFF  unused

Output files written to this script's directory:
  sobel_dmem_init.hex   16384 x 32-bit words (one hex word per line)
  sobel_input.png       64x64 grayscale source (visual)
  sobel_reference.png   64x64 Sobel edge magnitude (visual reference)
  sobel_ref.hex         4096 words — expected output plane, row-major,
                         computed with the *identical* integer arithmetic
                         as sobel.c (|Gx|+|Gy| approximation, not sqrt)
"""

import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LENA_GRAY_DIR = os.path.join(SCRIPT_DIR, "..", "lena_gray")

IMG_SIZE = 64
N_PIXELS = IMG_SIZE * IMG_SIZE          # 4096

IN_WORD_BASE  = 0x1000 // 4             # 1024
OUT_WORD_BASE = 0x5000 // 4             # 5120
DMEM_WORDS    = 16384                   # 64 KB


# ---------------------------------------------------------------------------
# Image loading (reuses the lena_gray source; no new image is fetched)
# ---------------------------------------------------------------------------

def _synthetic_gray():
    """64x64 diagonal ramp fallback if no source image / Pillow is available."""
    return [((r * 4) ^ (c * 4)) & 0xFF for r in range(IMG_SIZE) for c in range(IMG_SIZE)]


def load_gray():
    """Return a list of N_PIXELS uint8 grayscale values, 64x64, row-major."""
    search_paths = [
        os.path.join(LENA_GRAY_DIR, "lena_raw.png"),
        os.path.join(SCRIPT_DIR, "lena_raw.png"),
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
                gray = bt601_approx(r, g, b)
                _save_gray_png(gray, os.path.join(SCRIPT_DIR, "sobel_input.png"))
                return gray
        print("Lena source not found — using synthetic diagonal ramp.")
        gray = _synthetic_gray()
        _save_gray_png(gray, os.path.join(SCRIPT_DIR, "sobel_input.png"))
        return gray
    except ImportError:
        print("Pillow not installed — using synthetic diagonal ramp (no PNG output).")
        return _synthetic_gray()


def bt601_approx(r, g, b):
    """Y[i] = floor(R*77/256) + floor(G*150/256) + floor(B*29/256) —
    identical formula to prep_lena.py / lena_gray.c, so the grayscale
    conversion itself is not something new being introduced here."""
    return [(r[i] * 77 >> 8) + (g[i] * 150 >> 8) + (b[i] * 29 >> 8)
            for i in range(N_PIXELS)]


def _save_gray_png(gray, path):
    try:
        from PIL import Image
        img = Image.new("L", (IMG_SIZE, IMG_SIZE))
        img.putdata(gray)
        img.save(path)
        print(f"Wrote {path}")
    except ImportError:
        pgm = path.replace(".png", ".pgm")
        with open(pgm, "wb") as f:
            f.write(f"P5\n{IMG_SIZE} {IMG_SIZE}\n255\n".encode())
            f.write(bytes(gray))
        print(f"Wrote {pgm}")
    except Exception as e:
        print(f"Warning: could not save {path}: {e}")


# ---------------------------------------------------------------------------
# Pure-Python Sobel reference — must match sobel.c's arithmetic exactly:
# |Gx|+|Gy| approximation (not sqrt(Gx^2+Gy^2)), clamped to 255, borders=0.
# ---------------------------------------------------------------------------

def sobel_reference(gray):
    W = H = IMG_SIZE
    out = [0] * N_PIXELS

    def px(r, c):
        return gray[r * W + c]

    for r in range(1, H - 1):
        for c in range(1, W - 1):
            uL, uC, uR = px(r - 1, c - 1), px(r - 1, c), px(r - 1, c + 1)
            cL,      cR = px(r,     c - 1),                px(r,     c + 1)
            dL, dC, dR = px(r + 1, c - 1), px(r + 1, c), px(r + 1, c + 1)

            pos_x = cR + cR + uR + dR
            neg_x = cL + cL + uL + dL
            gx = max(pos_x, neg_x) - min(pos_x, neg_x)

            pos_y = dC + dC + dL + dR
            neg_y = uC + uC + uL + uR
            gy = max(pos_y, neg_y) - min(pos_y, neg_y)

            out[r * W + c] = min(gx + gy, 255)

    return out


# ---------------------------------------------------------------------------
# Output writers
# ---------------------------------------------------------------------------

def write_dmem_init(gray, path):
    with open(path, "w") as f:
        for word_idx in range(DMEM_WORDS):
            if IN_WORD_BASE <= word_idx < IN_WORD_BASE + N_PIXELS:
                v = gray[word_idx - IN_WORD_BASE]
            else:
                v = 0
            f.write(f"{v:08x}\n")
    print(f"Wrote {path}")


def write_ref_hex(ref, path):
    with open(path, "w") as f:
        for v in ref:
            f.write(f"{v:08x}\n")
    print(f"Wrote {path}")


def write_ref_png(ref, path):
    try:
        from PIL import Image
        img = Image.new("L", (IMG_SIZE, IMG_SIZE))
        img.putdata(ref)
        img.save(path)
        print(f"Wrote {path}")
    except ImportError:
        pgm = path.replace(".png", ".pgm")
        with open(pgm, "wb") as f:
            f.write(f"P5\n{IMG_SIZE} {IMG_SIZE}\n255\n".encode())
            f.write(bytes(ref))
        print(f"Wrote {pgm}")
    except Exception as e:
        print(f"Warning: could not save {path}: {e}")


if __name__ == "__main__":
    gray = load_gray()
    ref = sobel_reference(gray)

    print(f"Input gray[0..7]  : {gray[:8]}")
    print(f"Reference out[64+1..64+8] (row1): {ref[64+1:64+9]}")
    print(f"Reference range   : min={min(ref)}, max={max(ref)}")

    write_dmem_init(gray, os.path.join(SCRIPT_DIR, "sobel_dmem_init.hex"))
    write_ref_hex(ref, os.path.join(SCRIPT_DIR, "sobel_ref.hex"))
    write_ref_png(ref, os.path.join(SCRIPT_DIR, "sobel_reference.png"))
