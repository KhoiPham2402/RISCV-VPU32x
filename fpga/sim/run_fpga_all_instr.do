# =============================================================================
# run_fpga_all_instr.do — VPU instruction regression (bench/tb_vproc_all_instr.sv)
# compiled against fpga/rtl/vpu instead of rtl/ (see vproc_all_instr.do at repo
# root, which targets the older rtl/ tree). Use this one for fpga/ work.
#
# Chạy từ project root: vsim -c -do fpga/sim/run_fpga_all_instr.do
# =============================================================================
transcript on
vlib work
vmap work work

vlog -sv \
    fpga/rtl/vpu/vproc_adder.sv \
    fpga/rtl/vpu/vproc_mul.sv \
    fpga/rtl/vpu/vproc_logic.sv \
    fpga/rtl/vpu/vproc_shifter.sv \
    fpga/rtl/vpu/vproc_compare.sv \
    fpga/rtl/vpu/vproc_compare_combine.sv \
    fpga/rtl/vpu/vproc_minmax.sv \
    fpga/rtl/vpu/vproc_reduction.sv \
    fpga/rtl/vpu/vproc_merge_unit.sv \
    fpga/rtl/vpu/vproc_processor_lane.sv \
    fpga/rtl/vpu/vproc_vregfile.sv \
    fpga/rtl/vpu/vproc_mux_cells.sv \
    fpga/rtl/vpu/vproc_mask_enable.sv \
    fpga/rtl/vpu/vproc_mask_write_buffer.sv \
    fpga/rtl/vpu/vproc_vcsr.sv \
    fpga/rtl/vpu/vproc_cfg_encoder.sv \
    fpga/rtl/vpu/vproc_cycle_counter.sv \
    fpga/rtl/vpu/vproc_vrf_addr_gen.sv \
    fpga/rtl/vpu/vproc_scalar_expand.sv \
    fpga/rtl/vpu/vproc_fsm.sv \
    fpga/rtl/vpu/vproc_fifo.sv \
    fpga/rtl/vpu/vproc_vdecoder.sv \
    fpga/rtl/vpu/vproc_vec_lsu.sv \
    fpga/rtl/vpu/vproc_system_wrapper.sv \
    bench/tb_vproc_all_instr.sv

vsim -voptargs=+acc -c work.tb_vproc_all_instr
run -all
quit -f
