# Build axpy_imem.hex from axpy.c + main.c using the real riscv64-unknown-elf-
# gcc toolchain (MSYS2: pacman -S mingw-w64-x86_64-riscv64-unknown-elf-gcc).
# Verified 2026-08-01: fresh build is byte-identical to the checked-in
# axpy_imem.hex — this Makefile documents/reproduces exactly what produced it.
#
# Run: make            (from this directory)
#      make disasm     to inspect the compiled instructions

RISCV_PREFIX ?= riscv64-unknown-elf-
CC      = $(RISCV_PREFIX)gcc

# ── Windows GCC.exe temp dir fix ──────────────────────────────────────────────
# GCC.exe ignores MSYS2 /tmp and uses Windows TEMP/TMP; ensure they are set.
# (Same workaround as sw/Makefile — needed because make does not reliably
# inherit TEMP/TMP exported by an outer shell when invoking native gcc.exe.)
_mktmp   := $(shell mkdir -p ../../../tmp 2>/dev/null)
_wintemp := $(shell cd ../../../tmp && pwd -W 2>/dev/null)
ifeq ($(strip $(_wintemp)),)
  _wintemp := $(shell cd ../../../tmp && pwd)
endif
export TEMP := $(_wintemp)
export TMP  := $(_wintemp)

OBJCOPY = $(RISCV_PREFIX)objcopy
OBJDUMP = $(RISCV_PREFIX)objdump
PYTHON  ?= python

ROOT    = ../../..
SW      = $(ROOT)/sw
COMMON  = ../common

MARCH   = rv32im_zicsr_zve32x_zvl128b
MABI    = ilp32
CFLAGS  = -march=$(MARCH) -mabi=$(MABI) -mcmodel=medlow \
          -Os -ffreestanding -fno-builtin -fno-pic -fno-pie \
          -nostdlib -nostartfiles \
          -Wall -Wextra

LDFLAGS = -Wl,-T$(COMMON)/link_bench.ld -Wl,--build-id=none

IMEM_HEX = axpy_imem.hex

all: $(IMEM_HEX)
	@echo "Build done. Wrote $(IMEM_HEX)"

crt0.o: $(COMMON)/crt0.S
	$(CC) $(CFLAGS) -c -o $@ $<

axpy.o: axpy.c
	$(CC) $(CFLAGS) -c -o $@ $<

main.o: main.c
	$(CC) $(CFLAGS) -c -o $@ $<

# crt0.o linked first so _start lands at address 0x000
axpy_bench.elf: crt0.o axpy.o main.o
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

axpy_bench.bin: axpy_bench.elf
	$(OBJCOPY) -O binary $< $@

$(IMEM_HEX): axpy_bench.bin
	$(PYTHON) $(SW)/elf2hex_lines.py $< > $(IMEM_HEX)
	@echo "Wrote $(IMEM_HEX)"

disasm: axpy_bench.elf
	$(OBJDUMP) -d -Mnumeric -Mno-aliases $<

clean:
	rm -f crt0.o axpy.o main.o axpy_bench.elf axpy_bench.bin $(IMEM_HEX)

.PHONY: all disasm clean
