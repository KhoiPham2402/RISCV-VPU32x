transcript on

# run_uart_echo_sim.do — UART → VPU BT.601 → UART echo simulation
#
# Firmware: sw/uart_echo.S (receive 3×16 RGB bytes, run VPU, echo 16 Y bytes + ACK)
# Testbench: bench/tb_uart_echo.sv (16 known pixels, per-pixel pass/fail table)
# Expected sim time: < 20 000 cycles (~5 200 UART cycles + VPU processing)
#
# Run:
#   vsim -c -do run_uart_echo_sim.do

if {![file exists work]} {
    vlib work
}

# ── Build echo firmware ──────────────────────────────────────────────────────
if {[catch {exec make -C sw uart_echo.hex} msg]} {
    puts "WARNING: make failed — using existing uart_echo.hex if present"
    puts $msg
}

if {![file exists uart_echo.hex]} {
    puts "ERROR: uart_echo.hex not found. Build manually: cd sw && make uart_echo.hex"
    quit -f
}

file copy -force uart_echo.hex imem.hex
puts "INFO: Copied uart_echo.hex → imem.hex"

# ── Compile TileLink package ─────────────────────────────────────────────────
vlog -sv rtl_trial/bus/tl_pkg.sv

# ── Compile UART ─────────────────────────────────────────────────────────────
vlog -sv rtl_trial/uart/uart.sv

# ── Compile pipeline utility modules ─────────────────────────────────────────
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

# ── Compile sync DMEM ─────────────────────────────────────────────────────────
vlog -sv rtl_trial/mem/dmem_sync.sv

# ── Compile VPU ──────────────────────────────────────────────────────────────
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

# ── Compile v4 top + testbench ────────────────────────────────────────────────
vlog -sv \
    rtl/riscv_vpu_top_v4.sv \
    bench/tb_uart_echo.sv

# ── Simulate ──────────────────────────────────────────────────────────────────
puts ""
puts "INFO: Starting UART echo simulation (16 pixels, ~20 000 cycles max)."
puts ""

vsim -voptargs=+acc work.tb_uart_echo

run -all
quit -f
