#!/usr/bin/env python3
"""
gen_lena_y_mif.py — Generate 4 DMEM byte-lane MIF files with Lena grayscale
                    pre-loaded directly in the VGA display area (words 12288-16383).

No VPU needed: VGA controller reads from 0xC000-0xFFFF and displays immediately.

Input : sw/benchmarks/lena_gray/lena_y_reference.hex
          4096 lines x 32-bit word (little-endian bytes)
          word[i] = Y[4i] | Y[4i+1]<<8 | Y[4i+2]<<16 | Y[4i+3]<<24

Output (Quartus project dir):
  dmem_b0.mif  bits[ 7: 0] — words 0-12287 = 0x00, words 12288-16383 = Y bytes
  dmem_b1.mif  bits[15: 8]
  dmem_b2.mif  bits[23:16]
  dmem_b3.mif  bits[31:24]

Usage (run from repo root):
    python fpga/gen_lena_y_mif.py
"""

import os, sys

SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
Y_HEX       = os.path.join(REPO_ROOT, "sw", "benchmarks", "lena_gray",
                            "lena_y_reference.hex")
QUARTUS_DIR = r"C:\CapstoneProject2\FPGA\riscv_vpu"
DEPTH       = 16384
VGA_OFFSET  = 12288   # word address 0x3000 = byte addr 0xC000

def main():
    if not os.path.exists(Y_HEX):
        print(f"ERROR: {Y_HEX} not found.")
        print("  Run: python sw/benchmarks/lena_gray/prep_lena.py  first.")
        sys.exit(1)

    with open(Y_HEX) as f:
        lines = [l.strip() for l in f if l.strip()]
    if len(lines) != 4096:
        print(f"ERROR: expected 4096 lines, got {len(lines)}")
        sys.exit(1)

    y_words = [int(l, 16) for l in lines]

    # Build 4 full-depth byte arrays (all zeros then overwrite VGA area)
    banks = [[0] * DEPTH for _ in range(4)]
    for i, w in enumerate(y_words):
        for lane in range(4):
            banks[lane][VGA_OFFSET + i] = (w >> (8 * lane)) & 0xFF

    for lane in range(4):
        path = os.path.join(QUARTUS_DIR, f"dmem_b{lane}.mif")
        with open(path, "w") as f:
            f.write(f"WIDTH = 8;\nDEPTH = {DEPTH};\n\n")
            f.write("ADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\n\nCONTENT BEGIN\n")
            # Write only non-zero entries for compactness; fill rest with 0
            f.write(f"\t[0000..{VGA_OFFSET-1:04X}] : 00;\n")
            for addr, val in enumerate(banks[lane][VGA_OFFSET:], start=VGA_OFFSET):
                f.write(f"\t{addr:04X} : {val:02X};\n")
            f.write("END;\n")
        print(f"Wrote {path}")

    print()
    print("Done. Full recompile in Quartus, then program .sof.")
    print(f"  Y[0..3] = {y_words[0] & 0xFF:#04x} {(y_words[0]>>8) & 0xFF:#04x}"
          f" {(y_words[0]>>16) & 0xFF:#04x} {(y_words[0]>>24) & 0xFF:#04x}")

if __name__ == "__main__":
    main()
