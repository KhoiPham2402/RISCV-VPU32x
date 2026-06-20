# =============================================================================
# run_wave_fpga_imem_lena.do — Full FPGA system waveform (IMEM fetch + VPU)
#
# DUT: pipelined_vpu (scalar core) + vproc_system_wrapper (VPU)
# IMEM: lena_imem.hex (firmware compiled from lena_gray.c)
# DMEM: lena_dmem_init.hex (RGB pixel planes, backdoor-loaded)
#
# Chạy từ project root:  vsim -do fpga/sim/run_wave_fpga_imem_lena.do
# =============================================================================

set RTL   C:/CapstoneProject2/riscv_vpu/fpga/rtl
set IP    C:/CapstoneProject2/riscv_vpu/fpga/ip
set BENCH C:/CapstoneProject2/riscv_vpu/fpga/bench

vlib work
vmap work work

# ── IMEM behavioral IPs (must compile before pipelined_vpu) ──────────────────
vlog -sv $IP/imem_b0.sv
vlog -sv $IP/imem_b1.sv
vlog -sv $IP/imem_b2.sv
vlog -sv $IP/imem_b3.sv

# ── Scalar core pipeline cells ────────────────────────────────────────────────
foreach f {
    full_adder.sv eight_bit_adder.sv adder.sv
    d_ff.sv register.sv decoder5to32.sv Regfile.sv register_file.sv
    mux2to1.sv mux2X1.sv mux4to1.sv mux8to1.sv mux32to1.sv
    immgen.sv mag_comparator.sv mag_comparator8.sv brc_comparator.sv brc.sv
    word_and.sv word_or.sv word_xor.sv
    barrel_shifter_32bit.sv barrel_shifter_32bit_left.sv
    alu.sv imem_sync.sv control_unit.sv pipelined_vpu.sv
} {
    vlog -sv $RTL/pipeline/$f
}

# ── VPU modules ───────────────────────────────────────────────────────────────
foreach f {
    vproc_adder.sv vproc_mul.sv vproc_logic.sv vproc_shifter.sv
    vproc_compare.sv vproc_compare_combine.sv vproc_minmax.sv
    vproc_reduction.sv vproc_merge_unit.sv vproc_processor_lane.sv
    vproc_vregfile.sv vproc_mux_cells.sv vproc_mask_enable.sv
    vproc_mask_write_buffer.sv vproc_vcsr.sv vproc_cfg_encoder.sv
    vproc_cycle_counter.sv vproc_vrf_addr_gen.sv vproc_scalar_expand.sv
    vproc_fsm.sv vproc_fifo.sv vproc_vdecoder.sv
    vproc_vec_lsu.sv vproc_system_wrapper.sv
} {
    vlog -sv $RTL/vpu/$f
}

# ── Testbench ─────────────────────────────────────────────────────────────────
vlog -sv $BENCH/tb_fpga_imem_lena.sv

vsim -t 1ps -voptargs=+acc work.tb_fpga_imem_lena

# =============================================================================
# Waveform setup
# =============================================================================

# ── Clock / Reset ─────────────────────────────────────────────────────────────
add wave -divider "Clock / Reset"
add wave -color white   sim:/tb_fpga_imem_lena/clk
add wave -color yellow  sim:/tb_fpga_imem_lena/reset

# ── Scalar Core: PC + Instruction fetch ──────────────────────────────────────
add wave -divider "Scalar Core — PC + IMEM Fetch"
add wave -color cyan   -radix hex   sim:/tb_fpga_imem_lena/pc_debug
add wave -color cyan                sim:/tb_fpga_imem_lena/insn_vld
add wave -color cyan   -radix hex   sim:/tb_fpga_imem_lena/u_core/inst_decode

# ── VPU Dispatch (scalar → VPU) ───────────────────────────────────────────────
add wave -divider "VPU Dispatch"
add wave -color magenta              sim:/tb_fpga_imem_lena/vpu_insn_vld
add wave -color magenta -radix hex   sim:/tb_fpga_imem_lena/vpu_insn
add wave -color magenta              sim:/tb_fpga_imem_lena/vpu_instr_name
add wave -color magenta -radix unsigned sim:/tb_fpga_imem_lena/vpu_rs1

# ── VPU Status ────────────────────────────────────────────────────────────────
add wave -divider "VPU Status"
add wave -color green                sim:/tb_fpga_imem_lena/vpu_ready
add wave -color red                  sim:/tb_fpga_imem_lena/vpu_busy
add wave -color white  -radix unsigned sim:/tb_fpga_imem_lena/csr_vl
add wave -color white  -radix hex    sim:/tb_fpga_imem_lena/csr_vtype

# ── FSM State (enum auto-decoded + string) ────────────────────────────────────
add wave -divider "FSM State"
add wave -color magenta  sim:/tb_fpga_imem_lena/u_vpu/fsm_inst/state_r
add wave -color magenta  sim:/tb_fpga_imem_lena/fsm_state_name

# ── VLSU State ────────────────────────────────────────────────────────────────
add wave -divider "VLSU State"
add wave -color yellow   sim:/tb_fpga_imem_lena/u_vpu/vlsu_inst/state_r
add wave -color yellow   sim:/tb_fpga_imem_lena/vlsu_busy_o

# ── VLSU Memory Bus ───────────────────────────────────────────────────────────
add wave -divider "VLSU Memory Bus"
add wave -color cyan                 sim:/tb_fpga_imem_lena/vlsu_req
add wave -color cyan                 sim:/tb_fpga_imem_lena/vlsu_we
add wave -color cyan   -radix hex    sim:/tb_fpga_imem_lena/vlsu_addr
add wave -color cyan   -radix hex    sim:/tb_fpga_imem_lena/vlsu_rdata
add wave -color green                sim:/tb_fpga_imem_lena/vlsu_ready

# ── VLSU VRF Write-back (loaded pixel data) ───────────────────────────────────
add wave -divider "VLSU VRF Write-back"
add wave -color yellow               sim:/tb_fpga_imem_lena/u_vpu/vlsu_vrf_we
add wave -color yellow -radix unsigned sim:/tb_fpga_imem_lena/u_vpu/vlsu_vrf_waddr
add wave -color yellow -radix hex    sim:/tb_fpga_imem_lena/u_vpu/vlsu_vrf_wdata_l0
add wave -color yellow -radix hex    sim:/tb_fpga_imem_lena/u_vpu/vlsu_vrf_wdata_l1
add wave -color yellow -radix hex    sim:/tb_fpga_imem_lena/u_vpu/vlsu_vrf_wdata_l2
add wave -color yellow -radix hex    sim:/tb_fpga_imem_lena/u_vpu/vlsu_vrf_wdata_l3

# ── ALU VRF Write-back ────────────────────────────────────────────────────────
add wave -divider "ALU VRF Write-back"
add wave -color green                sim:/tb_fpga_imem_lena/u_vpu/fsm_vrf_wren
add wave -color green  -radix unsigned sim:/tb_fpga_imem_lena/u_vpu/vd_addr_eff
add wave -color green  -radix hex    sim:/tb_fpga_imem_lena/u_vpu/vrf_wdata0_eff
add wave -color green  -radix hex    sim:/tb_fpga_imem_lena/u_vpu/vrf_wdata1_eff
add wave -color green  -radix hex    sim:/tb_fpga_imem_lena/u_vpu/vrf_wdata2_eff
add wave -color green  -radix hex    sim:/tb_fpga_imem_lena/u_vpu/vrf_wdata3_eff

wave zoom full
run -all
wave zoom full
