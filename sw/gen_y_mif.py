"""
gen_y_mif.py — Pre-compute BT.601 grayscale Y channel and inject into DMEM MIFs.

DMEM layout (16384 words × 32-bit, 4 byte-lane banks):
  Words   0–4095  : R channel (bank[w] = R pixel at byte-address 4w+bank)
  Words 4096–8191 : G channel
  Words 8192–12287: B channel
  Words 12288–16383: Y channel (written by this script)

For pixel index i (0..16383):
  bank = i % 4   (which byte lane)
  word = i // 4  (word address within channel)
  R[i] = dmem_b{bank}[word]
  G[i] = dmem_b{bank}[4096 + word]
  B[i] = dmem_b{bank}[8192 + word]
  Y[i] = floor(R*77/256) + floor(G*150/256) + floor(B*29/256)  ← BT.601 integer approx
  Written to dmem_b{bank}[12288 + word]

Usage:
  python gen_y_mif.py [mif_dir]
  Default mif_dir: C:/CapstoneProject2/FPGA/riscv_vpu
"""

import sys
import re
import os

MIF_DIR = sys.argv[1] if len(sys.argv) > 1 else "C:/CapstoneProject2/FPGA/riscv_vpu"

def read_mif(path):
    """Return {addr: byte_val} from a WIDTH=8 MIF."""
    d = {}
    with open(path) as f:
        for line in f:
            m = re.match(r'\s*([0-9A-Fa-f]+)\s*:\s*([0-9A-Fa-f]+)', line)
            if m:
                addr = int(m.group(1), 16)
                val  = int(m.group(2), 16) & 0xFF
                d[addr] = val
    return d

def write_mif(path, data, depth=16384):
    """Write {addr: byte_val} dict back into the MIF file, preserving header."""
    with open(path) as f:
        original = f.read()

    # Extract header (everything before CONTENT BEGIN)
    header_match = re.search(r'(.*?CONTENT BEGIN\s*\n)', original, re.DOTALL | re.IGNORECASE)
    header = header_match.group(1) if header_match else "WIDTH = 8;\nDEPTH = 16384;\n\nADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\n\nCONTENT BEGIN\n"

    lines = [header.rstrip('\n')]
    for addr in range(depth):
        val = data.get(addr, 0)
        lines.append(f'\t{addr:04X} : {val:02X};')
    lines.append('END;')

    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n')

# ── Load all 4 banks ─────────────────────────────────────────────────────────
banks = []
for i in range(4):
    path = os.path.join(MIF_DIR, f'dmem_b{i}.mif')
    banks.append(read_mif(path))
    print(f'Loaded {path}  ({len(banks[-1])} entries)')

# ── Compute Y channel ─────────────────────────────────────────────────────────
y_count = 0
for pix_idx in range(16384):
    bank = pix_idx % 4
    word = pix_idx // 4

    r = banks[bank].get(word,       0)
    g = banks[bank].get(4096 + word, 0)
    b = banks[bank].get(8192 + word, 0)

    # BT.601: Y = floor(R*77/256) + floor(G*150/256) + floor(B*29/256)
    y = (r * 77 >> 8) + (g * 150 >> 8) + (b * 29 >> 8)
    y = min(y, 255)

    banks[bank][12288 + word] = y
    y_count += 1

print(f'Computed {y_count} Y pixels')

# Quick sanity: first 4 pixels
print('Sample Y values (pixels 0-3):')
for i in range(4):
    bank = i % 4; word = i // 4
    r = banks[bank].get(word, 0)
    g = banks[bank].get(4096+word, 0)
    b = banks[bank].get(8192+word, 0)
    y = banks[bank][12288+word]
    print(f'  pix[{i}]: R={r:3d} G={g:3d} B={b:3d} -> Y={y:3d} (0x{y:02X})')

# ── Write back ────────────────────────────────────────────────────────────────
for i in range(4):
    path = os.path.join(MIF_DIR, f'dmem_b{i}.mif')
    write_mif(path, banks[i])
    print(f'Updated {path}')

print('Done. Y channel pre-loaded in all 4 bank MIF files.')
