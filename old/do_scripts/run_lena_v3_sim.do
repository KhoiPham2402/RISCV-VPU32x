transcript on

# run_lena_v3_sim.do — Lena 128x128 RGB→Grayscale on riscv_vpu_top_v3
# (5-stage pipelined RISC-V + sync DMEM + VPU)
#
# Run:
#   vsim -c -do run_lena_v3_sim.do
#
# After simulation:
#   python sw/benchmarks/lena_gray/reconstruct.py

if {![file exists work]} {
    vlib work
}

# Copy lena IMEM so imem_sync's $readmemh("imem.hex") finds it
file copy -force sw/benchmarks/lena_gray/lena_imem.hex imem.hex

# ===== Compile pipeline utility modules =====
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

# ===== Compile sync DMEM =====
vlog -sv rtl_trial/mem/dmem_sync.sv

# ===== Compile VPU =====
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

# ===== Compile Top + Testbench =====
vlog -sv \
    rtl/riscv_vpu_top_v3.sv \
    bench/tb_lena_gray_v3.sv

# ===== Simulate =====
vsim -voptargs=+acc work.tb_lena_gray_v3

run -all
quit -f

# After simulation, verify with:
#   python sw/benchmarks/lena_gray/reconstruct.py sw/benchmarks/lena_gray/lena_dmem_out_v3.hex
