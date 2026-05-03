transcript on

# Ensure work library exists
if {![file exists work]} {
    vlib work
}

# Compile RTL + integration testbench
vlog -sv rtl/vproc_adder.sv rtl/vproc_mul.sv rtl/vproc_logic.sv rtl/vproc_shifter.sv rtl/vproc_compare.sv rtl/vproc_processor_lane.sv rtl/vproc_vregfile.sv rtl/vproc_mux_cells.sv rtl/vproc_mask_enable.sv rtl/vproc_mask_write_buffer.sv rtl/vproc_vcsr.sv rtl/vproc_cfg_encoder.sv rtl/vproc_cycle_counter.sv rtl/vproc_vrf_addr_gen.sv rtl/vproc_scalar_expand.sv rtl/vproc_fsm.sv rtl/vproc_fifo.sv rtl/vproc_vdecoder.sv rtl/vproc_vec_lsu.sv rtl/vproc_system_wrapper.sv bench/tb_vproc_system_wrapper.sv

# IMPORTANT: vsim loads module name, not .sv file path
vsim -voptargs=+acc work.tb_vproc_system_wrapper

run -all

