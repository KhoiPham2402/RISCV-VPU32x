## run_wave_reduction_sim.do — Reduction unit waveform testbench
## Shows: start, valid, busy, elem_cnt, acc_r, wb_valid, result_out
## Run from project root: vsim -do run_wave_reduction_sim.do

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
    bench/tb_wave_reduction.sv

vsim -voptargs=+acc work.tb_wave_reduction

add wave -divider "━━━ CLOCK ━━━"
add wave -radix binary    /tb_wave_reduction/clk
add wave -radix binary    /tb_wave_reduction/rst_n

add wave -divider "━━━ FSM STATE ━━━"
add wave -radix unsigned  /tb_wave_reduction/fsm_state
add wave -radix binary    /tb_wave_reduction/busy

add wave -divider "━━━ REDUCTION CONTROL (from FSM) ━━━"
add wave -radix binary    /tb_wave_reduction/dut/fsm_reduction_start
add wave -radix binary    /tb_wave_reduction/dut/fsm_reduction_en
add wave -radix binary    /tb_wave_reduction/dut/counter_done

add wave -divider "━━━ REDUCTION UNIT INTERNALS ━━━"
add wave -radix binary    /tb_wave_reduction/dut/reduction_inst/start
add wave -radix binary    /tb_wave_reduction/dut/reduction_inst/valid
add wave -radix binary    /tb_wave_reduction/dut/reduction_inst/busy
add wave -radix binary    /tb_wave_reduction/dut/reduction_inst/done
add wave -radix unsigned  /tb_wave_reduction/dut/reduction_inst/elem_cnt
add wave -radix hex       /tb_wave_reduction/dut/reduction_inst/acc_r
add wave -radix unsigned  /tb_wave_reduction/dut/reduction_inst/sew_r
add wave -radix unsigned  /tb_wave_reduction/dut/reduction_inst/op_r
add wave -radix binary    /tb_wave_reduction/dut/reduction_inst/active

add wave -divider "━━━ REDUCTION RESULT ━━━"
add wave -radix binary    /tb_wave_reduction/dut/reduction_wb_valid
add wave -radix hex       /tb_wave_reduction/dut/reduction_result

add wave -divider "━━━ VRF WRITEBACK ━━━"
add wave -radix unsigned  /tb_wave_reduction/dut/vrf_waddr_eff
add wave -radix hex       /tb_wave_reduction/dut/vrf_we0_eff
add wave -radix hex       /tb_wave_reduction/wb_result_lane0

add wave -divider "━━━ CSR ━━━"
add wave -radix unsigned  /tb_wave_reduction/csr_vl_o

run -all
