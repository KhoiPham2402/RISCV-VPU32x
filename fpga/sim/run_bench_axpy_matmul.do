# =============================================================================
# run_bench_axpy_matmul.do — AXPY + matmul benchmarks against fpga/rtl
# 5-stage pipeline + VPU (see fpga/bench/tb_bench_generic.sv).
#
# Expected values come from sw/benchmarks/{axpy,matmul}/main.c comments.
# Chạy từ project root: vsim -c -do fpga/sim/run_bench_axpy_matmul.do
# =============================================================================
set RTL fpga/rtl
set IP  fpga/ip

vlib work
vmap work work

vlog -sv $IP/imem_b0.sv
vlog -sv $IP/imem_b1.sv
vlog -sv $IP/imem_b2.sv
vlog -sv $IP/imem_b3.sv

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

vlog -sv fpga/rtl/bus/dmem_arbiter.sv
vlog -sv fpga/bench/dmem_model_sp.sv
vlog -sv fpga/bench/tb_bench_generic.sv

set AXPY_HEX   [pwd]/sw/benchmarks/axpy/axpy_imem.hex
set MATMUL_HEX [pwd]/sw/benchmarks/matmul/matmul_imem.hex

echo "=================== AXPY ==================="
vsim -c -t 1ps \
    -gIMEM_FILE=$AXPY_HEX -gMAX_CYCLES=20000 \
    -gEXP0=4 -gEXP1=16 -gEXP2=28 -gEXP3=40 -gNAME=AXPY \
    work.tb_bench_generic
run -all
quit -sim

echo "=================== MATMUL ==================="
vsim -c -t 1ps \
    -gIMEM_FILE=$MATMUL_HEX -gMAX_CYCLES=20000 \
    -gEXP0=10 -gEXP1=26 -gEXP2=42 -gEXP3=58 -gNAME=MATMUL \
    work.tb_bench_generic
run -all
quit -sim

quit -f
