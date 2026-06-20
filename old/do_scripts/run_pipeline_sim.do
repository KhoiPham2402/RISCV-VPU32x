## run_pipeline_sim.do — Pipelined VPU regression simulation
## Compiles vproc_fsm_p + vproc_system_wrapper_p and runs tb_pipeline_regression.
## Run from project root: vsim -do run_pipeline_sim.do
##
## Expected output: PASS=N  FAIL=0  (same test suite as vproc_all_instr.do)

transcript on

if {![file exists work]} { vlib work }

vlog -sv \
    rtl/vproc_adder.sv \
    rtl/vproc_mul.sv \
    rtl/vproc_logic.sv \
    rtl/vproc_shifter.sv \
    rtl/vproc_compare.sv \
    rtl/vproc_compare_combine.sv \
    rtl/vproc_minmax.sv \
    rtl/vproc_reduction.sv \
    rtl/vproc_merge_unit.sv \
    rtl/vproc_processor_lane.sv \
    rtl/vproc_vregfile.sv \
    rtl/vproc_mux_cells.sv \
    rtl/vproc_mask_enable.sv \
    rtl/vproc_mask_write_buffer.sv \
    rtl/vproc_vcsr.sv \
    rtl/vproc_cfg_encoder.sv \
    rtl/vproc_cycle_counter.sv \
    rtl/vproc_vrf_addr_gen.sv \
    rtl/vproc_scalar_expand.sv \
    rtl/vproc_fifo.sv \
    rtl/vproc_vdecoder.sv \
    rtl/vproc_vec_lsu.sv \
    rtl_pipeline/vproc_fsm_p.sv \
    rtl_pipeline/vproc_system_wrapper_p.sv \
    bench/tb_pipeline_regression.sv

vsim -voptargs=+acc work.tb_pipeline_regression

run -all
quit -f
