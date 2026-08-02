# Build sobel_imem.hex from sobel.c using the real riscv64-unknown-elf-gcc
# toolchain (MSYS2: pacman -S mingw-w64-x86_64-riscv64-unknown-elf-gcc).
# Modeled on sw/benchmarks/lena_gray/Makefile, but writes sobel_imem.hex
# directly next to the source (lena_gray's Makefile writes to
# rtl/imem_from_gcc.hex and needs a manual copy into lena_imem.hex before
# vsim picks it up — that foot-gun is deliberately not repeated here).
#
# Run: make            (builds sobel_imem.hex + runs the check-isa guard)
#      make dmem       (runs prep_sobel.py -> sobel_dmem_init.hex + PNGs)
#      make disasm     to inspect the compiled instructions

RISCV_PREFIX ?= riscv64-unknown-elf-
CC      = $(RISCV_PREFIX)gcc

# ── Windows GCC.exe temp dir fix ──────────────────────────────────────────────
# GCC.exe ignores MSYS2 /tmp and uses Windows TEMP/TMP; ensure they are set.
# (Same workaround as sw/Makefile / sw/benchmarks/{axpy,matmul}/Makefile.)
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

MARCH   = rv32im_zicsr_zve32x_zvl128b
MABI    = ilp32
CFLAGS  = -march=$(MARCH) -mabi=$(MABI) -mcmodel=medlow \
          -Os -ffreestanding -fno-builtin -fno-pic -fno-pie \
          -nostdlib -nostartfiles \
          -Wall -Wextra

LDFLAGS = -Wl,-T$(SW)/link.ld -Wl,--build-id=none

IMEM_HEX  = sobel_imem.hex
DMEM_INIT = sobel_dmem_init.hex

all: $(IMEM_HEX) check-isa
	@echo "Build done. Wrote $(IMEM_HEX). Run 'make dmem' if sobel_dmem_init.hex is missing/stale."

dmem: $(DMEM_INIT)

crt0.o: $(SW)/crt0.S
	$(CC) $(CFLAGS) -c -o $@ $<

sobel.o: sobel.c
	$(CC) $(CFLAGS) -c -o $@ $<

# crt0.o linked first so _start lands at address 0x000
sobel.elf: crt0.o sobel.o
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

sobel.bin: sobel.elf
	$(OBJCOPY) -O binary $< $@

$(IMEM_HEX): sobel.bin
	$(PYTHON) $(SW)/elf2hex_lines.py $< > $(IMEM_HEX)
	@echo "Wrote $(IMEM_HEX)"

$(DMEM_INIT): prep_sobel.py
	$(PYTHON) prep_sobel.py
	@echo "Wrote $(DMEM_INIT)"

# Safety net for project issue #24 (vsll/vsrl/vsra funct6 mismatch) and the
# scalar RV32M squash (issue #20, fixed 2026-08-01): fail the build instead
# of silently producing a binary that will compute wrong results on this RTL.
check-isa: sobel.elf
	@$(OBJDUMP) -d -Mnumeric -Mno-aliases $< > sobel.dis
	@if grep -nE '\b(vsll|vsrl|vsra|vmacc|vnmsac|vslide[0-9a-z]*|vnclip|vnsrl|vnsra|vrgather|vmv\.x\.s)\b' sobel.dis; then \
	   echo "check-isa: FAIL - forbidden vector instruction (unsupported/mis-encoded on this RTL, see issue #24/#13)"; exit 1; fi
	@if grep -qE '^\s+[0-9a-f]+:.*[[:space:]](mul|mulh|mulhu|mulhsu|div|divu|rem|remu)([[:space:]]|$$)' sobel.dis; then \
	   echo "check-isa: FAIL - scalar RV32M instruction (squashed as illegal on this RTL, see issue #20)"; exit 1; fi
	@echo "check-isa: OK"

disasm: sobel.elf
	$(OBJDUMP) -d -Mnumeric -Mno-aliases $<

clean:
	rm -f crt0.o sobel.o sobel.elf sobel.bin sobel.dis $(IMEM_HEX)
	@echo "Note: $(DMEM_INIT) and generated PNGs are NOT removed by clean; rerun 'make dmem' to refresh them."

.PHONY: all dmem disasm check-isa clean
