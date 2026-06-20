#!/usr/bin/env python3
"""
gen_dmem_mif.py — Split lena_dmem_init.hex into 4 byte-lane MIF files
                  for Quartus altsyncram (dmem_bank) initialization.

Input:
    sw/benchmarks/lena_gray/lena_dmem_init.hex
        16384 lines × 8 hex chars (one 32-bit word per line, little-endian bytes)
        words     0– 4095 : R channel
        words  4096– 8191 : G channel
        words  8192–12287 : B channel
        words 12288–16383 : zeros (Y output area, VPU writes here at run time)

Output (written to <quartus_project_dir>):
    dmem_b0.mif  — bits[ 7: 0] of each word  (byte lane 0)
    dmem_b1.mif  — bits[15: 8]               (byte lane 1)
    dmem_b2.mif  — bits[23:16]               (byte lane 2)
    dmem_b3.mif  — bits[31:24]               (byte lane 3)

Usage (run from repo root):
    python fpga/gen_dmem_mif.py

Then copy/confirm dmem_b*.mif are in the Quartus project directory:
    C:/CapstoneProject2/FPGA/riscv_vpu/
"""

import os
import sys

SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT    = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
DMEM_HEX     = os.path.join(REPO_ROOT, "sw", "benchmarks", "lena_gray",
                             "lena_dmem_init.hex")
QUARTUS_DIR  = r"C:\CapstoneProject2\FPGA\riscv_vpu"
DEPTH        = 16384

MIF_HEADER = """\
WIDTH = 8;
DEPTH = {depth};

ADDRESS_RADIX = HEX;
DATA_RADIX = HEX;

CONTENT BEGIN
"""
MIF_FOOTER = "END;\n"


def main():
    if not os.path.exists(DMEM_HEX):
        print(f"ERROR: {DMEM_HEX} not found.")
        print("  Run: python sw/benchmarks/lena_gray/prep_lena.py  first.")
        sys.exit(1)

    with open(DMEM_HEX) as f:
        lines = [l.strip() for l in f if l.strip()]

    if len(lines) != DEPTH:
        print(f"ERROR: expected {DEPTH} lines, got {len(lines)}")
        sys.exit(1)

    words = [int(l, 16) for l in lines]

    # Split into 4 byte lanes
    lanes = [[(w >> (8 * lane)) & 0xFF for w in words] for lane in range(4)]

    for lane, data in enumerate(lanes):
        path = os.path.join(QUARTUS_DIR, f"dmem_b{lane}.mif")
        with open(path, "w") as f:
            f.write(MIF_HEADER.format(depth=DEPTH))
            for addr, byte in enumerate(data):
                f.write(f"\t{addr:04X} : {byte:02X};\n")
            f.write(MIF_FOOTER)
        print(f"Wrote {path}")

    print()
    print("Done. Verify files exist in Quartus project, then:")
    print("  1. In Quartus: Processing > Start Compilation  (full recompile)")
    print("  2. Program .sof to board")


if __name__ == "__main__":
    main()
