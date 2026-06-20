# IP Core Generation Instructions

Two IP cores must be generated in Quartus IP Catalog before synthesis.
Both go in `fpga/ip/` and their `.qip` paths must be uncommented in `sources.tcl`.

---

## 1. `dmem_bank` — 8-bit True Dual-Port SRAM (M10K)

Used by: `fpga/rtl/mem/dmem_qip_wrapper.sv`

**Steps in Quartus IP Catalog:**
1. IP Catalog → Basic Functions → On Chip Memory → **RAM: 2-PORT**
2. Settings:
   - Mode: **With two read/write ports** (True Dual-Port)
   - Width: **8 bits**
   - Depth: **16384 words**
   - Byte enable: **NO** (per-bank wren used instead)
   - Read-during-write: **OLD_DATA** (both ports)
   - Output: **Registered** (1-cycle latency, both ports)
   - Clock: **Single clock**
   - Target: **M10K**
   - Output module name: **`dmem_bank`**
3. Save to: `fpga/ip/dmem_bank/dmem_bank.qip`
4. Uncomment in `sources.tcl`:
   ```tcl
   set_global_assignment -name QIP_FILE [file join $RTL_ROOT ip dmem_bank dmem_bank.qip]
   ```

**Resource estimate:** 16 M10K blocks (4 banks × 4096-word depth per M10K at 8-bit width)

---

## 2. `pll` — PLL (50 MHz → 25 MHz pixel clock)

Used by: `fpga/rtl/top/riscv_vpu_top_fpga.sv` (`pclk` input port)

**Steps in Quartus IP Catalog:**
1. IP Catalog → Basic Functions → Clocks; PLLs and Resets → **ALTPLL**
2. Settings:
   - Input clock: **50.000 MHz**
   - Output c0: **50.000 MHz** (optional — can use CLOCK_50 directly as i_clk)
   - Output c1: **25.175 MHz** (pixel clock for 640×480@60Hz)
     - If 25.175 is not achievable exactly: use **25.000 MHz** (close enough for display)
   - Output module name: **`pll`**
3. Save to: `fpga/ip/pll/pll.qip`
4. Instantiate in top or use wrapper:
   ```systemverilog
   pll u_pll (
       .inclk0(CLOCK_50),  // 50 MHz board clock
       .c0    (i_clk),     // 50 MHz system clock
       .c1    (pclk)       // 25 MHz pixel clock
   );
   ```
5. Uncomment in `sources.tcl`:
   ```tcl
   set_global_assignment -name QIP_FILE [file join $RTL_ROOT ip pll pll.qip]
   ```

---

## 3. IMEM Initialization

`imem_sync.sv` uses `$readmemh(...)` for simulation, but Quartus **ignores** `$readmemh` at synthesis.
The RTL already has `(* ram_init_file = "uart_lena.mif" *)` on the memory declaration — Quartus
reads this attribute and initializes the inferred M10K at programming time.

**Required step before synthesis:**

1. Build the firmware hex:
   ```bash
   cd fpga/sw && make uart_lena.hex
   ```
2. Convert to MIF (place in Quartus project root, same directory as `riscv_vpu.qpf`):
   ```bash
   python fpga/sw/hex2mif.py uart_lena.hex fpga/uart_lena.mif
   ```
3. Synthesize — Quartus will pick up `uart_lena.mif` automatically via the `ram_init_file` attribute.

**Alternative (no rebuild needed):** After programming the bitstream, use Quartus
In-System Memory Content Editor (Tools → In-System Memory Content Editor) to write
firmware directly via JTAG without recompiling.

The firmware assembly source is in `fpga/sw/uart_lena.S`.
Build with: `cd fpga/sw && make uart_lena.hex`
