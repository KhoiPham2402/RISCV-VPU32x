## run_pipeline_lena.do — Lena 128x128 grayscale on pipelined VPU
## Loads lena_imem.hex (compiled lena_gray.c) + lena_dmem_init.hex via testbench backdoor.
## Run from project root: vsim -c -do run_pipeline_lena.do
## After simulation: python sw/benchmarks/lena_gray/reconstruct.py \
##   sw/benchmarks/lena_gray/pipeline_output/lena_dmem_out_pipeline.hex

transcript on

if {![file exists work]} { vlib work }

# ── RISC-V scalar core ────────────────────────────────────────────────────────
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
    rtl/riscv/alu.sv \
    rtl/riscv/lsu.sv \
    rtl/riscv/imem.sv \
    rtl/riscv/control_unit.sv \
    rtl/riscv/single_cycle.sv

# ── Pipelined VPU ─────────────────────────────────────────────────────────────
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
    rtl/vproc_fifo.sv \
    rtl/vproc_vdecoder.sv \
    rtl/vproc_vec_lsu.sv \
    rtl_pipeline/vproc_fsm_p.sv \
    rtl_pipeline/vproc_system_wrapper_p.sv \
    rtl_pipeline/riscv_vpu_top_pipeline.sv \
    bench/tb_pipeline_lena.sv

vsim -voptargs=+acc work.tb_pipeline_lena

run -all
quit -f
