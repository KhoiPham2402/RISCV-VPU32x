#!/usr/bin/env python3
"""
make_imem_mifs.py — Split a 32-bit word-per-line hex file into four
                    8-bit byte-lane MIF files for Quartus altsyncram ROM:1-PORT.

Usage:
    python make_imem_mifs.py <input.hex> <depth> <outdir>

Example (from project root):
    python sw/make_imem_mifs.py fpga/uart_lena.hex 2048 fpga/

Produces:
    <outdir>/imem_b0.mif  — bits  7:0  of each instruction word
    <outdir>/imem_b1.mif  — bits 15:8
    <outdir>/imem_b2.mif  — bits 23:16
    <outdir>/imem_b3.mif  — bits 31:24

MIF format accepted by Quartus 18.1 altsyncram with WIDTH=8, DEPTH=<depth>.
"""

import sys
import os

def write_mif(path, depth, data_bytes):
    with open(path, 'w') as f:
        f.write(f"WIDTH=8;\n")
        f.write(f"DEPTH={depth};\n\n")
        f.write("ADDRESS_RADIX=HEX;\n")
        f.write("DATA_RADIX=HEX;\n\n")
        f.write("CONTENT BEGIN\n")
        for addr, val in enumerate(data_bytes):
            f.write(f"\t{addr:04X} : {val:02X};\n")
        # Fill remaining with 0 if shorter than depth
        for addr in range(len(data_bytes), depth):
            f.write(f"\t{addr:04X} : 00;\n")
        f.write("END;\n")

def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <input.hex> <depth> <outdir>")
        sys.exit(1)

    hex_file = sys.argv[1]
    depth    = int(sys.argv[2])
    outdir   = sys.argv[3]

    words = []
    with open(hex_file) as f:
        for line in f:
            line = line.strip()
            if line:
                words.append(int(line, 16))

    if len(words) > depth:
        print(f"WARNING: hex has {len(words)} words > depth {depth}, truncating.")
        words = words[:depth]

    # Split into 4 byte lanes (little-endian: b0=bits7:0, b3=bits31:24)
    b = [[] for _ in range(4)]
    for w in words:
        b[0].append(w & 0xFF)
        b[1].append((w >> 8)  & 0xFF)
        b[2].append((w >> 16) & 0xFF)
        b[3].append((w >> 24) & 0xFF)

    os.makedirs(outdir, exist_ok=True)
    for i in range(4):
        path = os.path.join(outdir, f"imem_b{i}.mif")
        write_mif(path, depth, b[i])
        print(f"Wrote {path}  ({len(b[i])} entries)")

if __name__ == "__main__":
    main()
