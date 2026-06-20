# RISC-V VPU — rv32im_zicsr_zve32x_zvl128b

A synthesisable RISC-V scalar core paired with a Zve32x Vector Processing Unit (VPU), targeting **ASIC tapeout** and validated on a **DE10-Standard FPGA board**.

**ISA:** `rv32im_zicsr_zve32x_zvl128b` | **VLEN:** 128 bit | **SEW:** 8 / 16 / 32 | **LMUL:** 1 / 2 / 4 / 8

---

## Results

| Benchmark | Scalar | VPU | Speedup |
|-----------|-------:|----:|:-------:|
| AXPY N=16 (SEW=32) | 315 cy | 221 cy | **1.43×** |
| MatMul 4×4 int32 | ~858 cy | 317 cy | **~2.7×** |
| Lena BT.601 128×128 (16 384 px, SEW=8) | ~295 K cy | 34 828 cy | **8.5×** |

Instruction regression: **172 / 172 PASS**  
Lena grayscale: **16 384 / 16 384 pixels correct, max\_err = 0**  
FPGA: **Lena Y-channel displayed on VGA monitor (hardware verified)**

---

## Architecture

```
de10_standard_top (DE10-Standard board ports)
└── riscv_vpu_top_fpga
    ├── pipelined_vpu          ← RV32IM 5-stage (IF/ID/EX/MEM/WB)
    │   ├── control_unit         load-use stall, EX→MEM→WB forwarding
    │   ├── alu, regfile, imem_sync, dmem_qip_wrapper
    │   └── VPU dispatch port  → vproc_system_wrapper
    ├── vproc_system_wrapper   ← VPU boundary (VLEN=128, single lane)
    │   ├── vproc_vdecoder       decode → 48-bit ctrl_bus
    │   ├── vproc_fsm            multi-cycle execution controller
    │   ├── vproc_vcsr           vl / vtype / vlenb CSRs
    │   ├── vproc_vregfile       32 × 128-bit VRF
    │   ├── vproc_vec_lsu        vector load / store
    │   ├── vproc_fifo           instruction queue
    │   └── vproc_processor_lane ← single execution lane
    │       ├── vproc_adder        VADD / VSUB / VRSUB
    │       ├── vproc_mul          VMUL / VMULH / VMULHU / VMULHSU
    │       ├── vproc_shifter      VSLL / VSRL / VSRA
    │       ├── vproc_logic        VAND / VOR / VXOR
    │       ├── vproc_compare      VMSEQ … VMSGT
    │       ├── vproc_minmax       VMIN / VMINU / VMAX / VMAXU
    │       └── vproc_reduction    VREDSUM / VREDMAX / VREDMIN / …
    ├── uart                   ← 8N1 TL-UL slave @ 0xFF000000
    └── vga_ctrl               ← 640×480@60Hz → ADV7123 DAC
```

### Memory map

| Range | Size | Contents |
|-------|------|----------|
| `0x0000_0000 – 0x0000_1FFF` | 8 KB | IMEM (read-only, Harvard) |
| `0x0000_0000 – 0x0000_FFFF` | 64 KB | DMEM (scalar + VLSU dual-port) |
| `0xFF00_0000 – 0xFF00_00FF` | 256 B | UART MMIO (TileLink-UL) |

---

## Directory Structure

```
riscv_vpu/
├── fpga/                      ← FPGA implementation (DE10-Standard) — LATEST RTL
│   ├── rtl/
│   │   ├── top/               riscv_vpu_top_fpga.sv, de10_standard_top.sv
│   │   ├── pipeline/          5-stage pipelined_vpu.sv + support cells
│   │   ├── vpu/               24 × vproc_*.sv (VPU modules)
│   │   ├── mem/               dmem_qip_wrapper.sv, lena_rom.sv
│   │   ├── uart/              uart.sv (TileLink-UL slave)
│   │   ├── bus/               tl_pkg.sv, tl_ul_xbar.sv, tl_ul_dmem_adapter.sv
│   │   ├── vga/               vga_ctrl.sv
│   │   └── hdmi/              adv7513_cfg.sv, hdmi_ctrl.sv, i2c_master.sv, vga_timing.sv
│   ├── ip/                    Behavioral stubs for Quartus IP (pll.sv, dmem_bank*.sv, imem_b*.sv)
│   ├── sim/                   FPGA-specific .do simulation scripts
│   ├── sw/                    FPGA firmware (dmem_lena.S, uart_lena.S, vga_lena_y.S)
│   ├── riscv_vpu.qpf/.qsf    Quartus project files
│   └── constraints/           timing.sdc, de10_standard_pins.tcl
│
├── rtl/                       ← Simulation RTL (mirrors fpga/rtl/vpu + legacy tops)
│   ├── riscv/                 Single-cycle core (used for standalone VPU sim)
│   ├── pipeline/              5-stage core (behavioral imem, lsu, forwarding)
│   └── vproc_*.sv             VPU modules (synced from fpga/rtl/vpu/)
│
├── bench/                     ← Testbenches
│   ├── tb_vproc_all_instr.sv  172-case Zve32x regression
│   ├── tb_lena_gray.sv        Lena 128×128 benchmark
│   ├── tb_riscv_vpu_top.sv    Top-level integration TB
│   └── tb_scalar_*.sv         Scalar benchmark harnesses
│
├── sw/                        ← Software / firmware
│   ├── Makefile               assemble → .hex (riscv64-unknown-elf-)
│   ├── test_alu.S             VPU smoke test
│   ├── uart_lena.S            Full 128×128 Lena via UART
│   └── benchmarks/
│       ├── axpy/              AXPY N=16 (VPU, C)
│       ├── matmul/            4×4 MatMul (VPU, C)
│       ├── lena_gray/         Lena BT.601 (VPU, assembly)
│       ├── scalar_axpy.S      AXPY scalar baseline
│       └── scalar_bt601.S     BT.601 scalar baseline
│
├── report/
│   ├── charts/                Benchmark comparison charts (PNG)
│   ├── gen_benchmark_charts.py
│   └── main.tex               LaTeX thesis report
│
├── run_top_sim.do             ← Top-level integration sim
├── vproc_all_instr.do         ← Zve32x regression (172 tests)
├── run_lena_sim.do            ← Lena 128×128 benchmark sim
├── run_tb_vlsu.do             ← Vector LSU test
└── BENCHMARK_REPORT.md        Scalar vs VPU analysis with evidence
```

---

## Simulation

All `.do` scripts run from the project root with ModelSim:

```bash
# Full instruction regression (172/172 Zve32x opcodes)
vsim -c -do vproc_all_instr.do

# Top-level integration (scalar core + VPU)
vsim -do run_top_sim.do

# Lena 128×128 grayscale benchmark
vsim -c -do run_lena_sim.do

# Vector LSU unit test
vsim -c -do run_tb_vlsu.do

# Scalar vs VPU benchmark comparison
vsim -c -do run_scalar_sim_batch.do
```

**Regression gate:** `vproc_all_instr.do` must pass 172/172 before any RTL change is considered complete.

---

## Software Build

```bash
cd sw
make            # assemble → ../rtl/imem_from_gcc.hex
make disasm     # disassemble ELF
make clean
```

**Toolchain:** `riscv64-unknown-elf-` with `-march=rv32im_zicsr_zve32x_zvl128b -mabi=ilp32`

The Python helper `sw/elf2hex_lines.py` converts raw binary to one 32-bit word per line for `$readmemh`.

---

## FPGA — DE10-Standard

**Toolchain:** Quartus 18.1 (Cyclone V)

```bash
# Open project
quartus fpga/riscv_vpu.qpf

# Generate Lena DMEM init files
python fpga/gen_dmem_mif.py   # RGB MIF for DMEM banks
python fpga/gen_lena_y_mif.py # Y-channel MIF (for direct VGA test)

# After compile: program .sof via Quartus Programmer
# Host UART demo (128×128 Lena via USB-UART adapter on GPIO_0):
cd fpga/host
python run_demo.py --port COM3
```

**FPGA demo modes:**

| Mode | Firmware | Description |
|------|----------|-------------|
| VGA direct | `vga_lena_y.S` | Y-channel pre-loaded via MIF, VGA immediately |
| VPU compute | `dmem_lena.S` | RGB pre-loaded, VPU runs BT.601, outputs Y to VGA |
| UART stream | `uart_lena.S` | Host streams 49152 bytes, VPU processes, VGA shows result |

**Pin assignments:** `fpga/constraints/de10_standard_pins.tcl`

---

## Design Rules (ASIC / Synthesisability)

- Synchronous active-low reset (`rst_n`) throughout
- No `initial` blocks, `$display`, or `#N` delays in `fpga/rtl/`
- Only `always_ff`, `always_comb`, `assign` — no `always @(*)`
- No latches — every `always_comb` has a full default assignment
- Widths parameterised via `VLEN`, `SEW_MAX`, `LANES` — no hardcoded slices

---

## Open Issues

| ID | Description | Priority |
|----|-------------|----------|
| #7 | Verify `vmv.v.x` decoder support | High |
| #8 | Audit reset synchronicity (`lsu.sv` async reset) | High |
| #9 | Lint pass — latches / undriven outputs | High |
| #13 | `vslide1up/down` not implemented (blocks pathfinder benchmark) | Medium |
| #14 | `CTRL_WIDTH=48` but decoder packs 49 bits — bit[48] silently dropped | High |
| #16 | `vsetivli` (immediate AVL ≤ 31) not decoded | Medium |

---

## Benchmark Evidence

| Result | Source |
|--------|--------|
| AXPY VPU 221 cy | `results/axpy/sim_log_raw.txt` (2026-04-29) |
| MatMul VPU 317 cy | `results/matmul/regression_raw.txt` (2026-04-29) |
| Lena VPU 34 828 cy | `PROJECT_STATUS.md` (2026-05-02) |
| AXPY scalar 315 cy | `bench/tb_scalar_io_detect.sv` (2026-06-03) |
| Lena scalar ~295 K cy | Analytical: 8 + 16384×18 insns (single-cycle) |
| 172/172 regression | `vproc_all_instr.do` (2026-05-01) |

Charts: [`report/charts/`](report/charts/)

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| VLEN=128, single lane | Area budget for ASIC; meets Zve32x requirement |
| Harvard architecture | Simplifies timing; no I-cache needed at this scale |
| Synchronous reset, active-low | Standard ASIC practice |
| FIFO between decoder and FSM | Allows scalar core to run ahead; hides VPU latency |
| TileLink-UL for UART | Clean bus interface; expandable to more peripherals |
| 5-stage pipeline (FPGA) | Realistic clock frequency; matches tapeout target |
