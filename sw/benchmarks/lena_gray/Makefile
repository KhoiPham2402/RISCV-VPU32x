RISCV_PREFIX ?= riscv64-unknown-elf-
CC      = $(RISCV_PREFIX)gcc
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

IMEM_HEX  = $(ROOT)/rtl/imem_from_gcc.hex
DMEM_INIT = lena_dmem_init.hex

all: $(IMEM_HEX) $(DMEM_INIT)
	@echo "Build done. Run: vsim -c -do run_lena_sim.do (from project root)"

crt0.o: $(SW)/crt0.S
	$(CC) $(CFLAGS) -c -o $@ $<

lena_gray.o: lena_gray.c
	$(CC) $(CFLAGS) -c -o $@ $<

# crt0.o linked first so _start lands at address 0x000
lena_gray.elf: crt0.o lena_gray.o
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

lena_gray.bin: lena_gray.elf
	$(OBJCOPY) -O binary $< $@

$(IMEM_HEX): lena_gray.bin
	$(PYTHON) $(SW)/elf2hex_lines.py $< > $(IMEM_HEX)
	@echo "Wrote $(IMEM_HEX)"

$(DMEM_INIT): prep_lena.py
	$(PYTHON) prep_lena.py
	@echo "Wrote $(DMEM_INIT)"

disasm: lena_gray.elf
	$(OBJDUMP) -d -Mnumeric -Mno-aliases $<

clean:
	rm -f crt0.o lena_gray.o lena_gray.elf lena_gray.bin \
	      $(IMEM_HEX) $(DMEM_INIT) lena_dmem_out.hex lena_y_reference.hex

.PHONY: all disasm clean
