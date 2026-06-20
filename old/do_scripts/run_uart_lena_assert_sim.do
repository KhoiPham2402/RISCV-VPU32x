transcript on

# run_uart_lena_assert_sim.do — Full assertion simulation for lena 128×128 FPGA readiness
#
# Testbench: bench/tb_uart_lena_assert.sv
# Assertions:
#   [A1]  No DMEM access during reset
#   [A2]  PC watchdog (no deadlock)
#   [A3]  UART TX frame (start=0, stop=1)
#   [A4]  No X/Z in UART TX data
#   [A5]  Scalar write only in [0x0000–0xBFFF]
#   [A6]  dmem_sync Port A+B same-word write hazard (in RTL)
#   [A7]  ACK = 0xAA
#   [A8]  All 16384 Y pixels match BT.601 reference model
#   [A9]  No Y pixel > 253 (8-bit BT.601 max, no overflow)
#   [A10] R/G/B data in DMEM matches what was sent
#   [A11] Global timeout guard
#
# Run:
#   vsim -c -do run_uart_lena_assert_sim.do

if {![file exists work]} {
    vlib work
}

# ── Build firmware ────────────────────────────────────────────────────────────
if {[catch {exec make -C sw uart_lena.hex} msg]} {
    puts "WARNING: make failed — using existing uart_lena.hex"
    puts $msg
}
if {![file exists uart_lena.hex]} {
    puts "ERROR: uart_lena.hex not found. Run: cd sw && make uart_lena.hex"
    quit -f
}
file copy -force uart_lena.hex imem.hex
puts "INFO: Copied uart_lena.hex → imem.hex"

# ── Ensure output directory ───────────────────────────────────────────────────
file mkdir sw/benchmarks/lena_gray/v3_output

# ── Compile TileLink package ──────────────────────────────────────────────────
vlog -sv rtl_trial/bus/tl_pkg.sv

# ── Compile UART ──────────────────────────────────────────────────────────────
vlog -sv rtl_trial/uart/uart.sv

# ── Compile pipeline modules ──────────────────────────────────────────────────
vlog -sv \
    rtl/pipeline/full_adder.sv \
    rtl/pipeline/eight_bit_adder.sv \
    rtl/pipeline/adder.sv \
    rtl/pipeline/d_ff.sv \
    rtl/pipeline/register.sv \
    rtl/pipeline/decoder5to32.sv \
    rtl/pipeline/Regfile.sv \
    rtl/pipeline/register_file.sv \
    rtl/pipeline/mux2to1.sv \
    rtl/pipeline/mux2X1.sv \
    rtl/pipeline/mux4to1.sv \
    rtl/pipeline/mux8to1.sv \
    rtl/pipeline/mux32to1.sv \
    rtl/pipeline/immgen.sv \
    rtl/pipeline/mag_comparator.sv \
    rtl/pipeline/mag_comparator8.sv \
    rtl/pipeline/brc_comparator.sv \
    rtl/pipeline/brc.sv \
    rtl/pipeline/word_and.sv \
    rtl/pipeline/word_or.sv \
    rtl/pipeline/word_xor.sv \
    rtl/pipeline/barrel_shifter_32bit.sv \
    rtl/pipeline/barrel_shifter_32bit_left.sv \
    rtl/pipeline/alu.sv \
    rtl/pipeline/imem_sync.sv \
    rtl/pipeline/control_unit.sv \
    rtl/pipeline/pipelined_vpu.sv

# ── Compile sync DMEM (TDP model with assertions) ────────────────────────────
vlog -sv rtl_trial/mem/dmem_sync.sv

# ── Compile VPU ───────────────────────────────────────────────────────────────
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
    rtl/vproc_system_wrapper.sv

# ── Compile top + assertion testbench ─────────────────────────────────────────
vlog -sv \
    rtl/riscv_vpu_top_v4.sv \
    bench/tb_uart_lena_assert.sv

# ── Simulate ──────────────────────────────────────────────────────────────────
puts ""
puts "INFO: Starting assertion simulation (~4M cycles, several minutes)"
puts "INFO: Watch for [FAIL] lines — any is a regression"
puts ""

vsim -voptargs=+acc work.tb_uart_lena_assert

run -all
quit -f
