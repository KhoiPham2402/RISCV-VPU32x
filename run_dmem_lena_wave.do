transcript on

set ROOT  [file normalize [pwd]]
set FPGA  [file join $ROOT fpga]
set BENCH [file join $ROOT bench]

# Copy dmem_lena.hex → uart_lena.hex (behavioral IMEM reads from this path)
set HEX_SRC [file join $FPGA dmem_lena.hex]
set HEX_DST [file join $FPGA uart_lena.hex]
if {![file exists $HEX_SRC]} {
    puts "ERROR: fpga/dmem_lena.hex not found."
    quit -f
}
file copy -force $HEX_SRC $HEX_DST
puts "INFO: Copied dmem_lena.hex → uart_lena.hex"

# ── Library ───────────────────────────────────────────────────────────────────
catch {vdel -lib work -all}
vlib work
vmap work work

# ── Compile ───────────────────────────────────────────────────────────────────
vlog -sv -work work [file join $FPGA rtl bus tl_pkg.sv]

foreach f {pll.sv dmem_bank.sv dmem_bank_b0.sv dmem_bank_b1.sv dmem_bank_b2.sv dmem_bank_b3.sv
           imem_b0.sv imem_b1.sv imem_b2.sv imem_b3.sv} {
    vlog -sv -work work [file join $FPGA ip $f]
}

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

vlog -sv -work work [file join $FPGA rtl bus dmem_arbiter.sv]
vlog -sv -work work [file join $FPGA rtl mem dmem_qip_wrapper.sv]
vlog -sv -work work [file join $FPGA rtl hdmi vga_timing.sv]
vlog -sv -work work [file join $FPGA rtl vga vga_ctrl.sv]
vlog -sv -work work [file join $FPGA rtl top riscv_vpu_top_fpga.sv]
vlog -sv -work work [file join $BENCH tb_dmem_lena_sim.sv]

puts "INFO: Compilation done — launching simulation"

# ── Load simulation ───────────────────────────────────────────────────────────
vsim -voptargs=+acc work.tb_dmem_lena_sim

# ── Wave window setup ─────────────────────────────────────────────────────────
add wave -divider {Clock Reset}
add wave -color Gold         /tb_dmem_lena_sim/clk
add wave -color Gold         /tb_dmem_lena_sim/reset

add wave -divider {Scalar PC}
add wave -color Cyan  -radix hexadecimal /tb_dmem_lena_sim/dut/u_core/pc

add wave -divider {VPU Status}
add wave -color Lime         /tb_dmem_lena_sim/vpu_busy
add wave -color White -radix unsigned    /tb_dmem_lena_sim/dut/o_fsm_state

add wave -divider {VLSU Memory Bus Port B}
add wave -color Yellow       /tb_dmem_lena_sim/dut/vlsu_req
add wave -color Yellow       /tb_dmem_lena_sim/dut/vlsu_we
add wave -color Yellow -radix hexadecimal /tb_dmem_lena_sim/dut/vlsu_addr
add wave -color Orange -radix binary      /tb_dmem_lena_sim/dut/vlsu_be
add wave -color White  -radix hexadecimal /tb_dmem_lena_sim/dut/vlsu_wdata
add wave -color Cyan   -radix hexadecimal /tb_dmem_lena_sim/dut/vlsu_rdata
add wave -color Lime         /tb_dmem_lena_sim/dut/vlsu_ready

add wave -divider {VRF Write from VLSU}
add wave -color Magenta      /tb_dmem_lena_sim/dut/u_vpu/vlsu_vrf_we
add wave -color Magenta -radix unsigned   /tb_dmem_lena_sim/dut/u_vpu/vlsu_vrf_waddr

add wave -divider {VPU WB Results ALU lanes}
add wave -color Aquamarine -radix hexadecimal /tb_dmem_lena_sim/dut/u_vpu/wb_lane0_mux
add wave -color Aquamarine -radix hexadecimal /tb_dmem_lena_sim/dut/u_vpu/wb_lane1_mux
add wave -color Aquamarine -radix hexadecimal /tb_dmem_lena_sim/dut/u_vpu/wb_lane2_mux
add wave -color Aquamarine -radix hexadecimal /tb_dmem_lena_sim/dut/u_vpu/wb_lane3_mux

add wave -divider {VLSU word counter}
add wave -color White  -radix unsigned /tb_dmem_lena_sim/dut/u_vpu/vlsu_inst/word_ctr_r

configure wave -namecolwidth 320
configure wave -valuecolwidth 120
configure wave -timelineunits ns

# ── Run ───────────────────────────────────────────────────────────────────────
run -all
wave zoom full
