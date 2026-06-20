# run_vga_lena_y_sim.do — VGA display smoke test: Lena Y pre-loaded in DMEM
#
# Run from project root:
#   vsim -do run_vga_lena_y_sim.do
#
# Tests: DMEM[12288..16383] pre-loaded with Lena grayscale Y →
#        VGA controller reads and outputs correct pixel values.
# Firmware = trivial 1-instruction spin (vga_lena_y.S).

set ROOT  [file normalize [pwd]]
set FPGA  [file join $ROOT fpga]
set BENCH [file join $ROOT bench]

# Use vga_lena_y.hex as IMEM (1-instruction spin firmware)
set HEX_SRC [file join $FPGA vga_lena_y.hex]
set HEX_DST [file join $FPGA uart_lena.hex]
if {![file exists $HEX_SRC]} {
    puts "ERROR: fpga/vga_lena_y.hex not found."
    puts "  Build: cd fpga/sw && make vga_lena_y RISCV_PREFIX=... PYTHON=python"
    quit -f
}
file copy -force $HEX_SRC $HEX_DST
puts "INFO: Using vga_lena_y.hex as IMEM"

catch {vdel -lib work -all}
vlib work
vmap work work

# Compile (same order as run_fpga_lena_sim.do)
vlog -sv -work work [file join $FPGA rtl bus tl_pkg.sv]

vlog -sv -work work [file join $FPGA ip pll.sv]
vlog -sv -work work [file join $FPGA ip dmem_bank.sv]
vlog -sv -work work [file join $FPGA ip dmem_bank_b0.sv]
vlog -sv -work work [file join $FPGA ip dmem_bank_b1.sv]
vlog -sv -work work [file join $FPGA ip dmem_bank_b2.sv]
vlog -sv -work work [file join $FPGA ip dmem_bank_b3.sv]
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
} { vlog -sv -work work [file join $FPGA rtl pipeline $f] }

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
} { vlog -sv -work work [file join $FPGA rtl vpu $f] }

vlog -sv -work work [file join $FPGA rtl mem dmem_qip_wrapper.sv]
vlog -sv -work work [file join $FPGA rtl hdmi vga_timing.sv]
vlog -sv -work work [file join $FPGA rtl vga vga_ctrl.sv]
vlog -sv -work work [file join $FPGA rtl top riscv_vpu_top_fpga.sv]
vlog -sv -work work [file join $BENCH tb_vga_lena_y_sim.sv]

puts "INFO: Compilation done — launching sim."
vsim -voptargs=+acc work.tb_vga_lena_y_sim
run -all
