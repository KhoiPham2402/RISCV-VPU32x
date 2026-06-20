#!/usr/bin/env python3
"""
reconstruct.py — Extract VPU grayscale output from DMEM dump.

Usage:
    python reconstruct.py [lena_dmem_out.hex]

Reads:
    lena_dmem_out.hex      512 x 32-bit words dumped by the testbench
    lena_y_reference.hex   64-word reference from prep_lena.py (optional)

Writes:
    lena_vpu_output.png/.pgm   VPU-computed grayscale image
    lena_comparison.png        side-by-side: colour input | reference | VPU output
"""

import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def read_hex_words(path):
    words = []
    with open(path) as f:
        for line in f:
            s = line.strip()
            if s and not s.startswith("//") and not s.startswith("#"):
                words.append(int(s, 16))
    return words


def words_to_bytes(words):
    out = []
    for w in words:
        out.append(w & 0xFF)
        out.append((w >> 8) & 0xFF)
        out.append((w >> 16) & 0xFF)
        out.append((w >> 24) & 0xFF)
    return out


def save_image(pixels, path, size=(16, 16)):
    try:
        from PIL import Image
        img = Image.new("L", size)
        img.putdata(pixels)
        img.save(path)
        print(f"Wrote {path}")
        return img
    except ImportError:
        pgm = path.replace(".png", ".pgm")
        w, h = size
        with open(pgm, "wb") as f:
            f.write(f"P5\n{w} {h}\n255\n".encode())
            f.write(bytes(pixels))
        print(f"Wrote {pgm}  (install Pillow for PNG/comparison output)")
        return None


def make_comparison(input_path, ref_path, vpu_img, out_path, scale=4):
    try:
        from PIL import Image, ImageDraw, ImageFont
        imgs = []
        labels = []
        for p, lbl in [(input_path, "Input (colour)"),
                       (ref_path,   "Reference (BT.601)"),
                       (None,       "VPU output")]:
            if p and os.path.exists(p):
                imgs.append(Image.open(p).convert("RGB").resize(
                    (128 * scale, 128 * scale), Image.LANCZOS))
            elif vpu_img and lbl == "VPU output":
                imgs.append(vpu_img.convert("RGB").resize(
                    (128 * scale, 128 * scale), Image.LANCZOS))
            else:
                imgs.append(Image.new("RGB", (128 * scale, 128 * scale), (64, 64, 64)))
            labels.append(lbl)

        gap = 6
        label_h = 20
        w_total = 128 * scale * 3 + gap * 4
        h_total = 128 * scale + gap * 2 + label_h
        canvas = Image.new("RGB", (w_total, h_total), (40, 40, 40))

        for idx, (im, lbl) in enumerate(zip(imgs, labels)):
            x = gap + idx * (128 * scale + gap)
            canvas.paste(im, (x, gap + label_h))
            draw = ImageDraw.Draw(canvas)
            draw.text((x + 2, 4), lbl, fill=(220, 220, 220))

        canvas.save(out_path)
        print(f"Wrote {out_path}")
    except ImportError:
        pass  # Pillow required for comparison image


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    dmem_file = sys.argv[1] if len(sys.argv) > 1 else \
                os.path.join(SCRIPT_DIR, "lena_dmem_out.hex")

    dmem_file = os.path.abspath(dmem_file)
    # Output images go to the same directory as the hex dump
    out_dir = os.path.dirname(dmem_file)

    if not os.path.exists(dmem_file):
        print(f"Error: {dmem_file} not found.")
        print("Run the simulation first with run_lena_sim.do, then call this script.")
        sys.exit(1)

    dmem = read_hex_words(dmem_file)
    if len(dmem) < 256:
        print(f"Error: expected ≥256 words in {dmem_file}, got {len(dmem)}")
        sys.exit(1)

    # Y channel: DMEM words 12288–16383 (byte addr 0x0C000–0x0FFFF)
    y_bytes = words_to_bytes(dmem[12288:16384])[:16384]

    print(f"VPU Y[0..7]  : {y_bytes[:8]}")
    print(f"VPU Y range  : min={min(y_bytes)}, max={max(y_bytes)}")

    ref_file = os.path.join(SCRIPT_DIR, "lena_y_reference.hex")
    passed = True
    if os.path.exists(ref_file):
        ref_bytes = words_to_bytes(read_hex_words(ref_file))[:16384]
        print(f"Ref Y[0..7]  : {ref_bytes[:8]}")
        diffs = [abs(y_bytes[i] - ref_bytes[i]) for i in range(16384)]
        max_err = max(diffs)
        bad = sum(1 for d in diffs if d > 2)
        print(f"Max error    : {max_err}  (tolerance ±2)")
        print(f"Mismatches>2 : {bad}/16384")
        passed = (max_err <= 2 and bad == 0)
        print("PASS" if passed else "FAIL")
    else:
        print("(No reference file — skipping comparison)")

    out_img = save_image(y_bytes,
                         os.path.join(out_dir, "lena_vpu_output.png"),
                         size=(128, 128))
    make_comparison(
        os.path.join(SCRIPT_DIR, "lena_input.png"),
        os.path.join(SCRIPT_DIR, "lena_reference.png"),
        out_img,
        os.path.join(out_dir, "lena_comparison.png"),
    )

    sys.exit(0 if passed else 1)
