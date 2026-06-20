## run_wave_fsm_sim.do — FSM state transition waveform testbench
## Shows: CONFIG, EXEC, WIDENL/H, REDUCTION state sequences
## Run from project root: vsim -do run_wave_fsm_sim.do

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
    rtl/vproc_fsm.sv \
    rtl/vproc_fifo.sv \
    rtl/vproc_vdecoder.sv \
    rtl/vproc_vec_lsu.sv \
    rtl/vproc_system_wrapper.sv \
    bench/tb_wave_fsm.sv

vsim -voptargs=+acc work.tb_wave_fsm

add wave -divider "━━━ CLOCK / RESET ━━━"
add wave -radix binary    /tb_wave_fsm/clk
add wave -radix binary    /tb_wave_fsm/rst_n

add wave -divider "━━━ INSTRUCTION ISSUE ━━━"
add wave -radix binary    /tb_wave_fsm/instr_valid
add wave -radix hex       /tb_wave_fsm/instruction
add wave -radix binary    /tb_wave_fsm/dut/fifo_data_valid
add wave -radix binary    /tb_wave_fsm/dut/raw_stall

add wave -divider "━━━ FSM STATE (key signal for report) ━━━"
add wave -radix unsigned  /tb_wave_fsm/fsm_state
add wave -radix binary    /tb_wave_fsm/busy

add wave -divider "━━━ FSM OUTPUTS ━━━"
add wave -radix binary    /tb_wave_fsm/dut/fsm_latch_ctrl_en
add wave -radix binary    /tb_wave_fsm/dut/fsm_vrf_wren
add wave -radix binary    /tb_wave_fsm/dut/fsm_s_offset_en
add wave -radix binary    /tb_wave_fsm/dut/fsm_d_offset_en
add wave -radix binary    /tb_wave_fsm/dut/fsm_offset_reset
add wave -radix binary    /tb_wave_fsm/dut/fsm_pop_ready
add wave -radix binary    /tb_wave_fsm/dut/fsm_reduction_start
add wave -radix binary    /tb_wave_fsm/dut/fsm_reduction_en

add wave -divider "━━━ CYCLE COUNTER ━━━"
add wave -radix binary    /tb_wave_fsm/dut/counter_done
add wave -radix unsigned  /tb_wave_fsm/cycles
add wave -radix unsigned  /tb_wave_fsm/dut/cycles_left_dbg

add wave -divider "━━━ REDUCTION STATUS ━━━"
add wave -radix binary    /tb_wave_fsm/dut/reduction_wb_valid
add wave -radix binary    /tb_wave_fsm/dut/red_busy

add wave -divider "━━━ VRF WRITEBACK ━━━"
add wave -radix unsigned  /tb_wave_fsm/dut/vrf_waddr_eff
add wave -radix hex       /tb_wave_fsm/dut/vrf_we0_eff
add wave -radix hex       /tb_wave_fsm/wb_result_lane0

add wave -divider "━━━ CSR ━━━"
add wave -radix unsigned  /tb_wave_fsm/csr_vl_o
add wave -radix hex       /tb_wave_fsm/csr_vtype_o
add wave -radix binary    /tb_wave_fsm/vpu_cfg_done
add wave -radix binary    /tb_wave_fsm/vpu_ready

run -all
