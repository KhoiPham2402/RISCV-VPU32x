# run_lena_mini_sim.do — Build uart_lena_mini firmware and simulate end-to-end
#
# Usage (from project root in ModelSim):
#   vsim -c -do run_lena_mini_sim.do
#
# What it verifies:
#   Sends 3×16 bytes (R=0x64, G=0x96, B=0x32) via UART.
#   VPU computes BT.601 Y = 30+87+5 = 122 = 0x7A per pixel.
#   Firmware sends ACK 0xAA on completion.
#   Total sim time: ~96 µs (48 bytes × 10 bits × 200 ns) — completes in seconds.

set ROOT  [file normalize [pwd]]
set FPGA  [file join $ROOT fpga]
set SW    [file join $ROOT sw]
set BENCH [file join $ROOT bench]

# ── Build firmware ─────────────────────────────────────────────────────────────
puts "INFO: Building uart_lena_mini firmware..."
set rc [catch {exec cmd /c "cd \"$SW\" && make uart_lena_mini.hex"} msg]
if {$rc != 0} {
    puts "WARN: make failed. Using existing uart_lena_mini.hex if present."
    puts "      Error: $msg"
    puts "      To build: cd sw && make uart_lena_mini.hex"
}

# ── Copy hex to fpga/ (imem_sync reads fpga/uart_lena.hex) ────────────────────
set HEX_SRC [file join $ROOT uart_lena_mini.hex]
set HEX_DST [file join $FPGA uart_lena.hex]
if {[file exists $HEX_SRC]} {
    file copy -force $HEX_SRC $HEX_DST
    puts "INFO: Copied uart_lena_mini.hex → fpga/uart_lena.hex"
} elseif {![file exists $HEX_DST]} {
    puts "ERROR: Neither uart_lena_mini.hex nor fpga/uart_lena.hex found."
    puts "       Run: cd sw && make uart_lena_mini.hex"
    quit -f
}

# ── Create work library ────────────────────────────────────────────────────────
catch {vdel -lib work -all}
vlib work
vmap work work

# ── Compile ────────────────────────────────────────────────────────────────────
vlog -sv -work work [file join $FPGA rtl bus tl_pkg.sv]

vlog -sv -work work [file join $FPGA ip pll.sv]
vlog -sv -work work [file join $FPGA ip dmem_bank.sv]
vlog -sv -work work [file join $FPGA ip imem_b0.sv]
vlog -sv -work work [file join $FPGA ip imem_b1.sv]
vlog -sv -work work [file join $FPGA ip imem_b2.sv]
vlog -sv -work work [file join $FPGA ip imem_b3.sv]

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

vlog -sv -work work [file join $FPGA rtl uart uart.sv]

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

vlog -sv -work work [file join $FPGA rtl mem dmem_qip_wrapper.sv]
vlog -sv -work work [file join $FPGA rtl hdmi vga_timing.sv]
vlog -sv -work work [file join $FPGA rtl vga vga_ctrl.sv]
vlog -sv -work work [file join $FPGA rtl top riscv_vpu_top_fpga.sv]
vlog -sv -work work [file join $BENCH tb_lena_mini.sv]

puts "INFO: Compilation done. Launching simulation..."

# ── Simulate ──────────────────────────────────────────────────────────────────
vsim -voptargs=+acc work.tb_lena_mini
run -all
