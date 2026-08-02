#!/usr/bin/env python3
"""
reconstruct_sobel.py — Verify the RTL simulation's Sobel output against the
pure-Python reference and render it as a PNG.

Sibling to lena_gray/reconstruct.py, not a reuse: the packing convention
differs (1 pixel / 32-bit word here, vs. 4 pixels / word there), so the two
scripts aren't interchangeable.

Input:  sobel_dmem_out.hex   — full 16384-word DMEM dump from
                               fpga/bench/tb_sobel_lena.sv (one %08x word per
                               line, matches bench/tb_lena_gray.sv's dump format)
        sobel_ref.hex        — 4096-word pure-Python reference from prep_sobel.py

Output: sobel_vpu_output.png — the VPU's edge-detection result
        sobel_comparison.png — input | reference | VPU output, side by side

Comparison uses ZERO tolerance: both the C firmware and the Python reference
run the identical integer |Gx|+|Gy| arithmetic (see sobel.c / prep_sobel.py's
sobel_reference()), so an exact match is the correct bar — unlike lena_gray's
±2 tolerance, which allows for a genuinely different reference algorithm.
"""

import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

IMG_SIZE  = 64
N_PIXELS  = IMG_SIZE * IMG_SIZE   # 4096
OUT_WORD_BASE = 0x5000 // 4       # 5120


def read_hex_words(path):
    words = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//") or line.startswith("#"):
                continue
            words.append(int(line, 16))
    return words


def main():
    dmem_out_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(SCRIPT_DIR, "sobel_dmem_out.hex")
    ref_path      = os.path.join(SCRIPT_DIR, "sobel_ref.hex")

    if not os.path.exists(dmem_out_path):
        print(f"ERROR: {dmem_out_path} not found — run fpga/sim/run_sobel_lena.do first.")
        return 1
    if not os.path.exists(ref_path):
        print(f"ERROR: {ref_path} not found — run prep_sobel.py first.")
        return 1

    dmem = read_hex_words(dmem_out_path)
    ref = read_hex_words(ref_path)

    if len(dmem) < OUT_WORD_BASE + N_PIXELS:
        print(f"ERROR: {dmem_out_path} has only {len(dmem)} words, "
              f"expected at least {OUT_WORD_BASE + N_PIXELS}.")
        return 1
    if len(ref) != N_PIXELS:
        print(f"ERROR: {ref_path} has {len(ref)} words, expected {N_PIXELS}.")
        return 1

    vpu_out = [dmem[OUT_WORD_BASE + i] & 0xFF for i in range(N_PIXELS)]

    mismatches = 0
    max_err = 0
    first_mismatch = None
    for i in range(N_PIXELS):
        err = abs(vpu_out[i] - ref[i])
        if err != 0:
            mismatches += 1
            max_err = max(max_err, err)
            if first_mismatch is None:
                r, c = divmod(i, IMG_SIZE)
                first_mismatch = (r, c, vpu_out[i], ref[i])

    print(f"Pixels compared : {N_PIXELS} (interior 62x62 = {62*62} non-border)")
    print(f"Mismatches      : {mismatches}")
    print(f"Max error       : {max_err}")
    if first_mismatch:
        r, c, got, exp = first_mismatch
        print(f"First mismatch  : row={r} col={c} got={got} expected={exp}")

    passed = (mismatches == 0)
    print("RESULT: PASS" if passed else "RESULT: FAIL")

    write_output_png(vpu_out, os.path.join(SCRIPT_DIR, "sobel_vpu_output.png"))
    write_comparison_png(vpu_out, ref)

    return 0 if passed else 1


def write_output_png(vpu_out, path):
    try:
        from PIL import Image
        img = Image.new("L", (IMG_SIZE, IMG_SIZE))
        img.putdata(vpu_out)
        img.save(path)
        print(f"Wrote {path}")
    except ImportError:
        pgm = path.replace(".png", ".pgm")
        with open(pgm, "wb") as f:
            f.write(f"P5\n{IMG_SIZE} {IMG_SIZE}\n255\n".encode())
            f.write(bytes(vpu_out))
        print(f"Wrote {pgm}")
    except Exception as e:
        print(f"Warning: could not save {path}: {e}")


def write_comparison_png(vpu_out, ref):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("Pillow not installed — skipping sobel_comparison.png")
        return

    input_path = os.path.join(SCRIPT_DIR, "sobel_input.png")
    try:
        input_img = Image.open(input_path).convert("L")
    except Exception:
        input_img = Image.new("L", (IMG_SIZE, IMG_SIZE))

    ref_img = Image.new("L", (IMG_SIZE, IMG_SIZE))
    ref_img.putdata(ref)
    out_img = Image.new("L", (IMG_SIZE, IMG_SIZE))
    out_img.putdata(vpu_out)

    scale = 4
    label_h = 16
    tile = IMG_SIZE * scale
    canvas = Image.new("L", (tile * 3 + 2 * 8, tile + label_h), color=32)
    draw = ImageDraw.Draw(canvas)

    for idx, (img, label) in enumerate([
        (input_img, "input (grayscale)"),
        (ref_img, "reference (Python)"),
        (out_img, "VPU output"),
    ]):
        x0 = idx * (tile + 8)
        big = img.resize((tile, tile), Image.NEAREST)
        canvas.paste(big, (x0, label_h))
        draw.text((x0, 2), label, fill=255)

    comp_path = os.path.join(SCRIPT_DIR, "sobel_comparison.png")
    canvas.save(comp_path)
    print(f"Wrote {comp_path}")


if __name__ == "__main__":
    sys.exit(main())
