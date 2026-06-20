## run_wave_lena.do — Lena RGB→Gray waveform: scalar PC + VPU FSM + VLSU bus
## Run: vsim -do run_wave_lena.do

transcript on

# ── Copy lena firmware → IMEM ─────────────────────────────────────────────
set LENA_HEX [file normalize "sw/benchmarks/lena_gray/lena_imem.hex"]
set IMEM_HEX [file normalize "rtl/imem_from_gcc.hex"]
if {![file exists $LENA_HEX]} { puts "ERROR: lena_imem.hex not found"; quit -f }
file copy -force $LENA_HEX $IMEM_HEX

if {![file exists work]} { vlib work }

# ── Compile scalar core ───────────────────────────────────────────────────
vlog -sv \
    rtl/riscv/d_ff.sv rtl/riscv/full_adder.sv rtl/riscv/eight_bit_adder.sv \
    rtl/riscv/adder.sv rtl/riscv/register.sv rtl/riscv/decoder5to32.sv \
    rtl/riscv/Regfile.sv rtl/riscv/mux2to1.sv rtl/riscv/mux2X1.sv \
    rtl/riscv/mux4to1.sv rtl/riscv/mux8to1.sv rtl/riscv/mux32to1.sv \
    rtl/riscv/register_file.sv rtl/riscv/immgen.sv \
    rtl/riscv/mag_comparator.sv rtl/riscv/mag_comparator8.sv \
    rtl/riscv/brc_comparator.sv rtl/riscv/brc.sv \
    rtl/riscv/word_and.sv rtl/riscv/word_or.sv rtl/riscv/word_xor.sv \
    rtl/riscv/barrel_shifter_32bit.sv rtl/riscv/barrel_shifter_32bit_left.sv \
    rtl/riscv/alu.sv rtl/riscv/lsu.sv rtl/riscv/imem.sv \
    rtl/riscv/control_unit.sv rtl/riscv/single_cycle.sv

# ── Compile VPU ───────────────────────────────────────────────────────────
vlog -sv \
    rtl/vproc_adder.sv rtl/vproc_mul.sv rtl/vproc_logic.sv \
    rtl/vproc_shifter.sv rtl/vproc_compare.sv rtl/vproc_compare_combine.sv \
    rtl/vproc_minmax.sv rtl/vproc_reduction.sv rtl/vproc_merge_unit.sv \
    rtl/vproc_processor_lane.sv rtl/vproc_vregfile.sv rtl/vproc_mux_cells.sv \
    rtl/vproc_mask_enable.sv rtl/vproc_mask_write_buffer.sv \
    rtl/vproc_vcsr.sv rtl/vproc_cfg_encoder.sv rtl/vproc_cycle_counter.sv \
    rtl/vproc_vrf_addr_gen.sv rtl/vproc_scalar_expand.sv \
    rtl/vproc_fsm.sv rtl/vproc_fifo.sv rtl/vproc_vdecoder.sv \
    rtl/vproc_vec_lsu.sv rtl/vproc_system_wrapper.sv

# ── Compile top + testbench ───────────────────────────────────────────────
vlog -sv rtl/riscv_vpu_top.sv bench/tb_lena_gray.sv

vsim -voptargs=+acc work.tb_lena_gray

# ── Scalar core ──────────────────────────────────────────────────────────
add wave -divider "━━━ SCALAR CORE ━━━"
add wave -radix binary   /tb_lena_gray/clk
add wave -radix binary   /tb_lena_gray/rst_n
add wave -radix hex      /tb_lena_gray/dut/u_scalar_core/pc
add wave -radix hex      /tb_lena_gray/dut/u_scalar_core/inst
add wave -radix binary   /tb_lena_gray/dut/u_scalar_core/vpu_insn_vld

# ── VPU dispatch ─────────────────────────────────────────────────────────
add wave -divider "━━━ VPU DISPATCH ━━━"
add wave -radix binary   /tb_lena_gray/dut/u_vpu/instr_valid
add wave -radix hex      /tb_lena_gray/dut/u_vpu/instruction
add wave -radix binary   /tb_lena_gray/dut/u_vpu/vpu_ready
add wave -radix binary   /tb_lena_gray/dut/u_vpu/fifo_full

# ── VPU FSM ──────────────────────────────────────────────────────────────
add wave -divider "━━━ VPU FSM ━━━"
add wave -radix unsigned /tb_lena_gray/dut/u_vpu/fsm_state
add wave -radix binary   /tb_lena_gray/dut/u_vpu/busy
add wave -radix unsigned /tb_lena_gray/dut/u_vpu/csr_vl_o

# ── VLSU memory bus ───────────────────────────────────────────────────────
add wave -divider "━━━ VLSU BUS ━━━"
add wave -radix binary   /tb_lena_gray/dut/u_vpu/vlsu_mem_req
add wave -radix binary   /tb_lena_gray/dut/u_vpu/vlsu_mem_we
add wave -radix hex      /tb_lena_gray/dut/u_vpu/vlsu_mem_addr
add wave -radix binary   /tb_lena_gray/dut/u_vpu/vlsu_mem_be
add wave -radix hex      /tb_lena_gray/dut/u_vpu/vlsu_mem_wdata
add wave -radix hex      /tb_lena_gray/dut/u_vpu/vlsu_mem_rdata

# ── VPU writeback ─────────────────────────────────────────────────────────
add wave -divider "━━━ VPU WRITEBACK ━━━"
add wave -radix hex      /tb_lena_gray/dut/u_vpu/wb_result_lane0
add wave -radix hex      /tb_lena_gray/dut/u_vpu/wb_result_lane1
add wave -radix hex      /tb_lena_gray/dut/u_vpu/wb_result_lane2
add wave -radix hex      /tb_lena_gray/dut/u_vpu/wb_result_lane3

run 5000ns
