# run_wave_fpga_vpu_batch.do — batch mode (transcript only, no GUI wave)
# Usage: vsim -c -do fpga/sim/run_wave_fpga_vpu_batch.do

set RTL   C:/CapstoneProject2/riscv_vpu/fpga/rtl
set BENCH C:/CapstoneProject2/riscv_vpu/fpga/bench

vlib work
vmap work work

foreach f {
    vproc_adder.sv      vproc_mul.sv       vproc_logic.sv
    vproc_shifter.sv    vproc_compare.sv   vproc_compare_combine.sv
    vproc_minmax.sv     vproc_reduction.sv vproc_merge_unit.sv
    vproc_processor_lane.sv
    vproc_vregfile.sv   vproc_mux_cells.sv
    vproc_mask_enable.sv  vproc_mask_write_buffer.sv
    vproc_vcsr.sv       vproc_cfg_encoder.sv   vproc_cycle_counter.sv
    vproc_vrf_addr_gen.sv vproc_scalar_expand.sv
    vproc_fsm.sv        vproc_fifo.sv      vproc_vdecoder.sv
    vproc_vec_lsu.sv    vproc_system_wrapper.sv
} {
    vlog -sv $RTL/vpu/$f
}

vlog -sv $BENCH/tb_vpu_wave.sv

vsim -t 1ps -voptargs=+acc work.tb_vpu_wave

run -all
quit -f
