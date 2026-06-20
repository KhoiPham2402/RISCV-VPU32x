# =============================================================================
# run_wave_lena_vpu.do — Lena-like grayscale pipeline waveform (no UART)
#
# Chạy từ project root:
#   vsim -do fpga/sim/run_wave_lena_vpu.do
#
# Hiển thị toàn bộ luồng VPU xử lý ảnh:
#   load R → compute → load G → compute → add → load B → compute → add → store
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

vlog -sv $BENCH/tb_lena_vpu_wave.sv

vsim -t 1ps -voptargs=+acc work.tb_lena_vpu_wave

# ── Clock / Reset ─────────────────────────────────────────────────────────────
add wave -divider "Clock / Reset"
add wave -color white   sim:/tb_lena_vpu_wave/clk
add wave -color yellow  sim:/tb_lena_vpu_wave/rst_n

# ── Instruction Dispatch ──────────────────────────────────────────────────────
add wave -divider "Instruction Dispatch"
add wave -color cyan                    sim:/tb_lena_vpu_wave/instr_valid
add wave -color cyan   -radix hex       sim:/tb_lena_vpu_wave/instruction
add wave -color cyan                    sim:/tb_lena_vpu_wave/instr_name
add wave -color cyan   -radix unsigned  sim:/tb_lena_vpu_wave/rs1_scalar_data

# ── VPU Status ────────────────────────────────────────────────────────────────
add wave -divider "VPU Status"
add wave -color green                   sim:/tb_lena_vpu_wave/vpu_ready
add wave -color red                     sim:/tb_lena_vpu_wave/vpu_busy
add wave -color white  -radix unsigned  sim:/tb_lena_vpu_wave/csr_vl

# ── FSM State ─────────────────────────────────────────────────────────────────
add wave -divider "FSM State"
add wave -color magenta                 sim:/tb_lena_vpu_wave/dut/fsm_inst/state_r
add wave -color magenta                 sim:/tb_lena_vpu_wave/fsm_state_name

# ── VLSU State ────────────────────────────────────────────────────────────────
add wave -divider "VLSU State"
add wave -color yellow                  sim:/tb_lena_vpu_wave/dut/vlsu_inst/state_r
add wave -color yellow                  sim:/tb_lena_vpu_wave/vlsu_busy_o

# ── VLSU Memory Bus ───────────────────────────────────────────────────────────
add wave -divider "VLSU Memory Bus"
add wave -color cyan                    sim:/tb_lena_vpu_wave/vlsu_req
add wave -color cyan                    sim:/tb_lena_vpu_wave/vlsu_we
add wave -color cyan   -radix hex       sim:/tb_lena_vpu_wave/vlsu_addr
add wave -color cyan   -radix hex       sim:/tb_lena_vpu_wave/vlsu_rdata
add wave -color cyan   -radix hex       sim:/tb_lena_vpu_wave/vlsu_wdata
add wave -color green                   sim:/tb_lena_vpu_wave/vlsu_ready

# ── VLSU VRF Write-back (load data) ──────────────────────────────────────────
add wave -divider "VLSU VRF Write-back"
add wave -color yellow                  sim:/tb_lena_vpu_wave/dut/vlsu_vrf_we
add wave -color yellow -radix unsigned  sim:/tb_lena_vpu_wave/dut/vlsu_vrf_waddr
add wave -color yellow -radix unsigned  sim:/tb_lena_vpu_wave/dut/vlsu_vrf_wdata_l0
add wave -color yellow -radix unsigned  sim:/tb_lena_vpu_wave/dut/vlsu_vrf_wdata_l1
add wave -color yellow -radix unsigned  sim:/tb_lena_vpu_wave/dut/vlsu_vrf_wdata_l2
add wave -color yellow -radix unsigned  sim:/tb_lena_vpu_wave/dut/vlsu_vrf_wdata_l3

# ── FSM VRF Write-back (ALU result) ──────────────────────────────────────────
add wave -divider "ALU VRF Write-back"
add wave -color green                   sim:/tb_lena_vpu_wave/dut/fsm_vrf_wren
add wave -color green  -radix unsigned  sim:/tb_lena_vpu_wave/dut/vd_addr_eff
add wave -color green  -radix unsigned  sim:/tb_lena_vpu_wave/dut/vrf_wdata0_eff
add wave -color green  -radix unsigned  sim:/tb_lena_vpu_wave/dut/vrf_wdata1_eff
add wave -color green  -radix unsigned  sim:/tb_lena_vpu_wave/dut/vrf_wdata2_eff
add wave -color green  -radix unsigned  sim:/tb_lena_vpu_wave/dut/vrf_wdata3_eff

wave zoom full
run -all
wave zoom full
