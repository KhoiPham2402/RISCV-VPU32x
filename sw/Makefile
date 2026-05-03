# MSYS2 mingw64: pacman -S mingw-w64-x86_64-riscv64-unknown-elf-gcc
#   rồi: make RISCV_PREFIX=riscv64-unknown-elf-
# (đặt PATH=/mingw64/bin hoặc chạy từ mingw64 shell)

RISCV_PREFIX ?= riscv64-unknown-elf-
CC      = $(RISCV_PREFIX)gcc
OBJCOPY = $(RISCV_PREFIX)objcopy
OBJDUMP = $(RISCV_PREFIX)objdump
# Windows: thường là `python`; Linux: `python3`. Ghi đè: make PYTHON=python3
PYTHON  ?= python

SRC     ?= test_alu.S
OBJ     = $(SRC:.S=.o)
ELF     = $(SRC:.S=.elf)
BIN     = $(SRC:.S=.bin)
HEX_OUT = ../rtl/imem_from_gcc.hex

MARCH  = rv32im_zicsr_zve32x_zvl128b
MABI   = ilp32

CFLAGS  = -march=$(MARCH) -mabi=$(MABI) -mcmodel=medlow \
          -Os -ffreestanding -fno-builtin -fno-pic -fno-pie \
          -Wall -Wextra -nostdlib -nostartfiles
LDFLAGS = -Wl,-Tlink.ld -Wl,--build-id=none

all: $(HEX_OUT)

# Link trực tiếp từ .S sang .elf có thể tạo ELF không có PT_LOAD (binutils 2.44);
# assemble .o rồi link ổn định hơn.
$(OBJ): $(SRC) Makefile
	$(CC) $(CFLAGS) -c -o $@ $(SRC)

$(ELF): $(OBJ) link.ld Makefile
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJ)

# Một lệnh 32-bit mỗi dòng (giống counter.hex) — binary + Python
$(HEX_OUT): $(ELF) elf2hex_lines.py
	$(OBJCOPY) -O binary $< $(BIN)
	$(PYTHON) elf2hex_lines.py $(BIN) > $@
	@rm -f $(BIN)
	@echo "Wrote $(HEX_OUT) (1 word / line)"

disasm: $(ELF)
	$(OBJDUMP) -d -Mnumeric -Mno-aliases $<

clean:
	rm -f $(OBJ) $(ELF) $(BIN) $(HEX_OUT)

.PHONY: all disasm clean
