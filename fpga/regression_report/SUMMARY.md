# FPGA Regression Report — 2026-08-01 → 2026-08-02

Full regression of the **`fpga/rtl` tree** (5-stage pipeline + VPU + shared DMEM bus +
UART/VGA) after the Critical-bug fixes (#19, #20), the cleanup pass (#21, #22, style,
docs), and the **DMEM single-shared-bus architecture change** (2026-08-02, SoC
groundwork — see `PROJECT_STATUS.md` "Last session"). Run right before system
integration testing / the Sobel benchmark to confirm nothing regressed.

**How to reproduce:** every command below is `vsim -c -do fpga/sim/<script>.do`, run
from the repo root. Scripts + testbenches are checked into the repo (`fpga/sim/`,
`fpga/bench/`) — not one-off scratch files — so this is re-runnable at any time.
Raw ModelSim transcripts for every run are in [`logs/`](logs/).

## Result overview

| # | Test | Script | Log | Result |
|---|------|--------|-----|--------|
| 0 | `dmem_arbiter` directed unit test (new, 2026-08-02) | `fpga/sim/run_dmem_arbiter.do` | [`dmem_arbiter.log`](logs/dmem_arbiter.log) | ✅ **19/19 PASS** |
| 1 | Directed unit checks (branch signed/unsigned + M-ext squash) | `fpga/sim/run_fixcheck.do` | [`unit_fixcheck.log`](logs/unit_fixcheck.log) | ✅ **10/10 PASS** |
| 2 | VPU instruction regression | `fpga/sim/run_fpga_all_instr.do` | [`vproc_all_instr.log`](logs/vproc_all_instr.log) | ✅ **204/204 PASS** |
| 3 | AXPY benchmark (N=16, a=3) | `fpga/sim/run_bench_axpy_matmul.do` | [`axpy_matmul.log`](logs/axpy_matmul.log) | ✅ **PASS** (0 arbitration conflicts) |
| 4 | Matmul 4×4 benchmark | `fpga/sim/run_bench_axpy_matmul.do` | [`axpy_matmul.log`](logs/axpy_matmul.log) | ✅ **PASS** (96 real arbitration conflicts, max 4-cycle consecutive streak) |
| 5 | Lena BT.601 grayscale 128×128 | `fpga/sim/run_fpga_imem_lena_regression.do` | [`lena_gray.log`](logs/lena_gray.log) | ✅ **PASS** (bit-identical to pre-bus-change baseline) |
| 6 | Full top-level compile/elaborate | `fpga/sim/run_fpga_top_compile_check.do` | [`top_level_compile.log`](logs/top_level_compile.log) | ✅ **0 errors** |
| 7 | Sobel edge detection on Lena (new, 2026-08-02) | `fpga/sim/run_sobel_lena.do` | [`sobel_lena.log`](logs/sobel_lena.log) | ✅ **PASS, 0/4096 mismatches** — see [`SOBEL_LENA.md`](SOBEL_LENA.md) |
| 8 | EX-forward MEM-stage bug regression (new, 2026-08-02, issue #26) | `fpga/sim/run_fwd_hazard.do` | [`fwd_hazard.log`](logs/fwd_hazard.log) | ✅ **ALL PASS** — see §9 below |

**Total: 9/9 test groups PASS, 0 errors anywhere.**

**2026-08-02 update:** DMEM was converted from a true dual/multi-port memory
(dedicated physical port per master) to a single shared port arbitrated by
`fpga/rtl/bus/dmem_arbiter.sv` (VLSU > scalar > video priority) — SoC
groundwork so future peripherals attach the same way UART already does. Test
groups #3-#6 were re-run against the new architecture: `tb_bench_generic.sv`
and `tb_fpga_imem_lena.sv` (#3-#5) were rewritten to instantiate the real
arbiter + a new single-port behavioral model (`fpga/bench/dmem_model_sp.sv`)
instead of an idealized flat dual-port array, so they now actually exercise
scalar/VLSU contention rather than masking it — see the matmul row above
(96 real conflicts) and §7 below.

---

## 0. `dmem_arbiter` directed unit test (new, 2026-08-02)

DUT: `fpga/rtl/bus/dmem_arbiter.sv` + `fpga/bench/dmem_model_sp.sv` in isolation.
Source: `fpga/bench/tb_dmem_arbiter.sv`.

| Case | Checks | Status |
|------|--------|--------|
| C1 | Scalar-alone read: not stalled, data correct 1 cycle later | ✅ 2/2 |
| C2 | VLSU-alone read: not ready before grant edge, ready+data right after | ✅ 3/3 |
| C3 | Scalar+VLSU contention: scalar stalled, VLSU's read completes on the grant edge, scalar retries and succeeds once VLSU is idle | ✅ 4/4 |
| C4 | Scalar+VLSU write conflict: scalar write does **not** land while denied, VLSU write lands, scalar write lands on retry (no corruption either direction) | ✅ 5/5 |
| C5 | Video loses to scalar (holds last value), wins once scalar is idle (data updates) | ✅ 2/2 |
| C6 | 3-way contention: VLSU wins, scalar stalled, video holds (starved, not corrupted) | ✅ 2/2 |
| C7 | Byte-enable pass-through: partial-word write only touches the enabled byte | ✅ 1/1 |
| C8 | **Sustained 5-cycle VLSU burst** (streamed addresses) with scalar holding an identical denied write throughout — every VLSU cycle gets correct data (no dropped/corrupted cycle), scalar's write never partially lands, and lands correctly with unchanged address/data once the burst ends | ✅ 17/17 |
| C9 | Video survives a sustained 5-cycle denial (not just 1 cycle) — holds the same value throughout, refreshes correctly once it wins again | ✅ 6/6 |

`=== RESULT: ALL PASS ===` (40/40 individual checks).

C8/C9 were added 2026-08-02 specifically to answer "is this a bug or just a limitation?" — the original C1-C7 only exercised single-cycle denial+retry; C8/C9 stress multi-cycle sustained contention, which is what actually happens under real vector load/store bursts (confirmed empirically below, not just synthetically).

---

## 1. Directed unit checks — branch signed/unsigned (#19) + M-extension squash (#20)

DUT: `brc.sv` + `control_unit.sv` in isolation. Source: `fpga/bench/tb_fixcheck.sv`.

| Case | Expected | Got | Status |
|------|----------|-----|--------|
| `BLT(-1, 1)` (signed) | taken=1 | taken=1 | ✅ PASS |
| `BGE(-1, 1)` (signed) | taken=0 | taken=0 | ✅ PASS |
| `BLTU(-1, 1)` (unsigned, -1=0xFFFFFFFF) | taken=0 | taken=0 | ✅ PASS |
| `BGEU(-1, 1)` (unsigned) | taken=1 | taken=1 | ✅ PASS |
| `BLT(1, 2)` (sanity, same-sign) | taken=1 | taken=1 | ✅ PASS |
| `BLTU(1, 2)` (sanity, same-sign) | taken=1 | taken=1 | ✅ PASS |
| `MUL` (funct7=0000001) squashed | illegal=1, rd_wren=0 | illegal=1, rd_wren=0 | ✅ PASS |
| `DIV` (funct7=0000001) squashed | illegal=1, rd_wren=0 | illegal=1, rd_wren=0 | ✅ PASS |
| `ADD` (funct7=0000000) not flagged | illegal=0 | illegal=0 | ✅ PASS |
| `SUB` (funct7=0100000) not flagged | illegal=0 | illegal=0 | ✅ PASS |

Before the fix, `BLT(-1,1)` and `BGEU(-1,1)` would have failed (branch logic had
signed/unsigned swapped), and `MUL`/`DIV` would have silently executed as `ADD`/`XOR`.

---

## 2. VPU instruction regression (`tb_vproc_all_instr`)

DUT: full `fpga/rtl/vpu/*` stack (decoder → FSM → lane → VRF). Previously this
suite only ran against the older `rtl/` tree (172/172 PASS, 2026-05-01) — this is
the **first run against `fpga/rtl/vpu`** specifically.

Covers: ALU VV/VX/VI, VRSUB, logic, shift, VMIN/VMAX, compare (8 funct6), VMULH
family, widening ops, LMUL=2, reductions (VREDSUM/MAX/MIN/MAXU/MINU), OPMVV,
OPMVX.

```
=== Summary: PASS=204  FAIL=0 ===
=== RESULT: ALL PASS ===
```

Expected: `PASS=204 FAIL=0`. Got: `PASS=204 FAIL=0`. ✅

---

## 3–4. AXPY and Matmul benchmarks

DUT: full `pipelined_vpu` (5-stage scalar core) + `vproc_system_wrapper` (VPU),
behavioral DMEM, no UART. Source: `fpga/bench/tb_bench_generic.sv`. Firmware
(`sw/benchmarks/{axpy,matmul}/*_imem.hex`) writes 4 results to a "mailbox" at
DMEM byte address `0x1E0` (see `main.c` in each benchmark folder); testbench
runs for a fixed 20 000-cycle budget then reads the mailbox back.

Note: this is the **first time these benchmarks are run against the `fpga/rtl`
5-stage pipeline** — previously they were only validated against the older
`rtl/` single-cycle core (`tb_riscv_vpu_top`, 221 / 317 cycles respectively,
2026-04/05). The 20 000-cycle budget here is a coarse timeout, not a
cycle-count measurement — use the single-cycle numbers in `BENCHMARK_REPORT.md`
for performance comparison, not this report.

### AXPY (y[i] += a·x[i], N=16, a=3, x[i]=i+1, y[i]=1 initially)

| Mailbox word | Meaning | Expected | Got | Status |
|---|---|---|---|---|
| [0] | y[0] | 4 | 4 | ✅ |
| [1] | y[4] | 16 | 16 | ✅ |
| [2] | y[8] | 28 | 28 | ✅ |
| [3] | y[12] | 40 | 40 | ✅ |

### Matmul 4×4 (C = A·B, A=1..16 row-major, B=all-ones)

Exercises `vmv.v.x` (zero-init accumulator) via the VMERGE datapath — see
correction note in `PROJECT_STATUS.md` issue #7/#23.

| Mailbox word | Meaning | Expected | Got | Status |
|---|---|---|---|---|
| [0] | C[0][0] (row 0 sum) | 10 | 10 | ✅ |
| [1] | C[1][0] (row 1 sum) | 26 | 26 | ✅ |
| [2] | C[2][0] (row 2 sum) | 42 | 42 | ✅ |
| [3] | C[3][0] (row 3 sum) | 58 | 58 | ✅ |

---

## 5. Lena BT.601 grayscale, 128×128

DUT: same as #3/#4, plus DMEM pre-loaded with real RGB pixel data (backdoor
`$readmemh`). Source: `fpga/bench/tb_fpga_imem_lena.sv` (pre-existing test,
not written for this pass). Firmware runs 1024 VPU iterations of BT.601
(`Y = (R×77 + G×150 + B×29) / 256`) and self-detects completion via an
infinite `j 0` loop.

| Metric | Baseline (pre-fix, this session) | After all fixes | Status |
|---|---|---|---|
| Completion cycle | 35863 | 35863 | ✅ identical |
| Y[0..3] | `a1 9f a0 9d` | `a1 9f a0 9d` | ✅ identical |
| Y[4..7] | `9c 9b 9a 99` | `9c 9b 9a 99` | ✅ identical |

Bit-for-bit identical to the pre-fix run captured earlier in this session —
confirms the reset-synchronicity rewrite (#21), the `always_comb` conversion,
and the `CTRL_WIDTH` default fix did not change behavior anywhere this
benchmark exercises.

---

## 6. Full top-level compile / elaborate

`de10_standard_top` → `riscv_vpu_top_fpga` → pipeline + VPU + UART + VGA +
DMEM (M10K behavioral stand-in) + PLL (behavioral stand-in). This is the
closest sim-only proxy for "does the whole FPGA design still build" without
running actual Quartus synthesis.

- **Errors: 0**
- **Warnings:** only pre-existing, already-triaged ones — unconnected debug/
  carry ports (`o_illegal_instr` at the top level since nothing consumes it
  yet, `o_br_less`, `cout`, `cnr`, `o_br_taken`) and benign `$unit` package
  re-elaboration notices from `import tl_pkg::*`. No new warnings, **no latch
  warnings**, introduced by this session's changes.

---

## 7. Shared DMEM bus architecture change (2026-08-02)

Replaced the true dual/multi-port `dmem_qip_wrapper.sv` (separate physical
port for scalar core, VLSU, and video) with a single shared logical port
arbitrated by `fpga/rtl/bus/dmem_arbiter.sv`, fixed priority VLSU > scalar >
video. Motivation: DMEM should be accessed like any other bus peripheral
(the way UART already is), as groundwork for a real SoC where future IP
blocks attach the same way instead of getting a dedicated memory port each.

**Bug found and fixed by this change, not pre-existing:** giving the scalar
core the ability to stall on a denied DMEM access meant a vector instruction
sitting in EX could now be held for an extra cycle for reasons unrelated to
VPU readiness — breaking the implicit assumption that a vector instruction
is dispatched to the VPU exactly once. Fixed with a one-shot dispatch latch
(`vpu_disp_done_r`) in `pipelined_vpu.sv`. This is exactly the kind of bug
`tb_bench_generic.sv`'s idealized dual-port model (fixed before this change)
could never have caught — it's directly exercised by the matmul regression
above, which now hits 96 real scalar/VLSU arbitration conflicts and still
produces the correct result (`10/26/42/58`).

**Regression impact:** zero. Lena grayscale's `Y[0..7]` output and cycle
count (35863) are bit-identical to the pre-change baseline — that program
never has scalar and VLSU contend for DMEM in the same cycle, so the new
stall path is simply never taken there (contrast with matmul, which does
exercise it, above).

### Bug vs. limitation? (follow-up debugging pass, 2026-08-02)

Re-audited specifically to answer this question, beyond what the original
implementation testing covered:

- **Re-read every consumer of `vpu_stall`/`ex_hold`/`mem_stall` in
  `pipelined_vpu.sv`** line by line to confirm no register enable was left
  on the wrong signal (PC/IF-ID/imem_sync → `stall` incl. `ex_hold`; ID/EX,
  EX/MEM → `!ex_hold`; MEM/WB → `!vpu_stall` with an explicit bubble branch
  for `mem_stall`) — all correctly wired, no leftover `!vpu_stall` where
  `!ex_hold` belonged or vice versa.
- **Traced address/data stability under multi-cycle denial analytically**:
  EX/MEM's `alu_result_m`/`rs2_data_m`/`func3_m` are plain flip-flops with
  `!ex_hold` as their only enable — by definition they cannot drift while
  held, so the retried request is provably identical every cycle, not just
  "probably". Confirmed empirically anyway with new test **C8** (5-cycle
  sustained VLSU burst against a held scalar write — correct throughout,
  see table above) and **in production** by the matmul benchmark, which
  hit a real 4-cycle-consecutive denial and still produced the exact
  correct answer.
- **Checked for combinational loops**: `vpu_insn_vld_o` (which feeds
  `vproc_system_wrapper`, whose `vpu_ready` feeds back into `vpu_stall`)
  depends only on registered state (`is_vector_exe`, `vpu_disp_done_r`) —
  no same-cycle loop through the arbiter. `m0_ready_o`'s write-case
  shortcut (`m0_we_i` passed straight through) is safe only because M0 has
  *unconditional* priority (`m0_gnt = m0_req_i` always) — verified this
  isn't a leftover assumption from the old dedicated-port design that no
  longer holds; it still holds by construction.
- **Checked video (M2) under sustained (not just 1-cycle) denial** — new
  test **C9** — holds its last value correctly through 5 consecutive
  losses, refreshes correctly once granted again.

**Conclusion: no correctness bug found.** The real, load-bearing risk of
this design is a **limitation, not a bug** — a bounded starvation window:
because priority is fixed (VLSU always wins), the scalar core can be
denied DMEM for the entire span of a VLSU burst. This is bounded (a single
vector instruction's memory burst is at most `VLEN·LMUL/32` words — 32 in
the worst case at LMUL=8), not unbounded/livelock, and empirically was
only 4 cycles in the matmul benchmark. The **video path has the same
starvation characteristic** (documented above) but degrades safely (stale
frame data, not corrupted). Neither was fixed, because both are exactly
the accepted trade-off of the fixed-priority design decided at the start
of Part A (VLSU > scalar > video, chosen for simplicity over round-robin
fairness) — not something introduced by an implementation mistake.

---

## 8. Sobel edge detection on Lena (new, 2026-08-02)

Full C→RTL→image pipeline, first new benchmark built after the Part A bus
change. **See [`SOBEL_LENA.md`](SOBEL_LENA.md) for the full writeup** —
algorithm, DMEM layout, the two new issues (#24 funct6 shift mismatch, #25
VLSU sub-word addressing) found and worked around while designing it, and
the `make check-isa` build guard against both. Summary: **0/4096 pixel
mismatches, max error 0**, against a pure-Python reference running the
identical integer arithmetic. Result images in `sw/benchmarks/sobel/`:
`sobel_input.png`, `sobel_reference.png`, `sobel_vpu_output.png`,
`sobel_comparison.png`.

---

## 9. EX-stage MEM-forward bug (#26) — found while debugging the user's follow-up question, pre-existing, now fixed

While investigating "if a scalar `lw` is immediately followed by a VPU
`vle32.v`/`vse32.v`, how does the hazard get classified?" (which itself
turned out to work correctly — the generic load-use stall/forward path
doesn't care whether the consumer is scalar or vector, since it only
compares instruction-encoding register field positions), a **separate,
much more serious, pre-existing bug** was found by direct RTL simulation
with a hand-written assembly repro: `pipelined_vpu.sv`'s EX-stage
"forward from MEM" path (`fwd_a`/`fwd_b == 01`) always selected
`alu_result_m`, regardless of whether the MEM-stage instruction's *real*
result actually came from the ALU.

| MEM-stage instruction | `wb_sel_mem` | Real result | Old forward gave |
|---|---|---|---|
| ALU op, AUIPC | `01` | `alu_result_m` | ✅ correct (coincidence) |
| **LUI** | `11` | `imm_m` | ❌ garbage (LUI has no real `rs1`; `alu_result_m` = whatever register `instr[19:15]` decodes to, plus the immediate) |
| **JAL / JALR** | `10` | `pc_four_m` (link address) | ❌ the *jump target*, a different address entirely |

**Confirmed with `git log -- pipelined_vpu.sv`: pre-existing since commit
`71fa990`, long before this session — not introduced by the Part A bus
change.** Not caught by any existing regression because every constant
used in AXPY/matmul/lena_gray/Sobel happens to be either small enough for
`addi` alone or an exact `0x1000` multiple needing only `lui` — neither
form produces the `lui`+`addi` back-to-back pair (`li reg,<32-bit
constant>`'s standard expansion) that triggers the bug. **Any future C
code needing a "non-round" 32-bit constant would have hit this
immediately, silently.**

**Repro (before fix):** `li x7, 0x22222222` (→ `lui x7,0x22222; addi
x7,x7,546`) computed `x7 = 0x22222322` — off by exactly `0x100`, the value
of an unrelated register `x4` that happened to alias `instr[19:15]` of
that specific `lui` encoding.

**Fix:** added `mem_fwd_value`, a `wb_sel_mem`-driven mux (`imm_m` /
`pc_four_m` / `alu_result_m`) feeding `ex1_fwd`/`ex2_fwd` in place of
`alu_result_m` directly — mirroring the WB-stage forward path
(`rf_wdata`/`wb_data`), which was already correctly `wb_sel`-aware and
never had this bug.

**New regression** `fpga/bench/tb_fwd_hazard.sv` (source:
`fpga/bench/asm/fwd_hazard.S`, script: `fpga/sim/run_fwd_hazard.do`)
covers both cases directly, plus the original `lw`→`vle32.v` scenario
that prompted the investigation:

| Case | Expected | Got (after fix) | Status |
|---|---|---|---|
| `li x7,0x22222222` / `0x33333333` (lui+addi, 2 instances) | `22222222`/`33333333` | `22222222`/`33333333` | ✅ PASS |
| `lw x3,0(x4)` immediately followed by `vle32.v v1,(x3)` | loads from `DMEM[0x200..0x20C]` | correct, dumped via `vse32.v` and verified | ✅ PASS |
| `jal x9,jtarget` immediately followed by `sw x9,0(x10)` | link address `0x00000058` | `0x00000058` | ✅ PASS |

**Regression impact of the fix: zero** — the entire existing suite
(arbiter 40/40, fixcheck 10/10, `tb_vproc_all_instr` 204/204, AXPY,
matmul, lena_gray, Sobel) was re-run and produced **bit-identical**
results to before the fix, confirming none of them ever exercised the
buggy path (consistent with the "why wasn't this caught" analysis above).

---

## Firmware provenance — real GNU RISC-V compiler, not hand-assembled

All IMEM `.hex` files used above (except `tb_fixcheck.sv`, which drives RTL
ports directly with no instruction memory at all) come from C sources
compiled with the actual **`riscv64-unknown-elf-gcc`** toolchain
(MSYS2 `mingw-w64-x86_64-riscv64-unknown-elf-gcc`, GCC 15.1.0, installed at
`C:\msys64\mingw64\bin\`), targeting `-march=rv32im_zicsr_zve32x_zvl128b`
— not written by hand and not written by me as raw hex.

Verified 2026-08-01 by rebuilding each `.hex` from its `.c` source with a
fresh `make` invocation and diffing byte-for-byte against the file already
checked into the repo:

| Benchmark | Source | Build recipe | Fresh rebuild vs. checked-in `.hex` |
|---|---|---|---|
| AXPY | `sw/benchmarks/axpy/axpy.c` + `main.c` (uses `<riscv_vector.h>` RVV intrinsics) | `sw/benchmarks/axpy/Makefile` (**new**, added this session) | ✅ byte-identical |
| Matmul | `sw/benchmarks/matmul/matmul.c` + `main.c` (uses `<riscv_vector.h>`, incl. `vmv.v.x`) | `sw/benchmarks/matmul/Makefile` (**new**, added this session) | ✅ byte-identical |
| Lena BT.601 | `sw/benchmarks/lena_gray/lena_gray.c` | `sw/benchmarks/lena_gray/Makefile` (pre-existing) | ✅ byte-identical |

`axpy_imem.hex` and `matmul_imem.hex` were already correct GCC output before
this session — they just had no `Makefile` to reproduce them from, only the
prebuilt `.hex` sitting next to the `.c` source. Added `Makefile` targets
for both (modeled on `lena_gray/Makefile`, using the existing
`sw/benchmarks/common/crt0.S` + `common/link_bench.ld` — infrastructure that
already existed but wasn't wired up for these two benchmarks) so the build
is reproducible with plain `make`, not a one-off manual `gcc` invocation.

**To rebuild any of them:**
```bash
cd sw/benchmarks/axpy && make      # → axpy_imem.hex
cd sw/benchmarks/matmul && make    # → matmul_imem.hex
cd sw/benchmarks/lena_gray && make # → lena_imem.hex + lena_dmem_init.hex
```
(Needs `riscv64-unknown-elf-gcc` on `PATH`, or `RISCV_PREFIX=` override —
see comment at the top of `sw/Makefile`.)

---

## Known gaps NOT covered by this regression (intentionally out of scope)

These are documented in `PROJECT_STATUS.md` and were not part of this pass —
listed here so "clean regression" isn't mistaken for "feature-complete":

- **mul/div/rem (RV32M):** squashed safely (#20), not implemented — no test
  above exercises actual multiply/divide on the *scalar* core (the VPU's
  `vmul`/`vmulh` are unrelated and are covered by test group #2).
- **UART TileLink backpressure/error-response:** the inline UART bus still has no
  `ready`/error path (#22) — not exercised by any test here since it is
  fixed-latency. (DMEM itself is no longer this way — it now goes through a
  real, if simple, synchronous arbiter, §7 above.)
- **`vmv.x.s`** (vector→scalar GPR): still unimplemented (#23) — no test
  above uses it.
- **`vslide1up`/`vslide1down`:** still unimplemented (#13).
- **`vsll`/`vsrl`/`vsra` funct6 mismatch (#24, found 2026-08-02):** these
  RTL encodings don't match real RVV 1.0 — GCC-compiled vector shift code
  would silently execute as multiply (or produce 0). No test above uses a
  vector shift intrinsic, so this isn't triggered here; not fixed this pass.
- **VLSU sub-word addressing (#25, found 2026-08-02):** `addr[1:0]` is
  discarded everywhere in the VLSU/DMEM path — only word-granular vector
  accesses are possible. Forces the upcoming Sobel benchmark to use 4
  bytes/pixel instead of 1; not fixed this pass.
- **UART/VGA hardware paths:** not exercised by any test above (all UART
  smoke-test benches are separately marked ⏳ Pending in `PROJECT_STATUS.md`);
  test #6 only confirms the UART/VGA modules still *compile and elaborate*
  correctly with the reset-sync and `always_comb` changes, not that they
  function correctly on real hardware.
