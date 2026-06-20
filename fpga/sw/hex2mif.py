#!/usr/bin/env python3
"""
hex2mif.py — Convert a one-word-per-line hex file to Quartus MIF format.

Usage:
    python hex2mif.py <input.hex> <output.mif> [--depth N] [--width W]

Defaults: depth=2048 (words), width=32 (bits).
The hex file must have exactly one 32-bit hex word per line (no 0x prefix).
Produced MIF is compatible with Quartus altsyncram and ram_init_file attribute.
"""

import sys
import argparse

def hex_to_mif(hex_path: str, mif_path: str, depth: int, width: int) -> None:
    words = []
    with open(hex_path, "r") as f:
        for line in f:
            stripped = line.strip()
            if stripped:
                words.append(int(stripped, 16))

    if len(words) > depth:
        print(f"WARNING: {len(words)} words in hex > depth {depth}; truncating.", file=sys.stderr)
        words = words[:depth]

    with open(mif_path, "w") as f:
        f.write(f"WIDTH = {width};\n")
        f.write(f"DEPTH = {depth};\n\n")
        f.write("ADDRESS_RADIX = UNS;\n")
        f.write("DATA_RADIX = HEX;\n\n")
        f.write("CONTENT BEGIN\n")
        for i, w in enumerate(words):
            f.write(f"\t{i} : {w:08X};\n")
        if len(words) < depth:
            f.write(f"\t[{len(words)}..{depth - 1}] : 00000000;\n")
        f.write("END;\n")

    print(f"Wrote {len(words)} words to {mif_path} (depth={depth}, width={width})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert hex to Quartus MIF")
    parser.add_argument("hex", help="Input hex file (one 32-bit word per line)")
    parser.add_argument("mif", help="Output MIF file")
    parser.add_argument("--depth", type=int, default=2048, help="Memory depth in words (default: 2048)")
    parser.add_argument("--width", type=int, default=32, help="Data width in bits (default: 32)")
    args = parser.parse_args()

    hex_to_mif(args.hex, args.mif, args.depth, args.width)
