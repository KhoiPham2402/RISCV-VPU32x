transcript on

# run_lena_trial_sim.do — Lena benchmark on riscv_vpu_top_v2
#
# Prerequisites: rtl/imem_from_gcc.hex must contain the lena program.
#   If not current, rebuild first:
#     cd sw/benchmarks/lena_gray && make
#
# Run:
#   vsim -c -do run_lena_trial_sim.do
#
# After simulation:
#   python sw/benchmarks/lena_gray/reconstruct.py

if {![file exists work]} {
    vlib work
}

# Copy lena IMEM so imem_sync's $readmemh("imem.hex") finds it
file copy -force sw/benchmarks/lena_gray/lena_imem.hex imem.hex

# ===== TileLink package (must compile first) =====
vlog -sv rtl_trial/bus/tl_pkg.sv

# ===== RISC-V scalar primitives (shared cells) =====
vlog -sv \
    rtl/riscv/d_ff.sv \
    rtl/riscv/full_adder.sv \
    rtl/riscv/eight_bit_adder.sv \
    rtl/riscv/adder.sv \
    rtl/riscv/register.sv \
    rtl/riscv/decoder5to32.sv \
    rtl/riscv/Regfile.sv \
    rtl/riscv/mux2to1.sv \
    rtl/riscv/mux2X1.sv \
    rtl/riscv/mux4to1.sv \
    rtl/riscv/mux8to1.sv \
    rtl/riscv/mux32to1.sv \
    rtl/riscv/register_file.sv \
    rtl/riscv/immgen.sv \
    rtl/riscv/mag_comparator.sv \
    rtl/riscv/mag_comparator8.sv \
    rtl/riscv/brc_comparator.sv \
    rtl/riscv/brc.sv \
    rtl/riscv/word_and.sv \
    rtl/riscv/word_or.sv \
    rtl/riscv/word_xor.sv \
    rtl/riscv/barrel_shifter_32bit.sv \
    rtl/riscv/barrel_shifter_32bit_left.sv \
    rtl/riscv/alu.sv

# ===== VPU RTL =====
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

# ===== Trial design =====
vlog -sv \
    rtl_trial/mem/imem_sync.sv \
    rtl_trial/mem/dmem_sync.sv \
    rtl_trial/bus/tl_ul_dmem_adapter.sv \
    rtl_trial/bus/tl_ul_xbar.sv \
    rtl_trial/uart/uart.sv \
    rtl_trial/riscv/scalar_core_v2.sv \
    rtl_trial/riscv_vpu_top_v2.sv

# ===== Testbench =====
vlog -sv bench/tb_lena_gray_v2.sv

# ===== Run =====
vsim -voptargs=+acc work.tb_lena_gray_v2
run -all
quit -f
