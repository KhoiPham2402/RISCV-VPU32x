# Build fwd_hazard_imem.hex from fwd_hazard.S using the real
# riscv64-unknown-elf-gcc toolchain. No crt0/link.ld needed — the source
# defines its own self-contained _start at address 0x0 and ends in a
# `j done` self-loop, same done-marker convention every other testbench in
# this project (fpga/bench/tb_*.sv) already detects.
#
# Run: make    (from this directory)

RISCV_PREFIX ?= riscv64-unknown-elf-
CC      = $(RISCV_PREFIX)gcc

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

SW = ../../../sw

MARCH  = rv32im_zicsr_zve32x_zvl128b
MABI   = ilp32
CFLAGS = -march=$(MARCH) -mabi=$(MABI) -mcmodel=medlow \
         -Os -ffreestanding -fno-builtin -fno-pic -fno-pie \
         -nostdlib -nostartfiles

all: fwd_hazard_imem.hex

fwd_hazard.o: fwd_hazard.S
	$(CC) $(CFLAGS) -c -o $@ $<

fwd_hazard.elf: fwd_hazard.o
	$(CC) $(CFLAGS) -Wl,-Ttext=0x0 -Wl,--build-id=none -o $@ $<

fwd_hazard.bin: fwd_hazard.elf
	$(OBJCOPY) -O binary $< $@

fwd_hazard_imem.hex: fwd_hazard.bin
	$(PYTHON) $(SW)/elf2hex_lines.py $< > $@
	@echo "Wrote fwd_hazard_imem.hex"

disasm: fwd_hazard.elf
	$(OBJDUMP) -d -Mnumeric -Mno-aliases $<

clean:
	rm -f fwd_hazard.o fwd_hazard.elf fwd_hazard.bin fwd_hazard_imem.hex

.PHONY: all disasm clean
