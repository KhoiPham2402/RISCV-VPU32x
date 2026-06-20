# run_fpga_lena_sim.do — Compile and simulate tb_fpga_lena_sim
#
# Run from project root in ModelSim:
#   vsim -do run_fpga_lena_sim.do
#
# What it tests:
#   • Send 3×16384 bytes (R/G/B planes) via UART to firmware running on
#     riscv_vpu_top_fpga with behavioral replacements for Quartus IPs.
#   • VPU computes BT.601 grayscale with vmulhu.vx + vadd.vv.
#   • Firmware sends ACK byte 0xAA when done.
#   • Testbench reports [PASS] if ACK received, [FAIL] otherwise.
#
# Behavioral IP replacements (no Quartus license needed):
#   fpga/ip/dmem_bank.sv  — 8-bit TDP SRAM (registered output, OLD_DATA)
#   fpga/ip/pll.sv        — divide-by-2 pixel clock, locked after 16 cycles

set ROOT [file normalize [pwd]]
set FPGA [file join $ROOT fpga]
set BENCH [file join $ROOT bench]

# ── Ensure uart_lena.hex is in fpga/ (imem_sync default path) ─────────────────
set HEX_SRC [file join $ROOT uart_lena.hex]
set HEX_DST [file join $FPGA uart_lena.hex]
if {[file exists $HEX_SRC] && ![file exists $HEX_DST]} {
    file copy $HEX_SRC $HEX_DST
    puts "INFO: Copied uart_lena.hex → fpga/"
} elseif {![file exists $HEX_DST]} {
    puts "ERROR: uart_lena.hex not found."
    puts "       Build it: cd sw && make PROG=uart_lena && cd .."
    quit -f
}

# ── Create/refresh work library ───────────────────────────────────────────────
catch {vdel -lib work -all}
vlib work
vmap work work

# ── Compile in dependency order ───────────────────────────────────────────────

# 1. TileLink bus package (must be first — used by uart and top)
vlog -sv -work work [file join $FPGA rtl bus tl_pkg.sv]

# 2. Behavioral IP replacements (before any module that instantiates them)
vlog -sv -work work [file join $FPGA ip pll.sv]
vlog -sv -work work [file join $FPGA ip dmem_bank.sv]
vlog -sv -work work [file join $FPGA ip imem_b0.sv]
vlog -sv -work work [file join $FPGA ip imem_b1.sv]
vlog -sv -work work [file join $FPGA ip imem_b2.sv]
vlog -sv -work work [file join $FPGA ip imem_b3.sv]

# 3. Pipeline leaf cells (order follows sources.tcl)
foreach f {
    full_adder.sv eight_bit_adder.sv adder.sv
    d_ff.sv register.sv
    decoder5to32.sv Regfile.sv register_file.sv
    mux2to1.sv mux2X1.sv mux4to1.sv mux8to1.sv mux32to1.sv
    immgen.sv
    mag_comparator.sv mag_comparator8.sv brc_comparator.sv brc.sv
    word_and.sv word_or.sv word_xor.sv
    barrel_shifter_32bit.sv barrel_shifter_32bit_left.sv
    alu.sv imem_sync.sv control_unit.sv pipelined_vpu.sv
} {
    vlog -sv -work work [file join $FPGA rtl pipeline $f]
}

# 4. UART
vlog -sv -work work [file join $FPGA rtl uart uart.sv]

# 5. VPU modules
foreach f {
    vproc_adder.sv vproc_mul.sv vproc_logic.sv vproc_shifter.sv
    vproc_compare.sv vproc_compare_combine.sv
    vproc_minmax.sv vproc_reduction.sv vproc_merge_unit.sv
    vproc_processor_lane.sv vproc_vregfile.sv vproc_mux_cells.sv
    vproc_mask_enable.sv vproc_mask_write_buffer.sv
    vproc_vcsr.sv vproc_cfg_encoder.sv vproc_cycle_counter.sv
    vproc_vrf_addr_gen.sv vproc_scalar_expand.sv
    vproc_fsm.sv vproc_fifo.sv vproc_vdecoder.sv
    vproc_vec_lsu.sv vproc_system_wrapper.sv
} {
    vlog -sv -work work [file join $FPGA rtl vpu $f]
}

# 6. DMEM M10K wrapper
vlog -sv -work work [file join $FPGA rtl mem dmem_qip_wrapper.sv]

# 7. VGA timing and controller
vlog -sv -work work [file join $FPGA rtl hdmi vga_timing.sv]
vlog -sv -work work [file join $FPGA rtl vga vga_ctrl.sv]

# 8. FPGA top (with UART parameters for sim override)
vlog -sv -work work [file join $FPGA rtl top riscv_vpu_top_fpga.sv]

# 9. Testbench
vlog -sv -work work [file join $BENCH tb_fpga_lena_sim.sv]

puts "INFO: Compilation complete — launching simulation."

# ── Simulate ──────────────────────────────────────────────────────────────────
vsim -voptargs=+acc work.tb_fpga_lena_sim

# Print useful signals to transcript on changes (optional — comment out for speed)
# log -r /*

run -all
