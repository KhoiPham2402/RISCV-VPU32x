# run_gray_sew8.do — BT.601 grayscale SEW=8 computation test
#
# Tests vmulhu.vx + vadd.vv at SEW=8 with Lena-like pixel values.
# Distinguishes: VPU computation bug vs VGA data path bug.
#
# Usage: vsim -do run_gray_sew8.do

quietly set SRC_ROOT "C:/CapstoneProject2/riscv_vpu"

vlib work
vmap work work

# VPU RTL (reuse compile list from vproc_all_instr.do)
vlog -sv "$SRC_ROOT/rtl/vproc_fifo.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_vdecoder.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_vcsr.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_cfg_encoder.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_vregfile.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_vec_lsu.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_vrf_addr_gen.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_scalar_expand.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_mask_enable.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_merge_unit.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_mux_cells.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_cycle_counter.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_adder.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_mul.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_shifter.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_logic.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_compare.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_minmax.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_reduction.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_processor_lane.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_fsm.sv"
vlog -sv "$SRC_ROOT/rtl/vproc_system_wrapper.sv"

vlog -sv "$SRC_ROOT/bench/tb_gray_sew8.sv"

vsim -novopt -t 1ps work.tb_gray_sew8
run -all
quit -f
