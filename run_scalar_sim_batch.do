# run_scalar_sim_batch.do
# Compile once, then run AXPY scalar + BT601 scalar simulations.
# Detection: PC stops changing for 200 consecutive cycles.

transcript on
set ROOT [file normalize [pwd]]
set IMEM [file join $ROOT rtl imem_from_gcc.hex]
set SW   [file join $ROOT sw benchmarks]

# ── Compile ───────────────────────────────────────────────────────────────────
catch { vdel -lib work -all }
vlib work
vmap work work

set rtl [file join $ROOT rtl]
foreach f {
    d_ff.sv full_adder.sv eight_bit_adder.sv adder.sv register.sv
    decoder5to32.sv Regfile.sv register_file.sv
    mux2to1.sv mux2X1.sv mux4to1.sv mux8to1.sv mux32to1.sv
    immgen.sv mag_comparator.sv mag_comparator8.sv
    brc_comparator.sv brc.sv word_and.sv word_or.sv word_xor.sv
    barrel_shifter_32bit.sv barrel_shifter_32bit_left.sv
    alu.sv lsu.sv imem.sv control_unit.sv single_cycle.sv
} { vlog -quiet -sv -work work [file join $rtl riscv $f] }

foreach f {
    vproc_adder.sv vproc_mul.sv vproc_logic.sv vproc_shifter.sv
    vproc_compare.sv vproc_compare_combine.sv vproc_minmax.sv
    vproc_reduction.sv vproc_merge_unit.sv vproc_processor_lane.sv
    vproc_vregfile.sv vproc_mux_cells.sv vproc_mask_enable.sv
    vproc_mask_write_buffer.sv vproc_vcsr.sv vproc_cfg_encoder.sv
    vproc_cycle_counter.sv vproc_vrf_addr_gen.sv vproc_scalar_expand.sv
    vproc_fsm.sv vproc_fifo.sv vproc_vdecoder.sv
    vproc_vec_lsu.sv vproc_system_wrapper.sv
} { vlog -quiet -sv -work work [file join $rtl $f] }

vlog -quiet -sv -work work [file join $rtl riscv_vpu_top.sv]
vlog -quiet -sv -work work [file join $ROOT bench tb_scalar_io_detect.sv]
puts "COMPILE OK"

# ── Helper ────────────────────────────────────────────────────────────────────
proc run_hex {hex_file label run_ns} {
    global IMEM
    set backup "${IMEM}.bak"
    file copy -force $IMEM $backup
    file copy -force $hex_file $IMEM
    puts "--- $label : IMEM <- [file tail $hex_file] ---"
    vsim -quiet -c -voptargs=+acc work.tb_scalar_io_detect
    run $run_ns
    quit -sim
    file copy -force $backup $IMEM
    file delete -force $backup
}

# ── AXPY scalar ───────────────────────────────────────────────────────────────
puts ""
puts "=== BENCHMARK: AXPY N=16 (Scalar, single-cycle) ==="
run_hex [file join $SW scalar_axpy.hex]  "AXPY-scalar"  1000000ns

# ── BT.601 scalar ─────────────────────────────────────────────────────────────
puts ""
puts "=== BENCHMARK: BT.601 16384px (Scalar, single-cycle) ==="
run_hex [file join $SW scalar_bt601.hex] "BT601-scalar" 25000000ns

puts ""
puts "=== KNOWN VPU RESULTS (simulation evidence, Apr-May 2026) ==="
puts "  AXPY N=16          VPU =    221 cycles  [results/axpy/sim_log_raw.txt]"
puts "  MatMul 4x4         VPU =    317 cycles  [results/matmul/regression_raw.txt]"
puts "  Lena 128x128 BT601 VPU = 34828 cycles  [PROJECT_STATUS.md 2026-05-02]"

quit -f
