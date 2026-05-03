# PROJECT_STATUS.md — RISC-V VPU

> **Rule:** Update this file after every architectural change, interface freeze, or milestone. Date format: YYYY-MM-DD.

---

## Current Phase

**Phase:** RTL Development & Functional Verification
**Target:** ASIC Tapeout

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
| VPU–CPU integration | ✅ Done | `rtl/riscv_vpu_top.sv` |
| Full instruction regression | ✅ Done | 172/172 PASS (2026-05-01) |
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
| 2026-05-01 | `tb_riscv_vpu_top` (bench_axpy) | ✅ PASS | y[0]=4 y[4]=16 y[8]=28 y[12]=40 correct (N=16, a=3, 221 cycles) |
| 2026-05-01 | `tb_vproc_all_instr` | ✅ 172/172 PASS | Post-decoder fix; vmul.vx/vmulh.vx now use scalar rs1 correctly |
| 2026-04-27 | `tb_vproc_all_instr` | ✅ 172/172 PASS | ALU VV/VX/VI, VRSUB, Logic, Shift, VMIN/VMAX, Compare (partial), VMULH, Widening, LMUL=2, Reductions |
| 2026-04-27 | `tb_vproc_vlsu` | ✅ 75/75 PASS | e8/e16/e32 random VL, masked store |
| — | `tb_vproc_adder` | — | — |
| — | `tb_vproc_mul` | — | — |

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
