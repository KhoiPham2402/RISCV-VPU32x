# MSYS2 mingw64: pacman -S mingw-w64-x86_64-riscv64-unknown-elf-gcc
#   rồi: make RISCV_PREFIX=riscv64-unknown-elf-
# (đặt PATH=/mingw64/bin hoặc chạy từ mingw64 shell)

RISCV_PREFIX ?= riscv64-unknown-elf-
CC      = $(RISCV_PREFIX)gcc

# ── Windows GCC.exe temp dir fix ──────────────────────────────────────────────
# GCC.exe ignores MSYS2 /tmp and uses Windows TEMP/TMP; ensure they are set.
_mktmp  := $(shell mkdir -p ../tmp 2>/dev/null)
_wintemp := $(shell cd ../tmp && pwd -W 2>/dev/null)
ifeq ($(strip $(_wintemp)),)
  _wintemp := $(shell cd ../tmp && pwd)
endif
export TEMP := $(_wintemp)
export TMP  := $(_wintemp)
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
          -pipe -Wall -Wextra -nostdlib -nostartfiles
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
	rm -f uart_lena.o   uart_lena.elf   uart_lena.bin   ../uart_lena.hex
	rm -f uart_lena_test.o uart_lena_test.elf uart_lena_test.bin ../uart_lena_test.hex
	rm -f uart_hex_test.o uart_hex_test.elf uart_hex_test.bin ../uart_hex_test.hex

# ── UART firmware targets ─────────────────────────────────────────────────────
# Produces uart_lena.hex / uart_lena_test.hex in the project root (../),
# alongside imem.hex used by other sims.
# Run_uart_sim.do copies uart_lena_test.hex → imem.hex automatically.

uart_lena.hex: uart_lena.S link.ld Makefile
	$(CC) $(CFLAGS) -c -o uart_lena.o $<
	$(CC) $(CFLAGS) $(LDFLAGS) -o uart_lena.elf uart_lena.o
	$(OBJCOPY) -O binary uart_lena.elf uart_lena.bin
	$(PYTHON) elf2hex_lines.py uart_lena.bin > ../uart_lena.hex
	@rm -f uart_lena.o uart_lena.elf uart_lena.bin
	@echo "Wrote ../uart_lena.hex"

uart_lena_test.hex: uart_lena_test.S link.ld Makefile
	$(CC) $(CFLAGS) -c -o uart_lena_test.o $<
	$(CC) $(CFLAGS) $(LDFLAGS) -o uart_lena_test.elf uart_lena_test.o
	$(OBJCOPY) -O binary uart_lena_test.elf uart_lena_test.bin
	$(PYTHON) elf2hex_lines.py uart_lena_test.bin > ../uart_lena_test.hex
	@rm -f uart_lena_test.o uart_lena_test.elf uart_lena_test.bin
	@echo "Wrote ../uart_lena_test.hex"

# ── UART HEX-display test firmware ───────────────────────────────────────────
# Receives 1 byte via UART → shows nibbles on HEX1:HEX0 + binary on LEDR → echo.
# After building, also overwrites uart_lena.hex/.mif so Quartus picks it up.
uart_hex_test: uart_hex_test.S link.ld Makefile
	$(CC) $(CFLAGS) -c -o uart_hex_test.o $<
	$(CC) $(CFLAGS) $(LDFLAGS) -o uart_hex_test.elf uart_hex_test.o
	$(OBJCOPY) -O binary uart_hex_test.elf uart_hex_test.bin
	$(PYTHON) elf2hex_lines.py uart_hex_test.bin > ../uart_hex_test.hex
	@cp ../uart_hex_test.hex ../uart_lena.hex
	$(PYTHON) hex2mif.py ../uart_lena.hex ../uart_lena.mif
	@rm -f uart_hex_test.o uart_hex_test.elf uart_hex_test.bin
	@echo "Wrote ../uart_hex_test.hex  (also copied → uart_lena.hex + uart_lena.mif)"
	@echo "Next: recompile in Quartus (Assembler-only) then program the board."

QUARTUS_DIR := C:/CapstoneProject2/FPGA/riscv_vpu

# ── DMEM-init demo: no UART, image pre-loaded in DMEM via MIF ─────────────────
# 1. Assemble dmem_lena.S → IMEM hex
# 2. Split hex → 4 IMEM MIF files  (imem_b0-b3.mif) in Quartus project dir
# 3. Generate 4 DMEM MIF files     (dmem_b0-b3.mif) from lena_dmem_init.hex
# After running: full recompile in Quartus → program .sof → VGA shows image.
vga_lena_y:
	$(CC) $(CFLAGS) -c -o vga_lena_y.o vga_lena_y.S
	$(CC) $(CFLAGS) $(LDFLAGS) -o vga_lena_y.elf vga_lena_y.o
	$(OBJCOPY) -O binary vga_lena_y.elf vga_lena_y.bin
	$(PYTHON) elf2hex_lines.py vga_lena_y.bin > ../vga_lena_y.hex
	@rm -f vga_lena_y.o vga_lena_y.elf vga_lena_y.bin
	@echo "Wrote ../vga_lena_y.hex"
	$(PYTHON) ../../sw/make_imem_mifs.py ../vga_lena_y.hex 2048 "$(QUARTUS_DIR)"
	$(PYTHON) ../gen_lena_y_mif.py
	@echo "Done. Full recompile Quartus then program."

dmem_lena:
	$(CC) $(CFLAGS) -c -o dmem_lena.o dmem_lena.S
	$(CC) $(CFLAGS) $(LDFLAGS) -o dmem_lena.elf dmem_lena.o
	$(OBJCOPY) -O binary dmem_lena.elf dmem_lena.bin
	$(PYTHON) elf2hex_lines.py dmem_lena.bin > ../dmem_lena.hex
	@rm -f dmem_lena.o dmem_lena.elf dmem_lena.bin
	@echo "Wrote ../dmem_lena.hex"
	$(PYTHON) ../../sw/make_imem_mifs.py ../dmem_lena.hex 2048 "$(QUARTUS_DIR)"
	$(PYTHON) ../gen_dmem_mif.py
	@echo "Done. Recompile Quartus (full compile) and program to board."

.PHONY: all disasm clean uart_lena.hex uart_lena_test.hex uart_hex_test dmem_lena vga_lena_y
