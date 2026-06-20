#!/usr/bin/env python3
"""
Đọc file binary (ELF -> objcopy -O binary): mỗi 4 byte LE = 1 lệnh RISC-V,
in một dòng hex 8 ký tự — đúng kiểu counter.hex / $readmemh.
"""
import struct
import sys


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: elf2hex_lines.py <file.bin>", file=sys.stderr)
        sys.exit(2)
    with open(sys.argv[1], "rb") as f:
        data = f.read()
    n = len(data) - (len(data) % 4)
    for i in range(0, n, 4):
        (w,) = struct.unpack("<I", data[i : i + 4])
        print(f"{w:08X}")


if __name__ == "__main__":
    main()
