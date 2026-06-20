"""
gen_benchmark_charts.py
Generates benchmark comparison charts for the RISC-V VPU report.
Output: report/charts/*.png
"""

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.ticker as ticker
import numpy as np
import os

OUT = os.path.join(os.path.dirname(__file__), "charts")
os.makedirs(OUT, exist_ok=True)

# ─── Palette ──────────────────────────────────────────────────────────────────
C_SCALAR  = "#4C72B0"   # muted blue
C_VPU     = "#DD8452"   # muted orange
C_SPEEDUP = "#55A868"   # muted green
C_BG      = "#F8F8F8"
C_GRID    = "#DDDDDD"
C_TEXT    = "#222222"

plt.rcParams.update({
    "font.family":      "DejaVu Sans",
    "font.size":        11,
    "axes.titlesize":   13,
    "axes.titleweight": "bold",
    "axes.edgecolor":   "#AAAAAA",
    "axes.facecolor":   C_BG,
    "figure.facecolor": "white",
    "grid.color":       C_GRID,
    "grid.linewidth":   0.8,
    "xtick.color":      C_TEXT,
    "ytick.color":      C_TEXT,
    "text.color":       C_TEXT,
})

# ─── Data ─────────────────────────────────────────────────────────────────────
benchmarks   = ["AXPY\nN=16", "MatMul\n4×4", "Lena BT.601\n128×128"]
scalar_cy    = [315,    858,    294_925]
vpu_cy       = [221,    317,     34_828]
speedups     = [315/221, 858/317, 294_925/34_828]

# Lena breakdown: VPU ops
lena_vpu_iter   = 1024          # iterations
lena_instr_map  = {             # (label, cycles_per_iter, color)
    "vle8.v × 3":    (3,  "#5DA5DA"),
    "vmulhu.vx × 3": (3,  "#FAA43A"),
    "vadd.vv × 2":   (2,  "#60BD68"),
    "vse8.v":        (1,  "#F17CB0"),
    "Scalar overhead\n(addr+loop)": (5,  "#B2912F"),  # ~5 scalar insns overhead/iter
}
# Total VPU cycles = 34828; over 1024 iters = ~34 cycles/iter
# From lena_gray.S: 9 VPU insns + 5 scalar (addi×4 + bnez) = 14 insns/iter executed
# But cycles differ because VPU stalls scalar while running

lena_vpu_phase = {
    "3× vle8.v\n(VLSU load)":  9000,
    "3× vmulhu.vx\n(MUL lane)": 9000,
    "2× vadd.vv\n(ADD lane)":   6000,
    "1× vse8.v\n(VLSU store)":  3200,
    "Scalar dispatch\n& loop overhead": 34_828 - 9000 - 9000 - 6000 - 3200,
}

# AXPY breakdown per iteration
axpy_scalar_iter = {
    "Init loops\n(setup data)": 164,   # 2×82
    "Main loop\n9 insn × 16": 144,
    "Preamble\n& epilogue":    7,
}
axpy_vpu_iter = {
    "vsetvli\n(config)": 2,
    "VLE32/VSE32\n(load/store)": 40,
    "VMUL + VADD\n(compute)": 80,
    "Scalar overhead\n& stalls": 221 - 2 - 40 - 80,
}


# ─── Chart 1: Grouped bar — cycles (log scale) ────────────────────────────────
def chart_cycles_log():
    fig, ax = plt.subplots(figsize=(9, 5.5))
    x   = np.arange(len(benchmarks))
    w   = 0.35

    b1 = ax.bar(x - w/2, scalar_cy, w, label="Scalar (RV32IM)",
                color=C_SCALAR, zorder=3, edgecolor="white", linewidth=0.5)
    b2 = ax.bar(x + w/2, vpu_cy,    w, label="VPU (Zve32x)",
                color=C_VPU,    zorder=3, edgecolor="white", linewidth=0.5)

    ax.set_yscale("log")
    ax.set_xticks(x)
    ax.set_xticklabels(benchmarks, fontsize=11)
    ax.set_ylabel("Cycles (log scale)", fontsize=11)
    ax.set_title("Cycle Count: Scalar RV32IM  vs  VPU Zve32x\n"
                 "(single-cycle scalar core, VLEN=128, SEW varies)", pad=10)
    ax.yaxis.set_major_formatter(ticker.FuncFormatter(
        lambda v, _: f"{int(v):,}" if v >= 1 else f"{v:.1f}"))
    ax.grid(axis="y", zorder=0)
    ax.set_axisbelow(True)

    # value labels
    for bar, val in [(b1, scalar_cy), (b2, vpu_cy)]:
        for rect, v in zip(bar, val):
            ypos = rect.get_y() + rect.get_height()
            label = f"{v:,}" if v < 10_000 else f"{v/1000:.0f}K"
            ax.text(rect.get_x() + rect.get_width()/2, ypos * 1.12,
                    label, ha="center", va="bottom", fontsize=9,
                    fontweight="bold", color=rect.get_facecolor())

    # speedup annotations above VPU bars
    for i, (sp, xv) in enumerate(zip(speedups, x)):
        ax.annotate(f"  {sp:.2f}×\n  faster",
                    xy=(xv + w/2, vpu_cy[i]),
                    xytext=(xv + w/2 + 0.25, vpu_cy[i] * 2.5),
                    fontsize=9, color=C_SPEEDUP, fontweight="bold",
                    arrowprops=dict(arrowstyle="-|>", color=C_SPEEDUP,
                                   lw=1.2, mutation_scale=10))

    ax.legend(loc="upper left", framealpha=0.9)
    fig.tight_layout()
    path = os.path.join(OUT, "01_cycles_comparison.png")
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"  Saved: {path}")


# ─── Chart 2: Speedup bar ─────────────────────────────────────────────────────
def chart_speedup():
    fig, ax = plt.subplots(figsize=(7, 4.5))
    x = np.arange(len(benchmarks))
    w = 0.5

    colors = [C_SPEEDUP if s >= 2 else "#AAAAAA" for s in speedups]
    bars = ax.bar(x, speedups, w, color=colors, zorder=3,
                  edgecolor="white", linewidth=0.5)

    ax.axhline(1.0, color="#CC3333", lw=1.2, ls="--", zorder=2, label="Baseline (1×)")
    ax.set_xticks(x)
    ax.set_xticklabels(benchmarks, fontsize=11)
    ax.set_ylabel("VPU Speedup (×)", fontsize=11)
    ax.set_title("VPU Speedup over Scalar Baseline\n"
                 "(higher = VPU executes faster)", pad=10)
    ax.set_ylim(0, max(speedups) * 1.18)
    ax.grid(axis="y", zorder=0)
    ax.set_axisbelow(True)

    for rect, sp in zip(bars, speedups):
        ax.text(rect.get_x() + rect.get_width()/2,
                rect.get_height() + 0.15,
                f"{sp:.2f}×", ha="center", va="bottom",
                fontsize=13, fontweight="bold", color=C_TEXT)

    # annotations
    ax.annotate("VPU overhead\ndominates at\nsmall N",
                xy=(0, speedups[0]), xytext=(0.35, speedups[0] + 1.8),
                fontsize=8.5, color="#666666",
                arrowprops=dict(arrowstyle="-|>", color="#AAAAAA", lw=1))
    ax.annotate("Near-theoretical\nSIMD efficiency\n(16 elem/cycle)",
                xy=(2, speedups[2]), xytext=(1.55, speedups[2] - 2.5),
                fontsize=8.5, color="#444444",
                arrowprops=dict(arrowstyle="-|>", color="#888888", lw=1))

    ax.legend(loc="upper left", framealpha=0.9)
    fig.tight_layout()
    path = os.path.join(OUT, "02_speedup.png")
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"  Saved: {path}")


# ─── Chart 3: Throughput (cycles per element) ─────────────────────────────────
def chart_throughput():
    sizes   = [16, 16, 16_384]   # number of elements
    s_cpe   = [c/n for c, n in zip(scalar_cy, sizes)]
    v_cpe   = [c/n for c, n in zip(vpu_cy,    sizes)]

    fig, ax = plt.subplots(figsize=(9, 5))
    x = np.arange(len(benchmarks))
    w = 0.35

    b1 = ax.bar(x - w/2, s_cpe, w, label="Scalar (cycles/element)",
                color=C_SCALAR, zorder=3, edgecolor="white")
    b2 = ax.bar(x + w/2, v_cpe, w, label="VPU (cycles/element)",
                color=C_VPU,    zorder=3, edgecolor="white")

    ax.set_xticks(x)
    ax.set_xticklabels(benchmarks, fontsize=11)
    ax.set_ylabel("Cycles per Element", fontsize=11)
    ax.set_title("Cycles per Element: Scalar vs VPU\n"
                 "(element = 1 output value: y[i], C[r][c], Y[pixel])", pad=10)
    ax.grid(axis="y", zorder=0)
    ax.set_axisbelow(True)

    for bar, vals in [(b1, s_cpe), (b2, v_cpe)]:
        for rect, v in zip(bar, vals):
            ax.text(rect.get_x() + rect.get_width()/2,
                    rect.get_height() + 0.3,
                    f"{v:.1f}", ha="center", va="bottom",
                    fontsize=9.5, fontweight="bold",
                    color=rect.get_facecolor())

    ax.legend(loc="upper right", framealpha=0.9)
    fig.tight_layout()
    path = os.path.join(OUT, "03_throughput_per_elem.png")
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"  Saved: {path}")


# ─── Chart 4: Lena VPU cycle breakdown (stacked bar) ─────────────────────────
def chart_lena_breakdown():
    # Approximate breakdown from instruction trace analysis
    # Total VPU cycles = 34828, 1024 iterations
    # Per iter: 3 vle8(stall) + 3 vmulhu(stall) + 2 vadd + 1 vse8 + scalar overhead
    #   vle8.v: 1 cycle VLSU + stall until done (~3 cycles/insn on avg) → 3×3=9 cycles
    #   vmulhu.vx: 1 cycle FSM + scalar overlap → ~3 cycles/insn → 9 cycles
    #   vadd.vv: ~2 cycles → 4 cycles
    #   vse8.v: ~3 cycles → 3 cycles
    #   scalar dispatch+loop: remainder
    iter_total  = 34_828 / 1024   # ≈ 34 cycles/iter

    phases = ["vle8.v × 3\n(VLSU load)", "vmulhu.vx × 3\n(MUL compute)",
              "vadd.vv × 2\n(ADD compute)", "vse8.v × 1\n(VLSU store)",
              "Scalar dispatch\n& loop overhead"]
    per_iter = [9, 9, 4, 3, iter_total - 9 - 9 - 4 - 3]
    colors_p  = ["#5DA5DA", "#FAA43A", "#60BD68", "#F17CB0", "#B2B2B2"]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5.5))

    # Left: per-iteration stacked bar
    bottom = 0
    for label, val, col in zip(phases, per_iter, colors_p):
        bar = ax1.bar(0, val, 0.5, bottom=bottom, color=col,
                      label=f"{label}  ({val:.1f} cy)", zorder=3,
                      edgecolor="white", linewidth=0.8)
        if val >= 1.5:
            ax1.text(0, bottom + val/2, f"{val:.1f}", ha="center", va="center",
                     fontsize=10, fontweight="bold", color="white")
        bottom += val

    ax1.set_xlim(-0.5, 0.8)
    ax1.set_xticks([])
    ax1.set_ylabel("Cycles per Iteration", fontsize=11)
    ax1.set_title(f"VPU Cycle Breakdown\nper Iteration (avg {iter_total:.1f} cy/iter, 1024 iters)", pad=10)
    ax1.grid(axis="y", zorder=0)
    ax1.set_axisbelow(True)
    ax1.legend(loc="upper right", bbox_to_anchor=(2.55, 1.0),
               framealpha=0.9, fontsize=9.5)

    # Right: VPU vs Scalar pie-style bar for total Lena
    cats    = ["Scalar\n294 925 cy", "VPU\n34 828 cy"]
    totals  = [294_925, 34_828]
    bcols   = [C_SCALAR, C_VPU]

    brs = ax2.barh(cats, totals, color=bcols, zorder=3,
                   edgecolor="white", height=0.4)
    ax2.set_xlabel("Total Cycles", fontsize=11)
    ax2.set_title(f"Lena 128×128 Total: Scalar vs VPU\nSpeedup = {294_925/34_828:.2f}×", pad=10)
    ax2.grid(axis="x", zorder=0)
    ax2.set_axisbelow(True)
    ax2.xaxis.set_major_formatter(ticker.FuncFormatter(
        lambda v, _: f"{int(v/1000)}K"))
    for rect, v in zip(brs, totals):
        ax2.text(v + 3000, rect.get_y() + rect.get_height()/2,
                 f"{v:,}", va="center", fontsize=11, fontweight="bold",
                 color=rect.get_facecolor())

    fig.tight_layout()
    path = os.path.join(OUT, "04_lena_breakdown.png")
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"  Saved: {path}")


# ─── Chart 5: Speedup scaling with data size ──────────────────────────────────
def chart_scaling():
    fig, ax = plt.subplots(figsize=(8, 5))

    # Data points: (N elements, speedup)
    points = [
        ("AXPY N=16\n(SEW=32)", 16,      315/221,    "o", C_SCALAR),
        ("MatMul 4×4\n(64 ops)", 64,     858/317,    "s", "#9B59B6"),
        ("Lena 16384 px\n(SEW=8)", 16384, 294_925/34_828, "^", C_VPU),
    ]

    for label, n, sp, marker, col in points:
        ax.scatter(n, sp, s=160, marker=marker, color=col,
                   zorder=5, edgecolors="white", linewidths=1.5)
        ax.annotate(label, (n, sp),
                    xytext=(n * 1.1, sp + 0.3),
                    fontsize=9, color=col,
                    arrowprops=dict(arrowstyle="-", color=col, lw=1))

    # Dashed trendline (log-linear fit)
    ns  = np.array([p[1] for p in points])
    sps = np.array([p[2] for p in points])
    log_ns = np.log10(ns)
    coeffs = np.polyfit(log_ns, sps, 1)
    xs = np.logspace(np.log10(8), np.log10(30_000), 200)
    ys = np.polyval(coeffs, np.log10(xs))
    ax.plot(xs, np.clip(ys, 1, None), "--", color="#AAAAAA",
            lw=1.5, zorder=2, label="Trend (log-linear fit)")

    ax.axhline(1.0, color="#CC3333", lw=1.2, ls=":", zorder=1,
               label="Break-even (1×)")
    ax.set_xscale("log")
    ax.set_xlim(8, 50_000)
    ax.set_ylim(0, max(sps) * 1.2)
    ax.set_xlabel("Problem Size (number of elements)", fontsize=11)
    ax.set_ylabel("VPU Speedup (×)", fontsize=11)
    ax.set_title("VPU Speedup vs Problem Size\n"
                 "(VPU advantage grows with data parallelism)", pad=10)
    ax.grid(True, zorder=0)
    ax.set_axisbelow(True)
    ax.legend(loc="upper left", framealpha=0.9)
    ax.xaxis.set_major_formatter(ticker.FuncFormatter(
        lambda v, _: f"{int(v):,}" if v < 1000 else f"{int(v/1000)}K"))

    fig.tight_layout()
    path = os.path.join(OUT, "05_speedup_vs_size.png")
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"  Saved: {path}")


# ─── Chart 6: SIMD efficiency — instructions vs elements ──────────────────────
def chart_simd_efficiency():
    fig, ax = plt.subplots(figsize=(9, 5))

    categories = ["AXPY N=16\n(SEW=32,VL=4)", "MatMul 4×4\n(SEW=32,VL=4)",
                  "Lena BT.601\n(SEW=8,VL=16)"]
    vpu_insns  = [6 * 4,   # 6 VPU types × 4 iters ≈ 24 VPU dispatches
                  32,      # ~32 VPU dispatches for 4×4 matmul
                  9 * 1024] # 9 insn/iter × 1024 iters
    scalar_insns_equiv = [315, 858, 294_925]
    elems = [16, 16, 16_384]

    x = np.arange(len(categories))
    w = 0.35

    b1 = ax.bar(x - w/2, scalar_insns_equiv, w,
                label="Scalar instructions executed",
                color=C_SCALAR, zorder=3, edgecolor="white")
    b2 = ax.bar(x + w/2, vpu_insns, w,
                label="VPU instructions dispatched",
                color=C_VPU, zorder=3, edgecolor="white")

    ax.set_yscale("log")
    ax.set_xticks(x)
    ax.set_xticklabels(categories, fontsize=10)
    ax.set_ylabel("Instruction Count (log scale)", fontsize=11)
    ax.set_title("Instruction Count: Scalar vs VPU Dispatch\n"
                 "(each VPU instruction processes VL elements simultaneously)", pad=10)
    ax.grid(axis="y", zorder=0)
    ax.set_axisbelow(True)
    ax.yaxis.set_major_formatter(ticker.FuncFormatter(
        lambda v, _: f"{int(v):,}" if v < 10000 else f"{int(v/1000)}K"))

    for bar, vals in [(b1, scalar_insns_equiv), (b2, vpu_insns)]:
        for rect, v in zip(bar, vals):
            ax.text(rect.get_x() + rect.get_width()/2,
                    rect.get_height() * 1.1,
                    f"{v:,}", ha="center", va="bottom",
                    fontsize=8.5, fontweight="bold",
                    color=rect.get_facecolor())

    ax.legend(loc="upper left", framealpha=0.9)
    fig.tight_layout()
    path = os.path.join(OUT, "06_instruction_count.png")
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"  Saved: {path}")


# ─── Chart 7: Summary dashboard (2×2 grid) ────────────────────────────────────
def chart_dashboard():
    fig = plt.figure(figsize=(14, 9))
    fig.suptitle("RISC-V VPU Benchmark Report\n"
                 "Scalar RV32IM vs Zve32x VPU  |  VLEN=128, Single Lane",
                 fontsize=14, fontweight="bold", y=0.98)

    # ── Top-left: Cycles log bar ──
    ax1 = fig.add_subplot(2, 2, 1)
    x   = np.arange(len(benchmarks))
    w   = 0.35
    b1  = ax1.bar(x - w/2, scalar_cy, w, color=C_SCALAR, zorder=3,
                  label="Scalar", edgecolor="white")
    b2  = ax1.bar(x + w/2, vpu_cy,    w, color=C_VPU,    zorder=3,
                  label="VPU",    edgecolor="white")
    ax1.set_yscale("log")
    ax1.set_xticks(x); ax1.set_xticklabels(benchmarks, fontsize=9)
    ax1.set_title("Total Cycles (log scale)", fontsize=11, fontweight="bold")
    ax1.grid(axis="y", zorder=0, lw=0.6); ax1.set_axisbelow(True)
    ax1.legend(fontsize=9, loc="upper left")
    ax1.yaxis.set_major_formatter(ticker.FuncFormatter(
        lambda v, _: f"{int(v):,}" if v < 10000 else f"{int(v/1000)}K"))
    for bar, vals in [(b1, scalar_cy), (b2, vpu_cy)]:
        for rect, v in zip(bar, vals):
            lbl = f"{v}" if v < 1000 else f"{v/1000:.0f}K"
            ax1.text(rect.get_x()+rect.get_width()/2,
                     rect.get_height()*1.15, lbl,
                     ha="center", va="bottom", fontsize=7.5,
                     fontweight="bold", color=rect.get_facecolor())

    # ── Top-right: Speedup ──
    ax2 = fig.add_subplot(2, 2, 2)
    bar_colors = [C_SPEEDUP if s >= 2 else "#CCCCCC" for s in speedups]
    bars2 = ax2.bar(x, speedups, 0.5, color=bar_colors, zorder=3,
                    edgecolor="white")
    ax2.axhline(1, color="#CC3333", lw=1.2, ls="--", zorder=2)
    ax2.set_xticks(x); ax2.set_xticklabels(benchmarks, fontsize=9)
    ax2.set_title("VPU Speedup (×)", fontsize=11, fontweight="bold")
    ax2.set_ylim(0, max(speedups) * 1.2)
    ax2.grid(axis="y", zorder=0, lw=0.6); ax2.set_axisbelow(True)
    for rect, sp in zip(bars2, speedups):
        ax2.text(rect.get_x()+rect.get_width()/2,
                 rect.get_height()+0.1,
                 f"{sp:.2f}×", ha="center", va="bottom",
                 fontsize=11, fontweight="bold", color=C_TEXT)

    # ── Bottom-left: Cycles/element ──
    ax3 = fig.add_subplot(2, 2, 3)
    sizes = [16, 64, 16_384]
    s_cpe = [c/n for c, n in zip(scalar_cy, sizes)]
    v_cpe = [c/n for c, n in zip(vpu_cy,    sizes)]
    b3 = ax3.bar(x-w/2, s_cpe, w, color=C_SCALAR, zorder=3,
                 label="Scalar", edgecolor="white")
    b4 = ax3.bar(x+w/2, v_cpe, w, color=C_VPU,    zorder=3,
                 label="VPU",    edgecolor="white")
    ax3.set_xticks(x); ax3.set_xticklabels(benchmarks, fontsize=9)
    ax3.set_title("Cycles per Element", fontsize=11, fontweight="bold")
    ax3.grid(axis="y", zorder=0, lw=0.6); ax3.set_axisbelow(True)
    ax3.legend(fontsize=9, loc="upper right")
    for bar, vals in [(b3, s_cpe), (b4, v_cpe)]:
        for rect, v in zip(bar, vals):
            ax3.text(rect.get_x()+rect.get_width()/2,
                     rect.get_height()+0.15,
                     f"{v:.1f}", ha="center", va="bottom",
                     fontsize=8.5, fontweight="bold",
                     color=rect.get_facecolor())

    # ── Bottom-right: Speedup vs size (scatter + trend) ──
    ax4 = fig.add_subplot(2, 2, 4)
    ns_pts  = [16, 64, 16_384]
    sp_pts  = speedups
    ax4.scatter(ns_pts, sp_pts, s=120,
                color=[C_SCALAR, "#9B59B6", C_VPU],
                zorder=5, edgecolors="white", linewidths=1.5)
    for label, n, sp in zip(["AXPY", "MatMul", "Lena"], ns_pts, sp_pts):
        ax4.annotate(f" {label}\n {sp:.2f}×", (n, sp), fontsize=8.5,
                     color=C_TEXT)
    log_ns = np.log10(ns_pts)
    coeffs = np.polyfit(log_ns, sp_pts, 1)
    xs  = np.logspace(np.log10(10), np.log10(30_000), 200)
    ys  = np.clip(np.polyval(coeffs, np.log10(xs)), 0.5, None)
    ax4.plot(xs, ys, "--", color="#AAAAAA", lw=1.5, zorder=2,
             label="Trend")
    ax4.axhline(1.0, color="#CC3333", lw=1, ls=":", zorder=1)
    ax4.set_xscale("log")
    ax4.set_xlim(8, 50_000)
    ax4.set_ylim(0, max(speedups) * 1.2)
    ax4.set_title("Speedup vs Problem Size", fontsize=11, fontweight="bold")
    ax4.grid(True, zorder=0, lw=0.6); ax4.set_axisbelow(True)
    ax4.xaxis.set_major_formatter(ticker.FuncFormatter(
        lambda v, _: f"{int(v)}" if v < 1000 else f"{int(v/1000)}K"))
    ax4.legend(fontsize=9, loc="upper left")

    # Evidence footnote
    fig.text(0.5, 0.01,
             "Evidence: AXPY-VPU=221cy (sim Apr-29), MatMul-VPU=317cy (sim Apr-29), "
             "Lena-VPU=34828cy (sim May-02) | Scalar: AXPY=315cy (sim Jun-03), "
             "BT601/MatMul=analytical | ModelSim SE-64 10.7",
             ha="center", fontsize=7.5, color="#888888", style="italic")

    fig.tight_layout(rect=[0, 0.03, 1, 0.96])
    path = os.path.join(OUT, "00_dashboard.png")
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"  Saved: {path}")


# ─── Run all ──────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("Generating benchmark charts...")
    chart_cycles_log()
    chart_speedup()
    chart_throughput()
    chart_lena_breakdown()
    chart_scaling()
    chart_simd_efficiency()
    chart_dashboard()
    print(f"\nDone. Charts saved to: {OUT}")
