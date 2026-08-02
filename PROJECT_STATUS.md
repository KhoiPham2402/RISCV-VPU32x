# PROJECT_STATUS.md — RISC-V VPU

> **Rule:** Update this file after every architectural change, interface freeze, or milestone. Date format: YYYY-MM-DD.

---

## Current Phase

**Phase:** SoC groundwork — DMEM converted from dedicated dual-port to a single shared bus (arbitrated, VLSU > scalar > video priority) so future peripherals attach like UART does; benchmarks measured; repo on GitHub; next: ASIC synthesis flow
**Target:** ASIC Tapeout (primary) / DE10-Standard demo board (FPGA validation) / growing into a small SoC

**Last session (2026-08-02):**
- **Architecture change (SoC groundwork):** replaced the true dual/multi-port DMEM (`fpga/rtl/mem/dmem_qip_wrapper.sv` — separate physical ports for scalar core, VLSU, and video) with a **single shared logical port arbitrated by a new bus** (`fpga/rtl/bus/dmem_arbiter.sv`), the same way UART is already accessed — not a dedicated memory port per master. Fixed priority: **VLSU > scalar > video**. Simple synchronous priority arbiter (not full TileLink-UL — everything is fixed-latency, so ready/valid backpressure would be unused complexity).
- `dmem_qip_wrapper.sv` rewritten to a single logical `clk/re/we/addr/be/wdata/rdata` port (Port B of the underlying M10K banks tied off, reclaimable later via IP regen as single-port).
- `pipelined_vpu.sv`: added `s_dmem_stall_i` — scalar DMEM access can now be denied and must retry (EX/MEM freeze via new `ex_hold = vpu_stall | mem_stall`; MEM/WB takes a bubble instead of holding, since a denied access never reaches memory).
- **Found + fixed a new bug the stall mechanism itself would have introduced:** holding EX for `mem_stall` broke the implicit invariant "a vector instruction is dispatched to the VPU exactly once" (previously guaranteed because EX only ever held for `vpu_stall`, which is mutually exclusive with a successful dispatch). Added a one-shot latch (`vpu_disp_done_r`) gating `vpu_insn_vld_o` so `vproc_system_wrapper`'s `push_valid`/`vls_fire` can't fire twice for the same instruction while EX is held. Directly exercised by the matmul regression (96 real scalar/VLSU arbitration conflicts in that run) — passed correctly with the fix.
- **Found (not fixed, logged as new issue #24):** `vsll`/`vsrl`/`vsra` funct6 encodings in `vproc_vdecoder.sv`/`vproc_processor_lane.sv` (`010101`/`010000`/`010010`) do not match real RVV 1.0 (`100101`/`101000`/`101001`). Real RVV `vsll` (funct6=100101) collides with this RTL's own `VMUL` (also 100101) — GCC-compiled vector shift code would silently execute as multiply (or hit no case for vsrl/vsra, producing 0). Not caught by `tb_vproc_all_instr` because it drives the RTL's own private encoding, not real GCC output. High severity, independent of this session's other work — logged for a dedicated future fix + full regression re-verification.
- Rewrote the two regression-suite testbenches that modeled DMEM as an idealized flat dual-port array (`fpga/bench/tb_bench_generic.sv`, `fpga/bench/tb_fpga_imem_lena.sv`) to instantiate the real `dmem_arbiter` + a new single-port behavioral model `fpga/bench/dmem_model_sp.sv` instead — so the regression suite actually exercises arbitration contention rather than masking it.
- New directed unit test `fpga/bench/tb_dmem_arbiter.sv` (`fpga/sim/run_dmem_arbiter.do`): 7 cases (scalar-alone, VLSU-alone, contention with retry, write-conflict non-corruption, video hold/starve, 3-way contention, byte-enable pass-through) — all PASS.
- **Full regression after the bus change, all green:** `dmem_arbiter` unit test (19/19 individual PASS lines) · AXPY (correct, 0 conflicts) · matmul (correct, 96 real arbitration conflicts exercised — this is what validates the double-dispatch fix) · lena_gray 128×128 (**bit-identical** `Y[0..7]` AND **unchanged** cycle count, 35863 — this program never has scalar/VLSU contend in the same cycle) · `tb_vproc_all_instr` 204/204 · directed fixcheck 10/10 · full top-level compile (`de10_standard_top`), 0 errors, no new warnings.
- **Known accepted trade-off:** video/VGA is now lowest arbitration priority — sustained VLSU activity (e.g. any vector-heavy firmware) will make VGA output stale (not corrupt, hold-register protected) for its duration. Not exercised by any current testbench; accepted per architectural decision.
- **New benchmark: Sobel edge detection on Lena** (`sw/benchmarks/sobel/`) — 3×3 Sobel, `|Gx|+|Gy|` magnitude approximation, C compiled with the real `riscv64-unknown-elf-gcc` toolchain, run end-to-end through `fpga/rtl` (pipeline + VPU + new shared DMEM bus) against the same Lena source `lena_gray` uses. **Result: 0/4096 pixel mismatches, max error 0** against a pure-Python reference. Full writeup: [`fpga/regression_report/SOBEL_LENA.md`](fpga/regression_report/SOBEL_LENA.md).
- **Found two new issues while designing the Sobel kernel** (both worked around in software, neither fixed in RTL this session — see Open Issues #24/#25 below): (i) `vsll`/`vsrl`/`vsra` funct6 encodings don't match real RVV 1.0 and collide with this RTL's own `VMUL`; (ii) VLSU/DMEM addressing discards `addr[1:0]` (word-only granularity), which forced the Sobel benchmark to 64×64 @ 4 bytes/pixel instead of 128×128 @ 1 byte/pixel like `lena_gray`. Added a `make check-isa` build-time guard (`sw/benchmarks/sobel/Makefile`) that disassembles the ELF and fails the build if a forbidden instruction (shift, `vmacc`, `vslide*`, scalar `mul/div/rem`, etc.) appears — a standing safety net, not a one-time check.

**Previous session (2026-08-01):**
- Full RTL audit + cleanup pass of `fpga/` tree (5-stage pipeline + TileLink + VPU, the version now used for FPGA work) — Open Issues #19-23
- Fixed Critical #19: swapped signed/unsigned branch comparison in `brc.sv` (BLT/BGE were unsigned, BLTU/BGEU were signed)
- Fixed Critical #20: `control_unit.sv` widened to see full funct7 and squash unimplemented RV32M (mul/div/rem) instead of silently aliasing onto base ALU ops — mul/div/rem still not implemented, just no longer silently wrong
- Fixed High #21: unified all async-reset `always_ff` blocks (11 files: `d_ff.sv` + 10 in `vpu/`) to synchronous active-low reset — removes the GPR-vs-control-register reset-domain skew
- Fixed Medium #22: removed dead `tl_ul_xbar.sv`/`tl_ul_dmem_adapter.sv` (zero references anywhere in the real build); `tl_pkg.sv` kept (used by `uart.sv`/`riscv_vpu_top_fpga.sv` for types). Real inline bus still has no backpressure/error-response — noted as a known architectural limitation, not fixed (would need a redesign)
- Style: converted all 41 remaining `always @(*)` → `always_comb` across `fpga/rtl/vpu/*.sv` (CLAUDE.md rule compliance); fixed `vproc_vdecoder.sv`'s stale `CTRL_WIDTH=48` default (now 49, matches the 49-bit ctrl_bus actually packed) + added missing `[48] cfg_is_vsetivli` doc row; documented (not removed — mandatory PLL IP port) the unused `pclk_int` net in `riscv_vpu_top_fpga.sv`; added sticky RX/TX overflow status bits to UART `STAT` register (bits [2]/[3], firmware unaffected — existing code only bit-masks bits [0]/[1])
- **Correction:** earlier audit wrongly flagged `vmv.v.x` as unimplemented (#7, #23) — verified it works correctly via the shared VMERGE funct6=010111 path (vm=1 forces `v0_merge_bits` all-1s in `vproc_system_wrapper.sv`). Only `vmv.x.s` (vector→scalar GPR writeback) is genuinely missing; left unimplemented (new datapath, not exercised by any current benchmark) — see #23
- **Full regression after all fixes, all PASS:** directed unit testbench (branch signed/unsigned + M-ext squash, 10/10) · VPU instruction regression `tb_vproc_all_instr` against `fpga/rtl/vpu` (204/204, was validated against `rtl/` only before) · AXPY benchmark on `fpga/rtl` pipeline (y[0]=4, y[4]=16, y[8]=28, y[12]=40, correct) · Matmul 4×4 benchmark on `fpga/rtl` pipeline (C row sums 10/26/42/58, correct — exercises vmv.v.x) · lena_gray 128×128 full regression unchanged vs. pre-fix baseline (35863 cycles, same Y output) · full top-level compile (`de10_standard_top` → `riscv_vpu_top_fpga` → pipeline+VPU+UART+VGA+DMEM+PLL), 0 errors, no new warnings
- Remaining known gaps (not fixed, out of scope for this pass): mul/div/rem not implemented (only squashed safely, #20); TileLink bus has no real backpressure/error-response (#22); `vmv.x.s` missing (#23); `vslide1up`/`vslide1down` missing (#13)
- Full regression report with expected-vs-actual tables + raw logs: [`fpga/regression_report/SUMMARY.md`](fpga/regression_report/SUMMARY.md) — reusable scripts in `fpga/sim/run_fixcheck.do`, `run_fpga_all_instr.do`, `run_bench_axpy_matmul.do`, `run_fpga_imem_lena_regression.do`, `run_fpga_top_compile_check.do`
- Verified firmware provenance: `axpy_imem.hex`, `matmul_imem.hex`, `lena_imem.hex` all rebuilt from their `.c` sources with the real `riscv64-unknown-elf-gcc` toolchain and diffed byte-identical against the checked-in files — none are hand-written. Added missing `sw/benchmarks/{axpy,matmul}/Makefile` (previously only `lena_gray/` had one) so both are reproducible via plain `make`, not a one-off manual build

**Previous session (2026-06-04):**
- GitHub repo created: https://github.com/KhoiPham2402/RISCV-VPU32x
- Synced `vproc_system_wrapper.sv` VLSU CSR stall fix from `fpga/rtl/` → `rtl/`
- Scalar vs VPU benchmark report completed (`BENCHMARK_REPORT.md`)
- 7 benchmark comparison charts generated (`report/charts/`)
- Scalar AXPY simulation: 315 cycles (confirmed ModelSim, 2026-06-03)
- README.md created with full project documentation

**Previous session (2026-05-31):**
- VGA output confirmed working on DE10-Standard with pre-loaded Lena Y channel
- Found & fixed VPU VLSU CSR stall bug (Issue #17) in `fpga/rtl/vpu/vproc_system_wrapper.sv`
- Simulation: RGB→grayscale PASS 4096/4096 words after fix
- 5-stage pipelined scalar core + UART TL-UL integration complete (riscv_vpu_top_v4)

**Benchmark Summary:**

| Benchmark | Scalar | VPU | Speedup | Status |
|-----------|-------:|----:|:-------:|--------|
| AXPY N=16 (SEW=32) | 315 cy | 221 cy | **1.43×** | ✅ Simulation confirmed |
| MatMul 4×4 int32 | ~858 cy | 317 cy | **~2.7×** | ✅ VPU sim confirmed |
| Lena BT.601 128×128 | ~295K cy | 34 828 cy | **8.5×** | ✅ 16384/16384 px correct |

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
| RGB→grayscale FPGA demo (VPU) | 🔄 In progress | Sim PASS 4096/4096; needs full Quartus recompile + hardware verify |
| Scalar vs VPU benchmark report | ✅ Done | `BENCHMARK_REPORT.md` + `report/charts/` — 3 benchmarks, 7 charts |
| GitHub repo | ✅ Done | https://github.com/KhoiPham2402/RISCV-VPU32x — 2 branches |
| RTL sync (fpga → rtl) | ✅ Done | `vproc_system_wrapper.sv` VLSU CSR fix synced to `rtl/` (2026-06-04) |
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
| #7 | ~~Verify vmv.v.x hỗ trợ trong decoder (cần cho test_reduction.S)~~ | ~~High~~ | ~~Verified 2026-08-01 — hoạt động đúng qua đường VMERGE (funct6=010111, vm=1), xem #23b~~ |
| #8 | Check reset synchronicity throughout hierarchy (lsu.sv dùng async reset) | High | — |
| #9 | Audit for latches (lint pass needed) | High | — |
| #10 | Parameterize any remaining hardcoded widths | Medium | — |
| #11 | Add clock gating enables on VRF data path | Medium | — |
| #12 | Thay SRAM model combinational → synchronous khi tapeout | ASIC | — |
| #13 | vslide1up/vslide1down chưa implement — pathfinder benchmark bị blocked | Medium | — |
| #14 | CTRL_WIDTH=48 nhưng decoder pack 49 bits → bit[48] cfg_is_vsetivli bị drop silently | High | — |
| #15 | lsu.sv DMEM 64KB (16384 words) là simulation-only cho lena_gray 128×128 — cần parameterize và tách riêng config tapeout vs benchmark | High | — |
| #16 | ~~vsetivli (immediate AVL ≤ 31) chưa decode được~~ | ~~Medium~~ | ~~Stale — đã implement đúng: `vproc_vdecoder.sv` bit [48] `cfg_is_vsetivli` + `vproc_system_wrapper.sv:422` chọn AVL từ immediate đúng. Phát hiện lại + xác nhận 2026-08-01 khi audit fpga/rtl~~ |
| #17 | ~~VLSU CSR stall bug: vle8.v fires during vsetvli ST_CONFIG → csr_vl_o=0 → num_words=1 → lanes 1-3 = 0 → R contribution mất cho elements 4-15~~ | ~~Critical~~ | ~~Fixed 2026-05-31~~ |
| #18 | UART: cần USB-UART adapter (CP2102/CH340) cắm vào JP1 chân 3(RX)/4(TX)/2(GND). Built-in UART thuộc HPS, không dùng được từ FPGA fabric | Medium | Hardware issue |
| #19 | ~~fpga/rtl/pipeline/brc.sv: sign-correction `sel` áp dụng khi `i_br_un=1` thay vì `i_br_un=0` → BLT/BGE so sánh như unsigned, BLTU/BGEU so sánh như signed~~ | ~~Critical~~ | ~~Fixed 2026-08-01~~ |
| #20 | ~~fpga/rtl/pipeline/control_unit.sv: OPC_REGREG chỉ check funct7[5] (bit 30), không check funct7[0] → RV32M (mul/div/rem, funct7=0000001) alias âm thầm sang ADD/XOR/... không có mul/div nào được implement~~ | ~~Critical~~ | ~~Squashed (illegal_instr flag) 2026-08-01 — mul/div/rem vẫn CHƯA implement thật, chỉ chặn không cho ghi sai kết quả~~ |
| #21 | ~~fpga/rtl/: reset không đồng nhất — pipeline chính (sync active-HIGH) vs. `d_ff.sv`/toàn bộ `vpu/*` (async active-low) vs. `dmem_qip_wrapper`/`uart.sv` (sync active-low). GPR reset qua `d_ff.sv` async trong khi control regs reset sync → lệch reset domain thật~~ | ~~High~~ | ~~Fixed 2026-08-01 — mọi always_ff async-reset (11 file) chuyển sang sync active-low, giữ nguyên polarity translation ở top~~ |
| #22 | ~~fpga/rtl/bus/tl_ul_xbar.sv + tl_ul_dmem_adapter.sv là dead code (không module nào instantiate)~~ | ~~Medium~~ | ~~Xoá 2026-08-01 (0 tham chiếu trong RTL/sources.tcl/.qsf thật). `tl_pkg.sv` giữ lại — uart.sv + riscv_vpu_top_fpga.sv dùng type của nó cho bus inline. Bus inline vẫn KHÔNG có ready/backpressure/source-ID/error-response thật — đây là giới hạn kiến trúc đã biết, chưa fix (cần redesign lớn hơn, để riêng)~~ |
| #23 | control_unit.sv comment "trừ khi là lệnh vmv.x.s" nhưng rd_wren luôn hard-0 cho OP_V — vmv.x.s (vector→scalar) chưa ghi được về GPR | Medium | — |
| ~~#23b~~ | ~~(Correction 2026-08-01) Audit trước đó nói sai: vmv.v.x KHÔNG bị thiếu — nó dùng chung funct6=010111 (VMERGE) với vm=1 ép `v0_merge_bits=32'hFFFF_FFFF` (vproc_system_wrapper.sv:556-559), đúng RVV spec. Xác nhận bằng bench_matmul.S (dùng vmv.v.x) PASS trong cả VPU instruction regression (204/204) lẫn matmul benchmark trên fpga/rtl~~ | — | — |
| #24 | `vsll`/`vsrl`/`vsra` funct6 trong `vproc_vdecoder.sv`/`vproc_processor_lane.sv` (010101/010000/010010) không khớp chuẩn RVV 1.0 thật (100101/101000/101001). `vsll` chuẩn RVV trùng funct6 với `VMUL` của chính RTL này → code compile GCC dùng shift vector sẽ âm thầm chạy thành nhân (hoặc ra 0 với vsrl/vsra). `tb_vproc_all_instr` không phát hiện được vì tự dựng encode riêng, không phải encode GCC thật. Phát hiện + verify độc lập 2026-08-02 khi thiết kế benchmark Sobel — chưa fix, cần redesign funct6 + re-run toàn bộ 204 test | High | — |
| #26 | ~~pipelined_vpu.sv: EX-stage "forward from MEM" (fwd_a/fwd_b==01) luôn lấy alu_result_m bất kể lệnh ở MEM stage thật ra lấy giá trị từ đâu (wb_sel). LUI (wb_sel=11, giá trị thật=imm_m) và JAL/JALR (wb_sel=10, giá trị thật=pc_four_m) bị forward sai — bất kỳ lệnh nào đứng ngay sau lui/jal/jalr dùng chung thanh ghi đích sẽ nhận giá trị sai âm thầm. Trúng ngay mỗi lần `li reg,<hằng số 32-bit>` expand thành lui+addi mà hằng số không nhỏ (fit addi) và không tròn 0x1000 (chỉ cần lui)~~ | ~~Critical~~ | ~~Fixed 2026-08-02 — thêm mux mem_fwd_value chọn theo wb_sel_mem. Verify bằng tb_fwd_hazard.sv (LUI+JAL) + toàn bộ regression cũ không đổi kết quả~~ |
| #25 | VLSU bỏ qua `addr[1:0]` (chỉ địa chỉ theo word 4-byte) — mọi consumer DMEM index bằng `addr[15:2]`, không có byte/halfword rotation cho vector load/store. Buộc benchmark Sobel phải dùng 4 byte/pixel thay vì 1 byte/pixel như lena_gray. Phát hiện 2026-08-02, chưa fix (cần sửa VLSU + dmem addressing, re-verify toàn bộ regression) | Medium | — |

---

## Key Design Decisions

| Date | Decision | Rationale |
|------|----------|-----------|
| — | VLEN=128, single lane | Area-constrained; meets Zve32x requirement |
| — | Synchronous reset, active-low | Standard ASIC practice |
| — | RV32IM scalar + Zve32x vector | Sufficient for target compute workloads |
| — | LMUL support: 1/2/4/8 | Full spec compliance for Zve32x |
| 2026-08-02 | DMEM: single shared arbitrated bus port, not dedicated dual-port per master | SoC groundwork — DMEM should be accessed like any other bus peripheral (UART), so future IP blocks attach the same way; VLSU > scalar > video fixed priority chosen for simplicity/low risk over a full round-robin or TileLink-UL handshake |

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
| 2026-08-01 | `tb_vproc_all_instr` against **fpga/rtl/vpu** (post cleanup pass) | ✅ 204/204 PASS | First time this suite run against the fpga/ tree instead of rtl/; confirms VMERGE/vmv.v.x, OPMVV, OPMVX, LMUL=2, reductions all correct post-fix |
| 2026-08-01 | AXPY (N=16, a=3) against **fpga/rtl** 5-stage pipeline + VPU | ✅ PASS | y[0]=4 y[4]=16 y[8]=28 y[12]=40 correct, 20000-cycle budget, mailbox @0x1E0 |
| 2026-08-01 | Matmul 4×4 against **fpga/rtl** 5-stage pipeline + VPU | ✅ PASS | C row sums 10/26/42/58 correct — exercises vmv.v.x via VMERGE path |
| 2026-08-01 | `tb_fpga_imem_lena` (lena_gray 128×128) against **fpga/rtl**, post #19-#22 fixes | ✅ PASS | 35863 cycles, Y[0..7]=a1 9f a0 9d 9c 9b 9a 99 — identical to pre-fix baseline (no regression) |

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
| 2026-06-03 | Benchmark: scalar AXPY N=16 = 315 cycles (ModelSim, single-cycle core, tb_scalar_io_detect.sv) | bench/tb_scalar_io_detect.sv |
| 2026-06-03 | Add: 7 benchmark comparison charts (Scalar vs VPU) via matplotlib | report/charts/, report/gen_benchmark_charts.py |
| 2026-06-03 | Add: BENCHMARK_REPORT.md — full scalar vs VPU analysis with simulation evidence | BENCHMARK_REPORT.md |
| 2026-06-04 | Sync: vproc_system_wrapper.sv VLSU CSR stall fix from fpga/rtl/vpu/ → rtl/ | rtl/vproc_system_wrapper.sv |
| 2026-06-04 | Add: README.md — full project documentation (architecture, build, sim, FPGA, benchmarks) | README.md |
| 2026-06-04 | Push: project to GitHub — https://github.com/KhoiPham2402/RISCV-VPU32x (master + trial/pipeline-sync-mem-uart) | git remote |
| 2026-08-01 | Audit: full RTL review of fpga/ tree (5-stage pipeline + TileLink + VPU) — found #19-23 (see Open Issues) | fpga/rtl/** |
| 2026-08-01 | Fix (Critical, #19): brc.sv — sign-correction `sel` now gated by `~i_br_un` instead of `i_br_un`; BLT/BGE were comparing as unsigned and BLTU/BGEU as signed. Verified with directed unit tb (BLT(-1,1), BGE(-1,1), BLTU(-1,1), BGEU(-1,1) all now correct) + full lena_gray pipeline regression (tb_fpga_imem_lena, 35863 cycles, Y[0..7] unchanged vs. pre-fix baseline) | fpga/rtl/pipeline/brc.sv |
| 2026-08-01 | Fix (Critical, #20): control_unit.sv — widened `instr` input 11b→17b to carry full funct7[6:0] (was silently dropping bit 25, the M-extension discriminator); added `illegal_instr` output, squashes rd_wren for funct7=0000001 (mul/div/rem) instead of letting it alias onto ADD/SLL/SLT/XOR/SRL/OR/AND. Wired through pipelined_vpu.sv as new `o_illegal_instr` port (decode-stage, currently unconnected at top-level — available for a future trap/LED hookup). mul/div/rem are still NOT implemented, just no longer silently wrong. | fpga/rtl/pipeline/control_unit.sv, fpga/rtl/pipeline/pipelined_vpu.sv |
| 2026-08-01 | Fix (High, #21): unified reset synchronicity — `always_ff/always @(posedge clk or negedge rst_n)` → `always_ff @(posedge clk)` (body unchanged, `if (!rst_n)` stays as the first check) across d_ff.sv + 10 vpu/ files (vproc_fsm, vproc_fifo, vproc_vregfile, vproc_vcsr, vproc_vrf_addr_gen, vproc_reduction, vproc_cycle_counter, vproc_mask_write_buffer, vproc_system_wrapper ×3, vproc_vec_lsu ×2). Behavior-preserving (verified via lena_gray regression, identical cycle count/output before/after). | fpga/rtl/pipeline/d_ff.sv, fpga/rtl/vpu/*.sv |
| 2026-08-01 | Fix (Medium, #22): deleted fpga/rtl/bus/tl_ul_xbar.sv and tl_ul_dmem_adapter.sv — confirmed zero instantiations anywhere in fpga/, and not referenced by the live fpga/riscv_vpu.qsf or fpga/sources.tcl (only the stale fpga/quartus_report/ snapshot referenced them). tl_pkg.sv kept (uart.sv, riscv_vpu_top_fpga.sv both `import tl_pkg::*` for tl_a_t/tl_d_t types). | fpga/rtl/bus/tl_ul_xbar.sv (removed), fpga/rtl/bus/tl_ul_dmem_adapter.sv (removed) |
| 2026-08-01 | Style: `always @(*)` → `always_comb` across 15 files / 41 occurrences in fpga/rtl/vpu/ (CLAUDE.md rule compliance, no behavior change, no new latch warnings on recompile). | fpga/rtl/vpu/*.sv |
| 2026-08-01 | Fix: vproc_vdecoder.sv default `CTRL_WIDTH` 48→49 (matches the 49-bit ctrl_bus actually packed; the real system already overrode this via vproc_system_wrapper.sv, so this was a latent footgun for any future direct instantiation, not a live bug) + added missing `[48] cfg_is_vsetivli` line to the header doc table. | fpga/rtl/vpu/vproc_vdecoder.sv |
| 2026-08-01 | Add: UART STAT register bits [2]=RX_OVERFLOW, [3]=TX_OVERFLOW (sticky until reset) — previously RX/TX FIFO overflow silently dropped bytes with no visibility. Firmware unaffected (existing .S files only `andi` bit-mask bits [0]/[1]). | fpga/rtl/uart/uart.sv |
| 2026-08-01 | Docs: documented (not removed) unused `pclk_int` net in riscv_vpu_top_fpga.sv — it's a mandatory output of the generated `pll` IP, can't be dropped without a Quartus IP regen; comment clarifies it's intentionally unused (VGA/HDMI clocked from `sclk` instead) rather than a stray leftover. | fpga/rtl/top/riscv_vpu_top_fpga.sv |
| 2026-08-01 | Correction (#7, #23): earlier audit incorrectly claimed vmv.v.x was unimplemented. Verified it works via the shared VMERGE funct6=010111 decode path — vm=1 forces `lane*_v0_merge_bits = 32'hFFFF_FFFF` in vproc_system_wrapper.sv, making the merge unconditionally pick the new operand, per RVV spec. Confirmed by both the VPU instruction regression and the matmul benchmark (which uses vmv.v.x), both passing on fpga/rtl. Only vmv.x.s (vector-element → scalar GPR) remains genuinely unimplemented. | PROJECT_STATUS.md (no RTL change — false positive corrected) |
| 2026-08-01 | Regression: adapted AXPY and matmul benchmarks (previously only validated against rtl/ single-cycle core) to run against fpga/rtl pipeline+VPU; adapted VPU instruction regression (tb_vproc_all_instr, 204 tests) to compile against fpga/rtl/vpu instead of rtl/vpu. All PASS — see Last Session summary above for full results. | (verification only, no RTL change; ad-hoc .do/tb kept outside repo) |
| 2026-08-02 | Add (SoC groundwork): fpga/rtl/bus/dmem_arbiter.sv — single shared DMEM bus port, fixed priority VLSU > scalar > video. Replaces the old true dual/multi-port dmem_qip_wrapper (separate physical ports per master). | fpga/rtl/bus/dmem_arbiter.sv (new) |
| 2026-08-02 | Rewrite: fpga/rtl/mem/dmem_qip_wrapper.sv — single logical port (clk/re/we/addr/be/wdata/rdata), Port B of the underlying M10K banks tied off. | fpga/rtl/mem/dmem_qip_wrapper.sv |
| 2026-08-02 | Fix: pipelined_vpu.sv — added s_dmem_stall_i input; new mem_stall/ex_hold stall composition (ID/EX + EX/MEM freeze on mem_stall, MEM/WB bubbles instead of holding). Added vpu_disp_done_r one-shot latch gating vpu_insn_vld_o — fixes a double-dispatch bug the stall mechanism itself would otherwise introduce (a vector instruction held in EX by mem_stall could push into the VPU FIFO / fire vls_fire twice). Verified via matmul regression, which exercises 96 real arbitration conflicts. | fpga/rtl/pipeline/pipelined_vpu.sv |
| 2026-08-02 | Update: fpga/rtl/top/riscv_vpu_top_fpga.sv — rewired scalar/VLSU/video DMEM ports through dmem_arbiter instead of direct dmem_qip_wrapper connections; header comment updated. | fpga/rtl/top/riscv_vpu_top_fpga.sv |
| 2026-08-02 | Add: fpga/bench/dmem_model_sp.sv — single-port behavioral DMEM model matching dmem_qip_wrapper's timing contract, for use behind dmem_arbiter in testbenches. | fpga/bench/dmem_model_sp.sv (new) |
| 2026-08-02 | Add: fpga/bench/tb_dmem_arbiter.sv + fpga/sim/run_dmem_arbiter.do — directed unit test for dmem_arbiter.sv, 7 cases (scalar-alone, VLSU-alone, contention+retry, write-conflict non-corruption, video hold/starve, 3-way contention, byte-enable pass-through), all PASS. | fpga/bench/tb_dmem_arbiter.sv (new), fpga/sim/run_dmem_arbiter.do (new) |
| 2026-08-02 | Rewrite: fpga/bench/tb_bench_generic.sv, fpga/bench/tb_fpga_imem_lena.sv — replaced idealized flat dual-port DMEM model (two independent always blocks) with real dmem_arbiter + dmem_model_sp, so the regression suite exercises real scalar/VLSU contention instead of masking it. AXPY/matmul/lena_gray all still PASS; lena_gray's Y[0..7] output and cycle count (35863) are bit-identical to the pre-change baseline. | fpga/bench/tb_bench_generic.sv, fpga/bench/tb_fpga_imem_lena.sv |
| 2026-08-02 | Build files: added dmem_arbiter.sv to fpga/sources.tcl and every .do script that compiles dmem_qip_wrapper.sv (9 scripts at repo root + fpga/sim/). | fpga/sources.tcl, run_wave_dmem_lena.do, run_scalar_bt601.do, run_scalar_bench.do, run_dmem_lena_wave.do, run_dmem_lena_sim.do, fpga/sim/run_fpga_top_compile_check.do, run_wave_uart_loopback.do, run_vga_capture.do, run_uart_loopback.do, run_lena_fpga_sim.do, run_fpga_imem_lena_regression.do, run_wave_fpga_imem_lena.do |
| 2026-08-02 | Found (#24, not fixed): vsll/vsrl/vsra funct6 encodings don't match real RVV 1.0 — vsll collides with this RTL's own VMUL encoding. Found (#25, not fixed): VLSU/dmem addressing discards addr[1:0] (word-only addressing), forcing the Sobel benchmark to use 4B/pixel. Both logged as new open issues, not fixed this session. | PROJECT_STATUS.md (no RTL change) |
| 2026-08-02 | Add: sw/benchmarks/sobel/ — sobel.c (3x3 Sobel, \|Gx\|+\|Gy\| approximation, SEW=32/LMUL=1, no shifts/vmacc/widening), Makefile (real riscv64-unknown-elf-gcc build + check-isa disassembly guard), prep_sobel.py (reuses lena_gray's Lena source + BT.601 conversion, resized 64x64), reconstruct_sobel.py (zero-tolerance exact-match verification + PNG output). Result: 0/4096 mismatches vs. pure-Python reference. | sw/benchmarks/sobel/*.c, *.py, Makefile (new) |
| 2026-08-02 | Add: fpga/bench/tb_sobel_lena.sv + fpga/sim/run_sobel_lena.do — full-system Sobel testbench (pipelined_vpu + vproc_system_wrapper + dmem_arbiter + dmem_model_sp), backdoor IMEM/DMEM load, full-DMEM dump for reconstruct_sobel.py, modeled on tb_fpga_imem_lena.sv (load/done-detect) + bench/tb_lena_gray.sv (dump format). 93766 cycles, PASS. | fpga/bench/tb_sobel_lena.sv (new), fpga/sim/run_sobel_lena.do (new) |
| 2026-08-02 | Add: fpga/regression_report/SOBEL_LENA.md — full Sobel benchmark writeup (algorithm, DMEM layout, issues #24/#25 rationale, pipeline, result images). Updated fpga/regression_report/SUMMARY.md (test group #7, section 8) and this file with Part A + Part B summaries. | fpga/regression_report/SOBEL_LENA.md (new), fpga/regression_report/SUMMARY.md, PROJECT_STATUS.md |
| 2026-08-02 | Follow-up debugging pass on the dmem_arbiter design (user asked "bug or just limitation?"): re-audited every ex_hold/vpu_stall/mem_stall consumer in pipelined_vpu.sv, traced address/data stability under multi-cycle denial, checked for combinational loops. Added directed tests C8 (5-cycle sustained VLSU burst vs. held scalar write) and C9 (video survives sustained multi-cycle denial) to tb_dmem_arbiter.sv — 40/40 PASS. Added max-consecutive-streak instrumentation to tb_bench_generic.sv; matmul empirically hits a real 4-cycle streak and still produces the correct answer. **Conclusion for the arbiter itself: no bug found — the fixed VLSU>scalar>video priority is a bounded-starvation limitation by design, not an implementation defect.** | fpga/bench/tb_dmem_arbiter.sv, fpga/bench/tb_bench_generic.sv |
| 2026-08-02 | **Fix (Critical, #26, found while investigating the user's follow-up question, pre-existing since long before this session — `git log` confirms last touched in commit 71fa990, unrelated to Part A/B):** `pipelined_vpu.sv`'s EX-stage "forward from MEM" path (`fwd_a`/`fwd_b` == `01`) always selected `alu_result_m` regardless of what the MEM-stage instruction's *real* result actually was. Correct only for regular ALU ops/AUIPC (`wb_sel_mem==01`). For **LUI** (`wb_sel_mem==11`, real result is `imm_m`) and **JAL/JALR** (`wb_sel_mem==10`, real result is `pc_four_m`, the link address — `alu_result_m` for these is the *jump target*, a completely different value), any instruction landing exactly 1 cycle later that consumed that register got silently wrong data. Hit on **every** `li reg,<32-bit constant>` expansion (`lui`+`addi` back-to-back, exactly the 1-cycle-apart case) whenever the constant isn't small enough for `addi` alone or a round `0x1000` multiple needing only `lui` — none of this session's benchmarks (Sobel/lena_gray addresses are `0x1000`-aligned, AXPY/matmul's are small) happened to need such a constant, hence zero regression failures despite the bug being live the whole time. Reproduced with a hand-written assembly test (`li x7,0x22222222` computed `0x22222322` instead — off by exactly the value of an unrelated register `x4`, whose value leaked in because LUI has no real `rs1` field but `instr[19:15]` still gets decoded as one) **before** fixing, confirmed exact match **after**. Fix: added `mem_fwd_value` — a `wb_sel_mem`-driven mux (`imm_m` / `pc_four_m` / `alu_result_m`) feeding `ex1_fwd`/`ex2_fwd` instead of `alu_result_m` directly. Verified: new regression `fpga/bench/tb_fwd_hazard.sv` (LUI+JAL cases, both PASS) plus full existing suite re-run unchanged (arbiter 40/40, fixcheck 10/10, `tb_vproc_all_instr` 204/204, AXPY/matmul/lena_gray/Sobel all bit-identical to pre-fix results — confirming none of them ever exercised the buggy path). | fpga/rtl/pipeline/pipelined_vpu.sv, fpga/bench/tb_fwd_hazard.sv (new), fpga/bench/asm/fwd_hazard.S (new), fpga/sim/run_fwd_hazard.do (new) |
