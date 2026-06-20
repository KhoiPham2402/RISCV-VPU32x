transcript on

# run_uart_sim.do — UART firmware simulation: receive pixels → VPU grayscale → ACK
#
# Firmware: sw/uart_lena_test.S (16 pixels, R=G=B=128, expected Y=127)
# Baud divisor = 7 → 8 clock cycles/bit (fast simulation)
#
# Steps:
#   1. Build firmware: cd sw && make uart_lena_test.hex
#   2. Copy hex to imem.hex (where imem_sync loads from by default)
#   3. Compile RTL and run simulation
#
# Run:
#   vsim -c -do run_uart_sim.do

if {![file exists work]} {
    vlib work
}

# ── Build firmware ──────────────────────────────────────────────────────────
# Produces sw/../uart_lena_test.hex (i.e. uart_lena_test.hex in project root)
if {[catch {exec make -C sw uart_lena_test.hex} msg]} {
    puts "WARNING: make failed — using existing uart_lena_test.hex if present"
    puts $msg
}
file copy -force uart_lena_test.hex imem.hex

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
    bench/tb_uart_lena.sv

# ── Simulate ──────────────────────────────────────────────────────────────────
vsim -voptargs=+acc work.tb_uart_lena

run -all
quit -f
