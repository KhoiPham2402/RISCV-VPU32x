# Sobel Edge Detection on Lena — 2026-08-02

Full C→RTL→image pipeline: a Sobel edge-detection kernel, written in C,
compiled with the real `riscv64-unknown-elf-gcc` toolchain (RVV intrinsics),
run on the RISC-V+VPU system (`fpga/rtl` — 5-stage pipeline + VPU, through
the new single shared DMEM bus from this session's Part A), against the same
Lena source image `lena_gray` uses, with the result verified pixel-for-pixel
against a pure-Python reference and rendered as a PNG.

**Result: PASS. 0/4096 mismatches, max error 0.**

| Item | Value |
|---|---|
| Firmware | `sw/benchmarks/sobel/sobel.c`, built via `sw/benchmarks/sobel/Makefile` |
| Compiler | `riscv64-unknown-elf-gcc` (GCC 15.1.0), `-march=rv32im_zicsr_zve32x_zvl128b` |
| ISA safety check | `make check-isa` — disassembly-grep guard, **PASS** (no forbidden instructions) |
| Testbench | `fpga/bench/tb_sobel_lena.sv` — `fpga/sim/run_sobel_lena.do` |
| Log | [`logs/sobel_lena.log`](logs/sobel_lena.log) |
| Cycles | 93766 |
| Arbitration conflicts | 0 (scalar/VLSU never contend for DMEM in this program) |
| Pixels compared | 4096 (62×62 = 3844 interior, rest border = 0 both sides) |
| Mismatches | **0** |
| Max error | **0** |

---

## 1. Why this needed the Part A bus change first

`sobel.c` runs on `fpga/rtl/pipeline/pipelined_vpu.sv` + `fpga/rtl/vpu/vproc_system_wrapper.sv`,
exactly the same DUT as the AXPY/matmul/lena_gray benchmarks — it did not
strictly *require* the DMEM architecture change to function (the old
dual-port model would have worked fine functionally), but it's the first
new benchmark built after that change, and this run — together with the
matmul regression in Part A — is direct evidence the shared-bus
architecture doesn't cost correctness even under real scalar/VLSU
contention (matmul saw 96 real conflicts; this program saw 0, since its
inner loop is VLSU-heavy with comparatively little scalar load/store
traffic in between vector ops).

## 2. Why 64×64 pixels, 4 bytes/pixel (not 128×128 @ 1 byte/pixel like lena_gray)

**Project issue #25** (found while designing this benchmark): `vproc_vec_lsu.sv`'s
address arithmetic and every DMEM consumer (`dmem_model_sp.sv`, real
`dmem_qip_wrapper.sv`) index memory with `addr[15:2]` — the low 2 address
bits are discarded, so there is no byte or halfword rotation for vector
loads. A Sobel kernel's ±1-pixel horizontal tap is only a valid, *distinct*,
aligned load if one pixel occupies exactly one 32-bit word. At 1 byte/pixel
(lena_gray's convention) the left/right taps would silently alias onto the
center pixel — wrong results, not a crash, so this had to be caught at
design time rather than debugged after the fact. 128×128 at 4 bytes/pixel
would use the entire 64 KB DMEM with no room for a separate output plane, so
the image is downsized to 64×64 instead of changing the memory layout.
Confirmed acceptable with the user before implementation.

## 3. Why no shift instructions, no `vmacc`, no widening

**Project issue #24** (found and independently verified while designing this
benchmark): `vproc_vdecoder.sv`/`vproc_processor_lane.sv` encode
`vsll`/`vsrl`/`vsra` with funct6 values (`010101`/`010000`/`010010`) that do
not match real RVV 1.0 (`100101`/`101000`/`101001`). Real RVV `vsll`
(funct6=100101) collides with this RTL's own `VMUL` encoding — GCC-compiled
vector shift code would silently execute as a multiply instead (or hit no
case at all for `vsrl`/`vsra`, producing 0). `sobel.c` computes "×2" via
`vadd_vv(x,x)` instead of a shift, and doesn't use `vmacc` (confirmed absent
from this RTL, same as `matmul.c`'s workaround) or widening instructions
(rejected during planning as higher-risk/less-proven than plain SEW=32 ops
for a first implementation — see the approved plan for the full comparison).

The `make check-isa` target in `sw/benchmarks/sobel/Makefile` disassembles
the built ELF and greps for `vsll|vsrl|vsra|vmacc|vslide*|vnclip|vnsr*|vrgather|vmv.x.s`
and scalar `mul/div/rem`, failing the build if any appear — this is a
standing guard against issue #24 (and the already-fixed-but-still-squashed
issue #20) for this benchmark and any future edits to it, not a one-time
manual check.

**Actual instruction mix used** (from `sobel.dis`, `make disasm`):
`vle32.v` ×8, `vse32.v` ×1, `vadd.vv` ×13, `vsub.vv` ×2, `vminu.vv` ×2,
`vmaxu.vv` ×2, `vminu.vx` ×1 per inner-loop iteration. (A scalar `slli`
also appears in the disassembly — that's the RV32I base ISA doing normal
C pointer-arithmetic address computation, unrelated to issue #24, which is
specifically about the *vector* shift encoding.)

## 4. Algorithm

3×3 Sobel, `|Gx|+|Gy|` magnitude approximation (no `sqrt` unit exists in
this VPU), saturated to 255:

```
posX = 2·C(r,c+1) + C(r-1,c+1) + C(r+1,c+1)     negX = 2·C(r,c-1) + C(r-1,c-1) + C(r+1,c-1)
posY = 2·C(r+1,c) + C(r+1,c-1) + C(r+1,c+1)     negY = 2·C(r-1,c) + C(r-1,c-1) + C(r-1,c+1)
|Gx| = max(posX,negX) − min(posX,negX)           |Gy| = max(posY,negY) − min(posY,negY)
out  = min(|Gx| + |Gy|, 255)
```

All arithmetic unsigned SEW=32/LMUL=1 (VLMAX=4 for VLEN=128). Every
intermediate sum is ≤ 1020 (4 taps × 255), so there's no overflow risk at
any step and no widening is needed. `|Gx|`/`|Gy|` use `max−min` instead of a
compare+select-based `abs()` since both operands are non-negative pixel-tap
sums by construction — `vminu`/`vmaxu` alone are sufficient and simpler.
Border rows/columns (0 and 63) are left at 0 by the output-plane pre-zero in
`prep_sobel.py`; the C loop only writes the interior `r,c ∈ [1,62]`.

## 5. DMEM layout

| Range | Contents |
|---|---|
| `0x0000–0x0FFF` | unused (reserved for `.bss`/stack by `sw/crt0.S`) |
| `0x1000–0x4FFF` | input: 64×64 grayscale, 1 pixel/word (word 1024..5119) |
| `0x5000–0x8FFF` | output: 64×64 edge magnitude, pre-zeroed (word 5120..9215) |
| `0x9000–0xFFFF` | unused |

## 6. Pipeline

```
sw/benchmarks/sobel/prep_sobel.py
    reads sw/benchmarks/lena_gray/lena_raw.png (same source lena_gray uses)
    -> BT.601 grayscale, resized 64x64 (identical formula to prep_lena.py)
    -> sobel_input.png, sobel_dmem_init.hex, sobel_ref.hex, sobel_reference.png

sw/benchmarks/sobel/Makefile  (make)
    sobel.c --[riscv64-unknown-elf-gcc]--> sobel.elf --[objcopy]--> sobel.bin
    --[elf2hex_lines.py]--> sobel_imem.hex
    make check-isa: disassemble + grep forbidden instructions -> PASS

fpga/sim/run_sobel_lena.do  (vsim)
    fpga/bench/tb_sobel_lena.sv: backdoor-load sobel_imem.hex + sobel_dmem_init.hex
    into pipelined_vpu + vproc_system_wrapper + dmem_arbiter + dmem_model_sp
    -> run to completion (j-done marker) -> dump full DMEM -> sobel_dmem_out.hex

sw/benchmarks/sobel/reconstruct_sobel.py
    sobel_dmem_out.hex vs. sobel_ref.hex, zero-tolerance exact match
    -> sobel_vpu_output.png, sobel_comparison.png
```

Every step is a plain `make`/`vsim -c -do`/`python` command from the repo
root or the benchmark directory — no manual/undocumented steps, matching
this session's earlier axpy/matmul/lena_gray provenance work.

## 7. Result images

- `sw/benchmarks/sobel/sobel_input.png` — 64×64 grayscale input
- `sw/benchmarks/sobel/sobel_reference.png` — pure-Python Sobel reference
- `sw/benchmarks/sobel/sobel_vpu_output.png` — actual VPU output (pixel-identical to the reference)
- `sw/benchmarks/sobel/sobel_comparison.png` — input | reference | VPU output side by side

## 8. Known gaps not exercised by this benchmark

- **Borders** (row/col 0 and 63) are simply left at 0 — no reflect/replicate/wrap
  boundary handling. Standard simplification for a first implementation.
- **Only exercises `vle32.v`/`vse32.v`/`vadd.vv`/`vsub.vv`/`vminu.vv`/`vmaxu.vv`/`vminu.vx`** —
  does not exercise masking, reductions, widening, or LMUL>1, all of which
  are already covered by `tb_vproc_all_instr` (204/204 PASS) instead.
- **Issues #24 and #25 are avoided, not fixed** by this benchmark — see
  `PROJECT_STATUS.md` for their tracked status.
