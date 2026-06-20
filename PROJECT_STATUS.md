# PROJECT_STATUS.md — RISC-V VPU

> **Rule:** Update this file after every architectural change, interface freeze, or milestone. Date format: YYYY-MM-DD.

---

## Current Phase

**Phase:** FPGA Board Demo — VGA display working; RGB→grayscale pipeline debugged & fixed; awaiting full recompile for hardware validation
**Target:** ASIC Tapeout (primary) / DE10-Standard demo board (FPGA validation)

**Last session (2026-05-31):**
- VGA output confirmed working on DE10-Standard with pre-loaded Lena Y channel
- Found & fixed VPU VLSU CSR stall bug (see Issue #17 + Change Log)
- Simulation: RGB→grayscale PASS 4096/4096 words after fix
- Next step: Full Quartus recompile → program .sof → hardware verify RGB→grayscale

---

## Milestone Tracker

| Milestone | Status | Notes |
|-----------|--------|-------|
| Scalar RISC-V core (RV32IM) | ✅ Done | `rtl/riscv/single_cycle.sv` |
| Vector decoder (Zve32x subset) | ✅ Done | `rtl/vproc_vdecoder.sv` |
| Vector register file (32×128b) | ✅ Done | `rtl/vproc_vregfile.sv` |
| Execution lane — ALU ops | ✅ Done | adder, logic, compare, minmax |
| Execution lane — MUL | ✅ Done | `rtl/vproc_mul.sv` |
| Execution lane — SHIFT | ✅ Done | `rtl/vproc_shifter.sv` |
| Reduction unit | ✅ Done | `rtl/vproc_reduction.sv` |
| Vector LSU | ✅ Done | `rtl/vproc_vec_lsu.sv` |
| Mask support (vm=0) | ✅ Done | `rtl/vproc_mask_enable.sv` |
| FSM execution control | ✅ Done | `rtl/vproc_fsm.sv` |
| VPU–CPU integration (single-cycle) | ✅ Done | `rtl/riscv_vpu_top.sv` |
| Full instruction regression | ✅ Done | 172/172 PASS (2026-05-01) |
| 5-stage pipelined scalar core | ✅ Done | `rtl/pipeline/pipelined_vpu.sv` — load-use stall, EX/MEM/WB forwarding, VPU dispatch |
| Sync IMEM + DMEM | ✅ Done | `rtl/pipeline/imem_sync.sv`, `rtl_trial/mem/dmem_sync.sv` — 1-cycle latency, byte-enable, VLSU port |
| UART 8N1 TL-UL slave | ✅ Done | `rtl_trial/uart/uart.sv` — RX/TX FIFO×8, 16× oversampling, baud configurable |
| UART top-level integration (v4) | ✅ Done | `rtl/riscv_vpu_top_v4.sv` — pipelined core + VPU + UART @ 0xFF000000 |
| UART firmware — smoke test (16 px) | ✅ Done | `sw/uart_lena_test.S` — 48-byte RX, 1 VPU iter, ACK 0xAA; compiled 46 insns |
| UART firmware — full Lena (128×128) | ✅ Done | `sw/uart_lena.S` — 49152-byte RX, 1024 VPU iters, ACK 0xAA; compiled 53 insns |
| UART simulation — smoke test | ⏳ Pending | `run_uart_sim.do` + `bench/tb_uart_lena.sv` — awaiting ModelSim run |
| UART simulation — full Lena image | ⏳ Pending | `run_uart_lena_img_sim.do` + `bench/tb_uart_lena_img.sv` — awaiting ModelSim run |
| FPGA VGA output — VGA timing + controller | ✅ Done | `fpga/rtl/hdmi/vga_timing.sv` + `fpga/rtl/vga/vga_ctrl.sv` — 640×480@60Hz, reads DMEM[0xC000..] |
| FPGA VGA output — hardware verified | ✅ Done | 2026-05-31: Lena grayscale image displayed on VGA monitor via ADV7123 DAC |
| FPGA top-level (de10_standard_top) | ✅ Done | `fpga/rtl/top/de10_standard_top.sv` + `riscv_vpu_top_fpga.sv` — VGA via ADV7123, GPIO_0 for UART |
| Quartus PLL IP (25 MHz pclk) | ✅ Done | `pll.qip` — 50→25 MHz outclk_1, `locked` used as reset gate |
| Quartus DMEM bank IP (dmem_bank) | ✅ Done | `dmem_bank.qip` — TDP 8-bit M10K × 4 lanes, 16384 deep |
| DMEM MIF init (RGB pre-load) | ✅ Done | `fpga/rtl/mem/dmem_bank_b0-b3.v` wrappers + `gen_dmem_mif.py`; bypasses UART |
| FPGA compile + program DE10-Standard | ✅ Done | Quartus 18.1 — first `.sof` running, VGA display confirmed |
| RGB→grayscale FPGA demo (VPU) | 🔄 In progress | Sim PASS 4096/4096; needs full recompile after VLSU CSR stall bugfix |
| Synthesis (Yosys / DC) | ⬜ Not started | — |
| Static timing analysis | ⬜ Not started | — |
| Clock gating insertion | ⬜ Not started | — |
| Formal verification | ⬜ Not started | — |
| Place & Route | ⬜ Not started | — |
| DRC / LVS | ⬜ Not started | — |
| Tapeout GDS submission | ⬜ Not started | — |

---

## Module Interface Freeze Status

| Module | Interface Frozen | Last Changed |
|--------|-----------------|--------------|
| `riscv_vpu_top` | ⬜ No | — |
| `vproc_processor_lane` | ⬜ No | — |
| `vproc_vdecoder` | ⬜ No | — |
| `vproc_fsm` | ⬜ No | — |
| `vproc_vregfile` | ⬜ No | — |
| `vproc_vec_lsu` | ⬜ No | — |
| `vproc_adder` | ⬜ No | — |
| `vproc_mul` | ⬜ No | — |

---

## Open Issues

| ID | Description | Priority | Owner |
|----|-------------|----------|-------|
| #1 | ~~control_unit.sv: rd_wren=1 cho mọi OP-V~~ | ~~Critical~~ | ~~Fixed 2026-04-27~~ |
| #2 | ~~cycle_counter: done=1 khi idle~~ | ~~High~~ | ~~Fixed 2026-04-27~~ |
| #3 | ~~is_compare_r chỉ cover 3/8 funct6~~ | ~~High~~ | ~~Fixed 2026-04-27~~ |
| #4 | ~~VSE8/VSE16: tail bytes ghi vào DMEM (mem_be=1111 cứng)~~ | ~~High~~ | ~~Fixed 2026-04-27~~ |
| #5 | ~~VSE masked (vm=0) không có effect — VLSU thiếu vm_i port~~ | ~~High~~ | ~~Fixed 2026-04-27~~ |
| #6 | ~~is_vls_insn kích hoạt cho strided/indexed/FF instructions~~ | ~~High~~ | ~~Fixed 2026-04-27~~ |
| #7 | Verify vmv.v.x hỗ trợ trong decoder (cần cho test_reduction.S) | High | — |
| #8 | Check reset synchronicity throughout hierarchy (lsu.sv dùng async reset) | High | — |
| #9 | Audit for latches (lint pass needed) | High | — |
| #10 | Parameterize any remaining hardcoded widths | Medium | — |
| #11 | Add clock gating enables on VRF data path | Medium | — |
| #12 | Thay SRAM model combinational → synchronous khi tapeout | ASIC | — |
| #13 | vslide1up/vslide1down chưa implement — pathfinder benchmark bị blocked | Medium | — |
| #14 | CTRL_WIDTH=48 nhưng decoder pack 49 bits → bit[48] cfg_is_vsetivli bị drop silently | High | — |
| #15 | lsu.sv DMEM 64KB (16384 words) là simulation-only cho lena_gray 128×128 — cần parameterize và tách riêng config tapeout vs benchmark | High | — |
| #16 | vsetivli (immediate AVL ≤ 31) chưa decode được — workaround: dùng AVL > 31 trong C code | Medium | — |
| #17 | ~~VLSU CSR stall bug: vle8.v fires during vsetvli ST_CONFIG → csr_vl_o=0 → num_words=1 → lanes 1-3 = 0 → R contribution mất cho elements 4-15~~ | ~~Critical~~ | ~~Fixed 2026-05-31~~ |
| #18 | UART: cần USB-UART adapter (CP2102/CH340) cắm vào JP1 chân 3(RX)/4(TX)/2(GND). Built-in UART thuộc HPS, không dùng được từ FPGA fabric | Medium | Hardware issue |

---

## Key Design Decisions

| Date | Decision | Rationale |
|------|----------|-----------|
| — | VLEN=128, single lane | Area-constrained; meets Zve32x requirement |
| — | Synchronous reset, active-low | Standard ASIC practice |
| — | RV32IM scalar + Zve32x vector | Sufficient for target compute workloads |
| — | LMUL support: 1/2/4/8 | Full spec compliance for Zve32x |

---

## Simulation Results Log

| Date | Test | Result | Notes |
|------|------|--------|-------|
| 2026-04-27 | `tb_riscv_vpu_top` (bench_imgproc) | ✅ PASS | t1=0x7BA2 t2=0x7C6A t3=0x9AE2 t4=0xFF00; VRF v7=[31650,31850,39650,65280] all correct |
| 2026-04-28 | `tb_riscv_vpu_top` (bench_matmul) | ✅ PASS | t1=0x0A(10) t2=0x1A(26) t3=0x2A(42) t4=0x3A(58); 4×4 int matmul C=A*B correct in 317 cycles |
| 2026-04-28 | `tb_riscv_vpu_top` (bench_imgproc regression) | ✅ PASS | t1=0x7BA2 t2=0x7C6A t3=0x9AE2 t4=0xFF00 unchanged after hazard fixes |
| 2026-05-02 | `tb_lena_gray` (lena_gray 128×128) | ✅ PASS | 16384/16384 pixels correct, max_err=0, 34828 cycles; SEW=8, 1024 iterations, DMEM 64KB |
| 2026-05-09 | `tb_uart_lena` (UART smoke test) | ⏳ Pending | 16 pixels R=G=B=128, expected Y=127; `run_uart_sim.do` |
| 2026-05-09 | `tb_uart_lena_img` (UART 128×128 full Lena) | ⏳ Pending | 49152 bytes UART RX, full BT.601, dump DMEM → PNG; `run_uart_lena_img_sim.do` |
| 2026-05-01 | `tb_riscv_vpu_top` (bench_axpy) | ✅ PASS | y[0]=4 y[4]=16 y[8]=28 y[12]=40 correct (N=16, a=3, 221 cycles) |
| 2026-05-01 | `tb_vproc_all_instr` | ✅ 172/172 PASS | Post-decoder fix; vmul.vx/vmulh.vx now use scalar rs1 correctly |
| 2026-04-27 | `tb_vproc_all_instr` | ✅ 172/172 PASS | ALU VV/VX/VI, VRSUB, Logic, Shift, VMIN/VMAX, Compare (partial), VMULH, Widening, LMUL=2, Reductions |
| 2026-04-27 | `tb_vproc_vlsu` | ✅ 75/75 PASS | e8/e16/e32 random VL, masked store |
| — | `tb_vproc_adder` | — | — |
| — | `tb_vproc_mul` | — | — |

---

## Pipeline + UART Integration (riscv_vpu_top_v4)

**Status:** RTL complete — awaiting ModelSim simulation runs.

**Active simulation top:** `rtl/riscv_vpu_top_v4.sv`

| Component | Implementation |
|-----------|---------------|
| Scalar core | 5-stage `pipelined_vpu.sv` (IF/ID/EX/MEM/WB, load-use stall, EX→MEM→WB forwarding) |
| IMEM | `rtl/pipeline/imem_sync.sv` — synchronous 1-cycle, loaded from `imem.hex` |
| DMEM | `rtl_trial/mem/dmem_sync.sv` — 64KB, scalar + VLSU dual-port, byte-enable |
| UART | `rtl_trial/uart/uart.sv` — 8N1, 8-byte FIFOs, 16× oversampling, TL-UL slave |
| UART address | `0xFF000000` decoded inline in top-level; 1-cycle registered latency to match dmem pipeline |
| VPU | `vproc_system_wrapper.sv` — unchanged, connects via `pipelined_vpu` VPU dispatch port |

**To run:**
```bash
vsim -c -do run_uart_sim.do           # smoke: 16 pixels, ~200k cycles
vsim -c -do run_uart_lena_img_sim.do  # full: 128×128 Lena, ~4M cycles
python sw/benchmarks/lena_gray/reconstruct.py \
       sw/benchmarks/lena_gray/v3_output/lena_dmem_out_uart.hex
```

---

## FPGA VGA Demo Stage (DE10-Standard, Cyclone V)

**Status:** VGA display hardware-verified. RGB→grayscale pipeline debugged & fixed in sim. Awaiting full Quartus recompile to push fix to hardware.

**Signal flow (DMEM-init mode, no UART):**
```
DMEM pre-init via MIF (RGB at 0x0000-0xBFFF) → firmware BT.601 VPU (dmem_lena.S)
→ DMEM[0xC000–0xFFFF] (Y channel written by VPU) → vga_ctrl → ADV7123 DAC → VGA monitor
```
**Signal flow (Y direct mode, verified working):**
```
DMEM pre-init via MIF (Y at 0xC000-0xFFFF) → trivial firmware (vga_lena_y.S, j done)
→ vga_ctrl reads continuously → ADV7123 → VGA monitor  ← VERIFIED ON HARDWARE ✅
```

| Component | File | Notes |
|-----------|------|-------|
| VGA timing | `fpga/rtl/hdmi/vga_timing.sv` | 640×480@60Hz; H=800, V=525; HS/VS active-low, DE |
| I2C master | `fpga/rtl/hdmi/i2c_master.sv` | 100 kHz, quarter-period FSM, START/byte/ACK/STOP |
| ADV7513 config | `fpga/rtl/hdmi/adv7513_cfg.sv` | 14 registers at boot: power-on, RGB444 8bpc, HDMI mode, HPD override |
| HDMI controller | `fpga/rtl/hdmi/hdmi_ctrl.sv` | Reads Y from DMEM via vid port; 3× scale → 384×384 centered on 640×480; RGB888 gray output |
| DMEM video port | `fpga/rtl/mem/dmem_qip_wrapper.sv` | Port A mux: scalar priority; `vid_re` enables video read when `s_re=0` |
| FPGA top | `fpga/rtl/top/riscv_vpu_top_fpga.sv` | `pclk` input (from PLL), `hdmi_tx_*` outputs, `u_hdmi` wired |
| Timing constraints | `fpga/constraints/timing.sdc` | `pclk` 25 MHz, HDMI output delay, I2C false path |

**Pixel mapping:**
```
screen active region: hc=[128..511], vc=[48..431]  (384×384 centered)
frame_row = (vc - 48) / 3    → 0..127
frame_col = (hc - 128) / 3   → 0..127
dmem_word = 12288 + frame_row*32 + frame_col/4
byte_lane = frame_col % 4
RGB888    = {Y, Y, Y}  (grayscale)
```

**Quartus steps to complete before board test:**
1. IP Catalog → `altpll`: 50 MHz in → 25 MHz out → output to `pclk` top port
2. IP Catalog → `RAM: 2-PORT (altsyncram)`: TDP, 8b×16384, M10K → output name `dmem_bank` → add `.qip`
3. Pin assignment: map `hdmi_tx_d[23:0]`, `hdmi_tx_clk`, `hdmi_tx_hs/vs/de`, `hdmi_tx_scl/sda` to DE10-Standard HDMI_TX pins
4. Compile → program `.sof`

---

## Trial Pipeline Design (rtl_trial/)

**Status:** Superseded by `riscv_vpu_top_v4` for simulation. Components reused: `dmem_sync.sv`, `uart.sv`, `tl_pkg.sv`.

**Architecture changes vs production rtl/:**
| Component | Before (rtl/) | After (rtl_trial/) |
|-----------|--------------|-------------------|
| Scalar core | Single-cycle (`single_cycle.sv`) | 2-stage pipeline (`scalar_core_v2.sv`) |
| IMEM | Combinatorial read | Synchronous, 1-cycle latency (`imem_sync.sv`) |
| DMEM | Combinatorial read, async reset | Synchronous read, byte-enable, sync reset (`dmem_sync.sv`) |
| Memory bus | Direct wires from LSU | TileLink-UL 1M-2S (`tl_ul_xbar.sv`) |
| UART | None | 8N1 RX/TX, 8-byte FIFOs, TL-UL slave (`uart.sv`) |
| LSU IO write logic | 4× copy-paste SB/SH/SW | Single `apply_store()` function |

**File inventory:**
```
rtl_trial/
├── mem/imem_sync.sv        — sync IMEM, en_i freeze for VPU stall
├── mem/dmem_sync.sv        — sync DMEM, 1-cycle read, byte-enable + VLSU port
├── bus/tl_pkg.sv           — TileLink-UL types
├── bus/tl_ul_xbar.sv       — 1M-2S crossbar (0x0000xxxx=DMEM, 0xFF0000xx=UART)
├── bus/tl_ul_dmem_adapter.sv — TL-UL ↔ dmem_sync flat interface
├── uart/uart.sv            — UART RX/TX, TL-UL slave registers
├── riscv/scalar_core_v2.sv — 2-stage IF/EX pipeline, load stall, branch flush
└── riscv_vpu_top_v2.sv     — top-level integrating all above + VPU
```
**Simulation:** `vsim -do run_trial_sim.do` → `work.tb_riscv_vpu_top_v2`

**Known issues to resolve during simulation:**
- Load stall in `scalar_core_v2` needs verification with DMEM round-trip
- `scalar_core_v2` ALU: M-extension block has duplicate outer case (needs merge)
- VLSU 2-cycle load (mem_ready handshake with sync DMEM) → ~2× latency for vector LD

---

## Change Log

| Date | Change | Module(s) Affected |
|------|--------|--------------------|
| 2026-04-27 | Initial CLAUDE.md and PROJECT_STATUS.md created | — |
| 2026-04-27 | Fix: control_unit.sv — thêm begin/end cho OP_V if block, ngăn rd_wren=1 với mọi vector instruction | rtl/riscv/control_unit.sv |
| 2026-04-27 | Fix: vproc_cycle_counter.sv — `done = ... && running_r` để ngăn spurious done khi idle | rtl/vproc_cycle_counter.sv |
| 2026-04-27 | Fix: vproc_system_wrapper.sv — is_compare_r cover đủ 8 funct6 compare thay vì 3 | rtl/vproc_system_wrapper.sv |
| 2026-04-27 | Add: sw/test_vlsu.S — test VLE32.V + VSE32.V với verification scalar LW | sw/test_vlsu.S |
| 2026-04-27 | Add: sw/test_loop.S — test multi-iteration loop, 12 phần tử, 3 iterations | sw/test_loop.S |
| 2026-04-27 | Add: sw/test_reduction.S — test vredsum/vredmax/vredmin | sw/test_reduction.S |
| 2026-04-27 | Fix: vproc_vec_lsu.sv — thêm last_word_be logic ngăn ghi tail bytes (e8/e16 VSE) | rtl/vproc_vec_lsu.sv |
| 2026-04-27 | Fix: vproc_vec_lsu.sv — thêm vm_i + v0_flat_i ports + mask_be logic (masked store) | rtl/vproc_vec_lsu.sv |
| 2026-04-27 | Fix: vproc_system_wrapper.sv — lọc is_vls_insn: chỉ unit-stride regular (mop=00, lumop=00000) | rtl/vproc_system_wrapper.sv |
| 2026-04-27 | Update: bench/tb_vproc_vlsu.sv — e8/e16 tests, masked store test, file report output | bench/tb_vproc_vlsu.sv |
| 2026-04-27 | Rewrite: bench/tb_vproc_all_instr.sv — fix fsm_state[3:0], add VLSU ports, fix compare expected values (packed mask format), add VRSUB/VMIN/VMAX/LMUL=2/reduction tests | bench/tb_vproc_all_instr.sv |
| 2026-04-27 | Fix: vproc_system_wrapper.sv — vls_fire guard for stores: wait fifo_or_fsm_busy=0 before firing; vpu_ready stall logic for VLS store RAW hazard | rtl/vproc_system_wrapper.sv |
| 2026-04-27 | Add: sw/bench_imgproc.S — RGB-to-grayscale BT.601 benchmark; rtl/imem_from_gcc.hex rebuilt | sw/bench_imgproc.S, rtl/imem_from_gcc.hex |
| 2026-04-28 | Add: RAW scoreboard (vrf_busy_r[31:0]) + WAW guard (load_waw_stall) in vproc_system_wrapper.sv | rtl/vproc_system_wrapper.sv |
| 2026-04-28 | Fix: vproc_system_wrapper.sv — push_valid gated by vpu_ready for arithmetic OP-V, preventing duplicate FIFO pushes during scalar stall | rtl/vproc_system_wrapper.sv |
| 2026-04-28 | Add: sw/bench_matmul.S — 4×4 integer matrix multiply benchmark, outer-product accumulation pattern | sw/bench_matmul.S |
| 2026-05-01 | Fix: vproc_vdecoder.sv — is_rs1 thiếu OPMVX (funct3=110) → vmul.vx/vmulh.vx/.vx dùng VRF thay vì scalar rs1 | rtl/vproc_vdecoder.sv |
| 2026-05-02 | Add: sw/benchmarks/lena_gray — RGB→grayscale (16×16→128×128, SEW=8, vmulhu.vx BT.601); 16384/16384 PASS, 34828 cycles; lsu.sv DMEM tăng lên 64KB (16384 words) cho benchmark | sw/benchmarks/lena_gray/, bench/tb_lena_gray.sv, run_lena_sim.do, rtl/riscv/lsu.sv |
| 2026-05-01 | Add: sw/benchmarks/axpy — AXPY benchmark (N=16, a=3); kết quả đúng y[0]=4, y[4]=16, y[8]=28, y[12]=40 | sw/benchmarks/axpy/ |
| 2026-05-01 | Fix: run_top_sim.do, vproc_all_instr.do — thêm quit -f để hỗ trợ batch mode (vsim -c -do ...) | run_top_sim.do, vproc_all_instr.do |
| 2026-05-03 | Simplify: lsu.sv IO write logic — extract `apply_store()` function, remove 4× SB/SH/SW copy-paste; switch to synchronous reset | rtl/riscv/lsu.sv |
| 2026-05-03 | Add: Trial pipeline design — 2-stage core, sync IMEM/DMEM, TileLink-UL bus, UART | rtl_trial/, bench/tb_riscv_vpu_top_v2.sv, run_trial_sim.do |
| 2026-05-09 | Add: 5-stage pipelined scalar core with VPU dispatch — replaces single-cycle as primary simulation core; load-use stall, EX/MEM/WB forwarding, IO + UART address decode | rtl/pipeline/pipelined_vpu.sv |
| 2026-05-09 | Add: riscv_vpu_top_v4.sv — new simulation top integrating pipelined_vpu + dmem_sync + vproc_system_wrapper + uart; UART decoded inline at 0xFF000000, 1-cycle latency registered at top | rtl/riscv_vpu_top_v4.sv |
| 2026-05-09 | Add: UART firmware uart_lena_test.S (16-pixel smoke, 46 insns) and uart_lena.S (128×128 full, 53 insns); BT.601 via vmulhu.vx (Y=R×77+G×150+B×29 / 256) | sw/uart_lena_test.S, sw/uart_lena.S |
| 2026-05-09 | Add: UART simulation testbenches tb_uart_lena.sv (smoke), tb_uart_lena_img.sv (full image dump → reconstruct.py) | bench/tb_uart_lena.sv, bench/tb_uart_lena_img.sv |
| 2026-05-09 | Add: run_uart_sim.do (smoke test) and run_uart_lena_img_sim.do (full image); both auto-build firmware from sw/ and copy → imem.hex | run_uart_sim.do, run_uart_lena_img_sim.do |
| 2026-05-09 | Fix: sw/Makefile — Windows TEMP/TMP path export (GCC.exe native binary ignores MSYS2 /tmp); -pipe flag to CFLAGS; explicit uart_lena.hex and uart_lena_test.hex targets | sw/Makefile |
| 2026-05-09 | Add: FPGA HDMI output stage for DE10-Standard — vga_timing.sv (640×480@60Hz), i2c_master.sv (100 kHz FSM), adv7513_cfg.sv (14-reg boot), hdmi_ctrl.sv (Y→RGB888, 3× scale centered) | fpga/rtl/hdmi/*.sv |
| 2026-05-09 | Add: video read port to dmem_sync (simulation) and dmem_qip_wrapper (FPGA M10K) — Port A mux, scalar priority, 1-cycle latency | rtl_trial/mem/dmem_sync.sv, fpga/rtl/mem/dmem_qip_wrapper.sv |
| 2026-05-09 | Update: riscv_vpu_top_fpga.sv — add HDMI TX ports (24-bit D, CLK, HS, VS, DE, I2C SCL/SDA), wire u_hdmi; dmem video port wired | fpga/rtl/top/riscv_vpu_top_fpga.sv |
| 2026-05-09 | Update: timing.sdc — add pclk 25 MHz constraint, HDMI output delay, I2C false paths | fpga/constraints/timing.sdc |
| 2026-05-30 | Switch: FPGA output from HDMI (ADV7513) → VGA (ADV7123 DAC). vga_ctrl.sv replaces hdmi_ctrl.sv; de10_standard_top.sv replaces hdmi top | fpga/rtl/vga/vga_ctrl.sv, fpga/rtl/top/de10_standard_top.sv |
| 2026-05-30 | Fix: riscv_vpu_top_fpga.sv — move pll_locked declaration before assign rst_n (ModelSim forward-ref issue) | fpga/rtl/top/riscv_vpu_top_fpga.sv |
| 2026-05-30 | Add: DMEM MIF pre-init infrastructure — dmem_bank_b0-b3.v (per-lane wrappers with init_file), dmem_qip_wrapper.sv modified (generate→explicit), gen_dmem_mif.py, gen_lena_y_mif.py | fpga/rtl/mem/dmem_bank_b0-b3.v, fpga/rtl/mem/dmem_qip_wrapper.sv, fpga/gen_*.py |
| 2026-05-30 | Add: FPGA firmware — dmem_lena.S (RGB→grayscale via VPU, no UART), vga_lena_y.S (trivial spin, Y pre-loaded) | fpga/sw/dmem_lena.S, fpga/sw/vga_lena_y.S |
| 2026-05-31 | Add: Simulation testbenches — tb_dmem_lena_sim.sv (DMEM pre-init + VPU + Y check), tb_dmem_uniform_sim.sv (uniform-pixel structural debug), run_dmem_lena_sim.do, run_uniform_sim.do | bench/tb_dmem_lena_sim.sv, bench/tb_dmem_uniform_sim.sv |
| 2026-05-31 | Hardware verified: VGA display working — Lena Y channel pre-loaded via MIF, image displayed on VGA monitor | FPGA hardware |
| 2026-05-31 | **Fix (Critical): vproc_system_wrapper.sv — VLSU CSR stall bug.** vle8.v could fire during vsetvli's ST_CONFIG, seeing csr_vl_o=0, loading only 1 DMEM word → lanes 1-3 = 0 → R contribution lost for elements 4-15 of first VPU iteration. Fix: added `is_load_csr_stall = instr_valid && is_vls_load_raw && vsetvli_pending` to both `vls_fire` and `vpu_ready`. | fpga/rtl/vpu/vproc_system_wrapper.sv |
| 2026-05-31 | Add: fpga/ip/dmem_bank_b0-b3.sv — behavioral simulation passthrough wrappers for dmem_bank_b0-b3.v | fpga/ip/dmem_bank_b0-b3.sv |
