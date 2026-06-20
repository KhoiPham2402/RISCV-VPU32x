# run_uart_loopback.do — Build uart_loopback firmware and simulate UART RX/TX
#
# Usage (from project root in ModelSim):
#   vsim -c -do run_uart_loopback.do
#
# What it verifies:
#   Sends bytes 0x64, 0x32, 0x00, 0x7F, 0x96, 0xFF, 0xAA, 0x55 to DUT.
#   Expects response = (sent + 1) mod 256 from uart_loopback firmware.
#   Critical test: 0x64/0x32 (bit7=0) — these failed with the old half-bit
#   sampling bug in uart.sv. Fixed by using 1.5-bit delay instead.

set ROOT [file normalize [pwd]]
set FPGA [file join $ROOT fpga]
set SW   [file join $ROOT sw]
set BENCH [file join $ROOT bench]

# ── Build firmware ─────────────────────────────────────────────────────────────
puts "INFO: Building uart_loopback firmware..."
set rc [catch {exec cmd /c "cd \"$SW\" && make uart_loopback.hex"} msg]
if {$rc != 0} {
    puts "WARN: make failed or toolchain not in PATH. Using existing uart_loopback.hex if present."
    puts "      Error: $msg"
    puts "      To build manually: cd sw && make uart_loopback.hex"
}

# ── Copy hex to fpga/ (imem_sync default HEX_FILE path) ───────────────────────
set HEX_SRC [file join $ROOT uart_loopback.hex]
set HEX_DST [file join $FPGA uart_lena.hex]
if {[file exists $HEX_SRC]} {
    file copy -force $HEX_SRC $HEX_DST
    puts "INFO: Copied uart_loopback.hex → fpga/uart_lena.hex"
} elseif {![file exists $HEX_DST]} {
    puts "ERROR: Neither uart_loopback.hex nor fpga/uart_lena.hex found."
    puts "       Run: cd sw && make uart_loopback.hex"
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
vlog -sv -work work [file join $BENCH tb_uart_loopback.sv]

puts "INFO: Compilation complete."

# ── Simulate ──────────────────────────────────────────────────────────────────
vsim -voptargs=+acc work.tb_uart_loopback
run -all
