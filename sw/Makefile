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
	rm -f uart_echo.o   uart_echo.elf   uart_echo.bin   ../uart_echo.hex

# ── IMEM MIF generation (4×8-bit Quartus altsyncram ROM init files) ──────────
# Run after building any firmware hex to refresh imem_b0..b3.mif in fpga/.
imem_mifs: ../fpga/uart_lena.hex
	$(PYTHON) make_imem_mifs.py ../fpga/uart_lena.hex 2048 ../fpga/
	@echo "Wrote fpga/imem_b0..b3.mif"

.PHONY: imem_mifs

# ── UART firmware targets ─────────────────────────────────────────────────────
# Produces uart_lena.hex in the project root and fpga/ then regenerates MIFs.
# Run_uart_sim.do copies uart_lena.hex → fpga/uart_lena.hex automatically.

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

uart_loopback.hex: uart_loopback.S link.ld Makefile
	$(CC) $(CFLAGS) -c -o uart_loopback.o $<
	$(CC) $(CFLAGS) $(LDFLAGS) -o uart_loopback.elf uart_loopback.o
	$(OBJCOPY) -O binary uart_loopback.elf uart_loopback.bin
	$(PYTHON) elf2hex_lines.py uart_loopback.bin > ../uart_loopback.hex
	@rm -f uart_loopback.o uart_loopback.elf uart_loopback.bin
	@echo "Wrote ../uart_loopback.hex"

uart_lena_mini.hex: uart_lena_mini.S link.ld Makefile
	$(CC) $(CFLAGS) -c -o uart_lena_mini.o $<
	$(CC) $(CFLAGS) $(LDFLAGS) -o uart_lena_mini.elf uart_lena_mini.o
	$(OBJCOPY) -O binary uart_lena_mini.elf uart_lena_mini.bin
	$(PYTHON) elf2hex_lines.py uart_lena_mini.bin > ../uart_lena_mini.hex
	@rm -f uart_lena_mini.o uart_lena_mini.elf uart_lena_mini.bin
	@echo "Wrote ../uart_lena_mini.hex"

uart_echo.hex: uart_echo.S link.ld Makefile
	$(CC) $(CFLAGS) -c -o uart_echo.o $<
	$(CC) $(CFLAGS) $(LDFLAGS) -o uart_echo.elf uart_echo.o
	$(OBJCOPY) -O binary uart_echo.elf uart_echo.bin
	$(PYTHON) elf2hex_lines.py uart_echo.bin > ../uart_echo.hex
	@rm -f uart_echo.o uart_echo.elf uart_echo.bin
	@echo "Wrote ../uart_echo.hex"

vga_test.hex: vga_test.S link.ld Makefile
	$(CC) $(CFLAGS) -c -o vga_test.o $<
	$(CC) $(CFLAGS) $(LDFLAGS) -o vga_test.elf vga_test.o
	$(OBJCOPY) -O binary vga_test.elf vga_test.bin
	$(PYTHON) elf2hex_lines.py vga_test.bin > ../vga_test.hex
	$(PYTHON) make_imem_mifs.py ../vga_test.hex 2048 ../fpga/
	@rm -f vga_test.o vga_test.bin
	@echo "Wrote ../vga_test.hex + fpga/imem_b0..b3.mif"

.PHONY: all disasm clean uart_lena.hex uart_lena_test.hex uart_loopback.hex uart_lena_mini.hex uart_echo.hex vga_test.hex
