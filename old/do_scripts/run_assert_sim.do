## run_assert_sim.do — Assertion testbench for vproc_system_wrapper
## Run from project root: vsim -do run_assert_sim.do

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
    bench/tb_assert_vpu.sv

vsim -voptargs=+acc work.tb_assert_vpu

add wave -divider "=== CLOCK/RESET ==="
add wave -radix binary    /tb_assert_vpu/clk
add wave -radix binary    /tb_assert_vpu/rst_n

add wave -divider "=== FSM STATE ==="
add wave -radix unsigned  /tb_assert_vpu/fsm_state
add wave -radix binary    /tb_assert_vpu/busy
add wave -radix binary    /tb_assert_vpu/vpu_ready
add wave -radix binary    /tb_assert_vpu/vpu_cfg_done

add wave -divider "=== INSTRUCTION ISSUE ==="
add wave -radix binary    /tb_assert_vpu/instr_valid
add wave -radix hex       /tb_assert_vpu/instruction
add wave -radix binary    /tb_assert_vpu/fifo_full

add wave -divider "=== FSM INTERNAL ==="
add wave -radix binary    /tb_assert_vpu/dut/fsm_vrf_wren
add wave -radix binary    /tb_assert_vpu/dut/fsm_latch_ctrl_en
add wave -radix binary    /tb_assert_vpu/dut/fsm_s_offset_en
add wave -radix binary    /tb_assert_vpu/dut/fsm_d_offset_en
add wave -radix binary    /tb_assert_vpu/dut/counter_done
add wave -radix binary    /tb_assert_vpu/dut/fifo_data_valid
add wave -radix binary    /tb_assert_vpu/dut/raw_stall

add wave -divider "=== HAZARD SIGNALS ==="
add wave -radix binary    /tb_assert_vpu/dut/vlsu_vrf_we
add wave -radix binary    /tb_assert_vpu/dut/reduction_wb_valid
add wave -radix hex       /tb_assert_vpu/dut/reduction_result

add wave -divider "=== VRF WRITEBACK ==="
add wave -radix unsigned  /tb_assert_vpu/dut/vrf_waddr_eff
add wave -radix hex       /tb_assert_vpu/dut/vrf_we0_eff
add wave -radix hex       /tb_assert_vpu/wb_result_lane0
add wave -radix hex       /tb_assert_vpu/wb_result_lane1
add wave -radix hex       /tb_assert_vpu/wb_result_lane2
add wave -radix hex       /tb_assert_vpu/wb_result_lane3

add wave -divider "=== CSR ==="
add wave -radix unsigned  /tb_assert_vpu/csr_vl_o
add wave -radix hex       /tb_assert_vpu/csr_vtype_o

run -all
