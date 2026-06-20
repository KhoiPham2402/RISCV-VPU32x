transcript on
if ![file isdirectory riscv_vpu_iputf_libs] {
	file mkdir riscv_vpu_iputf_libs
}

if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

###### Libraries for IPUTF cores 
###### End libraries for IPUTF cores 
###### MIF file copy and HDL compilation commands for IPUTF cores 


vlog "C:/CapstoneProject2/FPGA/riscv_vpu/pll_sim/pll.vo"

vlog -vlog01compat -work work +incdir+C:/CapstoneProject2/FPGA/riscv_vpu {C:/CapstoneProject2/FPGA/riscv_vpu/dmem_bank.v}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/hdmi {C:/CapstoneProject2/riscv_vpu/fpga/rtl/hdmi/vga_timing.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/hdmi {C:/CapstoneProject2/riscv_vpu/fpga/rtl/hdmi/i2c_master.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/hdmi {C:/CapstoneProject2/riscv_vpu/fpga/rtl/hdmi/hdmi_ctrl.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/hdmi {C:/CapstoneProject2/riscv_vpu/fpga/rtl/hdmi/adv7513_cfg.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/bus {C:/CapstoneProject2/riscv_vpu/fpga/rtl/bus/tl_pkg.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/mem {C:/CapstoneProject2/riscv_vpu/fpga/rtl/mem/dmem_qip_wrapper.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_vrf_addr_gen.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_vregfile.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_vec_lsu.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_vdecoder.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_vcsr.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_system_wrapper.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_shifter.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_scalar_expand.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_reduction.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_processor_lane.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_mux_cells.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_mul.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_minmax.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_merge_unit.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_mask_write_buffer.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_mask_enable.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_logic.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_fsm.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_fifo.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_cycle_counter.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_compare.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_cfg_encoder.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu {C:/CapstoneProject2/riscv_vpu/fpga/rtl/vpu/vproc_adder.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/word_xor.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/word_or.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/word_and.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/register_file.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/register.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/Regfile.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/pipelined_vpu.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/mux32to1.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/mux8to1.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/mux4to1.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/mux2X1.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/mux2to1.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/mag_comparator8.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/mag_comparator.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/immgen.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/imem_sync.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/full_adder.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/eight_bit_adder.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/decoder5to32.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/d_ff.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/control_unit.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/brc_comparator.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/brc.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/barrel_shifter_32bit_left.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/barrel_shifter_32bit.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/alu.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline {C:/CapstoneProject2/riscv_vpu/fpga/rtl/pipeline/adder.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/top {C:/CapstoneProject2/riscv_vpu/fpga/rtl/top/riscv_vpu_top_fpga.sv}
vlog -sv -work work +incdir+C:/CapstoneProject2/riscv_vpu/fpga/rtl/uart {C:/CapstoneProject2/riscv_vpu/fpga/rtl/uart/uart.sv}

vlog -sv -work work +incdir+C:/CapstoneProject2/FPGA/riscv_vpu/../../riscv_vpu/fpga/bench {C:/CapstoneProject2/FPGA/riscv_vpu/../../riscv_vpu/fpga/bench/tb_lena_fpga.sv}

vsim -t 1ps -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L cyclonev_ver -L cyclonev_hssi_ver -L cyclonev_pcie_hip_ver -L rtl_work -L work -voptargs="+acc"  tb_lena_fpga

add wave *
view structure
view signals
run -all
