# =============================================================================
# run_wave_fpga_vpu.do — FPGA VPU Standalone Waveform Demo  (ModelSim 10.5b)
#
# Chạy từ project root:
#   vsim -do fpga/sim/run_wave_fpga_vpu.do
#
# Kết quả mong đợi:
#   v8={10,20,30,40}  v9={1,2,3,4}  v10={11,22,33,44}
#   v11={10,40,90,160}  v12[0]=111
# =============================================================================

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

# ── Clock / Reset ─────────────────────────────────────────────────────────────
add wave -divider "Clock / Reset"
add wave -color white   sim:/tb_vpu_wave/clk
add wave -color yellow  sim:/tb_vpu_wave/rst_n

# ── Instruction Dispatch ──────────────────────────────────────────────────────
add wave -divider "Instruction Dispatch"
add wave -color cyan                     sim:/tb_vpu_wave/instr_valid
add wave -color cyan   -radix hex        sim:/tb_vpu_wave/instruction
add wave -color cyan                     sim:/tb_vpu_wave/instr_name
add wave -color cyan   -radix unsigned   sim:/tb_vpu_wave/rs1_scalar_data

# ── VPU Status ────────────────────────────────────────────────────────────────
add wave -divider "VPU Status"
add wave -color green                    sim:/tb_vpu_wave/vpu_ready
add wave -color red                      sim:/tb_vpu_wave/vpu_busy
add wave -color magenta                  sim:/tb_vpu_wave/vpu_cfg_done
add wave -color white  -radix unsigned   sim:/tb_vpu_wave/csr_vl

# ── FSM State (enum auto-decoded by ModelSim) ─────────────────────────────────
add wave -divider "VPU FSM State"
add wave -color magenta                  sim:/tb_vpu_wave/dut/fsm_inst/state_r
add wave -color magenta -radix unsigned  sim:/tb_vpu_wave/fsm_state
add wave -color magenta                  sim:/tb_vpu_wave/fsm_state_name

# ── VLSU State (enum auto-decoded) ────────────────────────────────────────────
add wave -divider "VLSU State"
add wave -color yellow                   sim:/tb_vpu_wave/dut/vlsu_inst/state_r
add wave -color yellow                   sim:/tb_vpu_wave/vlsu_busy_o

# ── VLSU Memory Bus ───────────────────────────────────────────────────────────
add wave -divider "VLSU Memory Bus"
add wave -color cyan                     sim:/tb_vpu_wave/vlsu_req
add wave -color cyan                     sim:/tb_vpu_wave/vlsu_we
add wave -color cyan   -radix hex        sim:/tb_vpu_wave/vlsu_addr
add wave -color cyan   -radix hex        sim:/tb_vpu_wave/vlsu_rdata
add wave -color green                    sim:/tb_vpu_wave/vlsu_ready

# ── VRF Write-back (ALU) ──────────────────────────────────────────────────────
add wave -divider "VRF Write-back (ALU)"
add wave -color green  -radix unsigned   sim:/tb_vpu_wave/wb_lane0
add wave -color green  -radix unsigned   sim:/tb_vpu_wave/wb_lane1
add wave -color green  -radix unsigned   sim:/tb_vpu_wave/wb_lane2
add wave -color green  -radix unsigned   sim:/tb_vpu_wave/wb_lane3

# ── Reduction Unit ────────────────────────────────────────────────────────────
add wave -divider "Reduction Unit"
add wave -color orange                   sim:/tb_vpu_wave/dut/red_busy
add wave -color orange                   sim:/tb_vpu_wave/dut/reduction_wb_valid
add wave -color orange -radix unsigned   sim:/tb_vpu_wave/dut/reduction_result

# ── VLSU VRF Write-back (load data) ──────────────────────────────────────────
add wave -divider "VLSU VRF Write-back"
add wave -color yellow                   sim:/tb_vpu_wave/dut/vlsu_vrf_we
add wave -color yellow -radix unsigned   sim:/tb_vpu_wave/dut/vlsu_vrf_waddr
add wave -color yellow -radix unsigned   sim:/tb_vpu_wave/dut/vlsu_vrf_wdata_l0
add wave -color yellow -radix unsigned   sim:/tb_vpu_wave/dut/vlsu_vrf_wdata_l1
add wave -color yellow -radix unsigned   sim:/tb_vpu_wave/dut/vlsu_vrf_wdata_l2
add wave -color yellow -radix unsigned   sim:/tb_vpu_wave/dut/vlsu_vrf_wdata_l3

wave zoom full
run -all
wave zoom full
