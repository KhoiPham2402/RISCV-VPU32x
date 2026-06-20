"""
prepare_image.py — Resize any image to 128x128 and export R/G/B planar files.

Usage:
    python prepare_image.py <input_image> [output_dir]

Output files (each 16384 bytes):
    lena_R.bin   — Red   channel, row-major
    lena_G.bin   — Green channel
    lena_B.bin   — Blue  channel

Example:
    python prepare_image.py lena.png .
    python prepare_image.py photo.jpg ./data/
"""

import sys
import os
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow not installed. Run: pip install Pillow")
    sys.exit(1)


def prepare(src_path: str, out_dir: str = ".") -> tuple[str, str, str]:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    img = Image.open(src_path).resize((128, 128), Image.LANCZOS).convert("RGB")
    r, g, b = img.split()

    r_path = out_dir / "lena_R.bin"
    g_path = out_dir / "lena_G.bin"
    b_path = out_dir / "lena_B.bin"

    r_path.write_bytes(r.tobytes())
    g_path.write_bytes(g.tobytes())
    b_path.write_bytes(b.tobytes())

    assert len(r.tobytes()) == 16384, "R plane size error"
    assert len(g.tobytes()) == 16384, "G plane size error"
    assert len(b.tobytes()) == 16384, "B plane size error"

    print(f"[OK] Saved {r_path.name}, {g_path.name}, {b_path.name}  (16384 bytes each)")
    return str(r_path), str(g_path), str(b_path)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src   = sys.argv[1]
    out   = sys.argv[2] if len(sys.argv) > 2 else "."
    prepare(src, out)
