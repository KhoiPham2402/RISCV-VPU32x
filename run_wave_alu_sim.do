## run_wave_alu_sim.do — ALU waveform testbench
## Signals: FSM control, decode fields, lane data, VRF writeback
## Run from project root: vsim -do run_wave_alu_sim.do

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
    bench/tb_wave_alu.sv

vsim -voptargs=+acc work.tb_wave_alu

add wave -divider "━━━ CLOCK / RESET ━━━"
add wave -radix binary    /tb_wave_alu/clk
add wave -radix binary    /tb_wave_alu/rst_n

add wave -divider "━━━ FSM CONTROL ━━━"
add wave -radix unsigned  /tb_wave_alu/fsm_state
add wave -radix binary    /tb_wave_alu/busy
add wave -radix binary    /tb_wave_alu/dut/fsm_vrf_wren
add wave -radix binary    /tb_wave_alu/dut/fsm_s_offset_en
add wave -radix binary    /tb_wave_alu/dut/fsm_d_offset_en
add wave -radix binary    /tb_wave_alu/dut/counter_done

add wave -divider "━━━ INSTRUCTION DECODE ━━━"
add wave -radix hex       /tb_wave_alu/dut/funct6_r
add wave -radix unsigned  /tb_wave_alu/dut/cfg_sew
add wave -radix unsigned  /tb_wave_alu/dut/vs1_addr_eff
add wave -radix unsigned  /tb_wave_alu/dut/vs2_addr_eff
add wave -radix unsigned  /tb_wave_alu/dut/vd_addr_eff
add wave -radix binary    /tb_wave_alu/dut/use_rs1_r
add wave -radix binary    /tb_wave_alu/dut/use_imm_r

add wave -divider "━━━ LANE 0 DATA PATH ━━━"
add wave -radix hex       /tb_wave_alu/dut/rs1_data_lane0
add wave -radix hex       /tb_wave_alu/dut/rs2_data_lane0
add wave -radix hex       /tb_wave_alu/dut/wb_lane0

add wave -divider "━━━ VRF WRITEBACK ━━━"
add wave -radix unsigned  /tb_wave_alu/dut/vrf_waddr_eff
add wave -radix hex       /tb_wave_alu/dut/vrf_we0_eff
add wave -radix hex       /tb_wave_alu/wb_result_lane0
add wave -radix hex       /tb_wave_alu/wb_result_lane1
add wave -radix hex       /tb_wave_alu/wb_result_lane2
add wave -radix hex       /tb_wave_alu/wb_result_lane3

add wave -divider "━━━ CSR ━━━"
add wave -radix unsigned  /tb_wave_alu/csr_vl_o
add wave -radix hex       /tb_wave_alu/csr_vtype_o

run -all
