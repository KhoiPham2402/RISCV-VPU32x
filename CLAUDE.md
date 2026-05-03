# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Goal

RISC-V scalar core + Vector Processing Unit (VPU) targeting **ASIC tapeout**. The VPU implements the RVV `Zve32x` subset with VLEN=128 and a single execution lane. Every RTL decision must be tapeout-viable — no simulation-only constructs in `/rtl/`.

**ISA:** `rv32im_zicsr_zve32x_zvl128b` | **VLEN:** 128 b | **SEW:** 8/16/32 | **LMUL:** 1/2/4/8

---

## Simulation Commands

All `.do` scripts run from the project root in ModelSim. There are three vsim invocation patterns:

```bash
# Full top-level integration (scalar core + VPU)
vsim -do run_top_sim.do
# → launches work.tb_riscv_vpu_top with -voptargs=+acc
# → optional reproducible seed: vsim -voptargs=+acc +SEED=12345 work.tb_riscv_vpu_top

# VPU instruction regression (all Zve32x opcodes)
vsim -do vproc_all_instr.do
# → launches work.tb_vproc_all_instr with -voptargs=+acc

# Vector LSU test
vsim -do run_tb_vlsu.do
# → launches work.tb_vproc_vlsu with -voptargs=+acc

# VPU subsystem standalone
vsim -do vproc_run_msim_rtl_verilog.do
# → launches work.tb_vproc_system_wrapper with -voptargs=+acc

# Execution lane unit test (runs from bench/ directory)
cd bench && vsim -novopt work.tb_vproc_lane   # then: run -all; quit -f

# FIFO unit test (batch mode, from bench/)
cd bench && vsim -c work.tb_vproc_fifo -do "run -all; quit -f"
```

**Regression gate:** run `vproc_all_instr.do` and `run_top_sim.do` before any RTL change is considered complete. Output prints `[PASS]`/`[FAIL]` per test followed by a `TEST SUMMARY` line.

---

## Software Build

```bash
cd sw
make          # assemble test_alu.S → ../rtl/imem_from_gcc.hex
make disasm   # disassemble ELF (numeric registers, no aliases)
make clean
```

Toolchain prefix: `riscv64-unknown-elf-` (overridable via `RISCV_PREFIX=`).
Compiler flags: `-march=rv32im_zicsr_zve32x_zvl128b -mabi=ilp32 -mcmodel=medlow -Os -ffreestanding -nostdlib`.
The Python step `elf2hex_lines.py <bin>` converts the raw binary to one 32-bit word per line; output is loaded by `imem.sv` via `$readmemh`.

**Memory map** (from `sw/link.ld`):
- IMEM: `0x00000000`, 8 KB, `rx` — `.text` + `.rodata` only (Harvard architecture).
- DMEM is a separate address space; `vproc_vec_lsu` uses `addr[10:2]` as the word index.

---

## Architecture

```
riscv_vpu_top                         ← no parameters; fixed top-level
├── riscv/single_cycle.sv             ← RV32IM scalar core
│   └── alu, control_unit, lsu, regfile, imem (+ barrel shifter cells)
└── vproc_system_wrapper.sv           ← VPU boundary (parameterised)
    ├── vproc_vdecoder.sv             ← decode: 32-bit insn → 48-bit ctrl_bus
    ├── vproc_fsm.sv                  ← multi-cycle execution FSM
    ├── vproc_vcsr.sv                 ← vl / vtype / vlenb CSRs
    ├── vproc_cfg_encoder.sv          ← vtype encoding (vsetvl/vsetvli)
    ├── vproc_vregfile.sv             ← 32 × 128-bit VRF
    ├── vproc_vec_lsu.sv              ← vector load/store
    ├── vproc_fifo.sv                 ← instruction queue between decode & exec
    ├── vproc_vrf_addr_gen.sv         ← VRF read/write address generation
    ├── vproc_scalar_expand.sv        ← broadcast scalar rs1 to vector width
    ├── vproc_mask_enable.sv          ← per-element mask gating (vm=0)
    ├── vproc_merge_unit.sv           ← VMERGE / VMV
    ├── vproc_mux_cells.sv            ← result selection mux tree
    ├── vproc_cycle_counter.sv        ← performance counter output
    └── vproc_processor_lane.sv       ← single execution lane
        ├── vproc_adder.sv            ← VADD/VSUB/VRSUB
        ├── vproc_mul.sv              ← VMUL/VMULH/VMULHU/VMULHSU
        ├── vproc_shifter.sv          ← VSLL/VSRL/VSRA
        ├── vproc_logic.sv            ← VAND/VOR/VXOR
        ├── vproc_compare.sv          ← VMSEQ/VMSNE/VMSLT/VMSLTU/VMSLE/VMSLEU/VMSGTU/VMSGT
        ├── vproc_minmax.sv           ← VMIN/VMINU/VMAX/VMAXU
        └── vproc_reduction.sv        ← VREDSUM/VREDMAX/VREDMIN/VREDMAXU/VREDMINU
```

### FSM states (`vproc_fsm.sv`)

```systemverilog
typedef enum logic [3:0] {
    ST_IDLE           = 4'd0,   // waiting for instruction
    ST_CONFIG         = 4'd1,   // vsetvl/vsetvli (1 cycle)
    ST_EXEC           = 4'd2,   // normal vector op
    ST_WIDENL         = 4'd3,   // widening — low half
    ST_WIDENH         = 4'd4,   // widening — high half
    ST_MASKING        = 4'd5,   // mask-generating instruction
    ST_FINAL_MASKING  = 4'd6,   // commit mask result
    ST_REDUCTION      = 4'd7,   // accumulation loop
    ST_REDUCTION_DONE = 4'd8    // write reduction result
} fsm_state_t;
```

### Decoder ctrl_bus layout (`vproc_vdecoder.sv`, `CTRL_WIDTH=48`)

| Bits | Field | Meaning |
|------|-------|---------|
| `[4:0]` | `vs1_addr` | Source register 1 |
| `[9:5]` | `vs2_addr` | Source register 2 |
| `[14:10]` | `vd_addr` | Destination register |
| `[20:15]` | `funct6` | Instruction funct6 |
| `[21]` | `is_widen` | Widening operation |
| `[22]` | `is_unsigned_vs1` | vs1 treated as unsigned |
| `[23]` | `is_unsigned_vs2` | vs2 treated as unsigned |
| `[24]` | `is_subtraction` | Subtract (negate adder) |
| `[25]` | `is_immediate` | Use zimm/imm operand |
| `[26]` | `is_rs1` | Use scalar rs1 |
| `[27]` | `is_mulh` | MUL high-half |
| `[28]` | `is_config` | vsetvl/vsetvli |
| `[29]` | `is_vector` | OP-V opcode |
| `[30]` | `cfg_is_vsetvli` | 1=vsetvli, 0=vsetvl |
| `[31]` | `vm` | Mask bit (insn[25]) |
| `[39:32]` | `vtype_enc` | `{vma,vta,vsew[2:0],vlmul[2:0]}` |
| `[40]` | `is_carry` | vadc/vsbc |
| `[41]` | `is_mask_carry` | vmadc/vmsbc |
| `[42]` | `is_masking` | Mask-generating instruction |
| `[43]` | `is_final_masking` | Needs ST_FINAL_MASKING phase |
| `[44]` | `is_reverse_sub` | vrsub (swap operands) |
| `[45]` | `minmax_is_min` | 1=min, 0=max |
| `[46]` | `minmax_is_unsign` | 1=unsigned comparison |
| `[47]` | `is_reduction` | vred* instruction |

---

## ASIC Design Rules

### Synthesizability
- No `initial` blocks, `$display`/`$time`, or `#N` delays in `/rtl/`.
- Use only `always_ff`, `always_comb`, `assign`. Never `always @(*)` in new code.
- No latches — every `always_comb` must have a default assignment covering all outputs.
- Every register must be initialized in reset. Reset is **synchronous, active-low (`rst_n`)** throughout.

### Timing & Structure
- One flip-flop per `always_ff` block. No combinational loops.
- Mux trees deeper than 4:1 must be pipelined or restructured.
- Prefer one-hot FSM encoding unless decided otherwise.

### Area / Power
- No computation that duplicates logic already available upstream.
- Gating enables (`*_en`) required on VRF and LSU data-path registers for clock-gating inference.

### Interfaces
- All ports: `logic` type. Naming: `clk`, `rst_n`, `*_i` inputs, `*_o` outputs.
- Widths that depend on `VLEN`, `SEW`, or `LMUL` must be parameterised — no hardcoded bit slices.
- `VLEN`, `SEW_MAX`, `LANES` are top-level parameters; propagate them; don't override at instantiation without justification.

---

## Code Style

- `UPPER_SNAKE` — parameters / localparams. `lower_snake` — signals. `CamelCase` — typedefs/structs.
- `typedef enum logic [N:0]` for all FSM state types.
- `struct packed` for instruction decode fields (avoids bit-slice errors).
- `localparam` for constants derived from parameters; no magic numbers in logic.
- Comments only when the **why** is non-obvious (microarchitectural constraint, spec deviation, synthesis workaround). Never restate what the code says.
- One module per file; filename = module name. Testbenches in `/bench/`, never in `/rtl/`.

---

## Workflow

**Adding a functional unit:**
1. Create `rtl/vproc_<name>.sv` with a parameterised interface.
2. Add `bench/tb_vproc_<name>.sv` with directed corner-case tests.
3. Instantiate into `vproc_processor_lane.sv` or the appropriate parent.
4. Add a `.do` entry or extend an existing testbench.

**Modifying the decoder (`vproc_vdecoder.sv`):**
- Cross-reference RVV spec (Zve32x subset) for encoding.
- Illegal instructions must assert a fault signal — no silent wrong-result behaviour.
- The 48-bit `ctrl_bus` layout is the contract between decoder and FSM/lane; changing bit positions requires updating all consumers.

**After any RTL change:** update [PROJECT_STATUS.md](PROJECT_STATUS.md) if it affects architecture, interfaces, or milestone state.

---

## Tapeout Checklist

- [ ] Lint-clean: no latches, no undriven outputs
- [ ] Synchronous active-low reset verified throughout hierarchy
- [ ] No X-propagation paths in simulation
- [ ] All widths parameterised — no hardcoded VLEN/SEW/LMUL bit slices
- [ ] Clock-gating enables on VRF and LSU data paths
- [ ] Full instruction regression passing (`vproc_all_instr.do`)
- [ ] Synthesis clean (Yosys or DC)
- [ ] Static timing analysis at target frequency
- [ ] Formal equivalence RTL ↔ gate-level netlist
- [ ] DRC / LVS clean on final GDS
- [ ] Power estimate within budget
