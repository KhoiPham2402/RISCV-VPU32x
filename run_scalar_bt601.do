transcript on
set FPGA  [file normalize fpga]
set BENCH [file normalize bench]
set SW    [file normalize sw/benchmarks]

file copy -force $SW/scalar_bt601.hex $FPGA/uart_lena.hex
puts "INFO: scalar_bt601.hex loaded as IMEM"

catch {vdel -lib work -all}
vlib work; vmap work work

vlog -quiet -sv -work work $FPGA/rtl/bus/tl_pkg.sv

foreach f {pll.sv dmem_bank.sv dmem_bank_b0.sv dmem_bank_b1.sv
           dmem_bank_b2.sv dmem_bank_b3.sv
           imem_b0.sv imem_b1.sv imem_b2.sv imem_b3.sv} {
    vlog -quiet -sv -work work $FPGA/ip/$f
}
foreach f {full_adder.sv eight_bit_adder.sv adder.sv d_ff.sv register.sv
           decoder5to32.sv Regfile.sv register_file.sv
           mux2to1.sv mux2X1.sv mux4to1.sv mux8to1.sv mux32to1.sv
           immgen.sv mag_comparator.sv mag_comparator8.sv
           brc_comparator.sv brc.sv word_and.sv word_or.sv word_xor.sv
           barrel_shifter_32bit.sv barrel_shifter_32bit_left.sv
           alu.sv imem_sync.sv control_unit.sv pipelined_vpu.sv} {
    vlog -quiet -sv -work work $FPGA/rtl/pipeline/$f
}
vlog -quiet -sv -work work $FPGA/rtl/uart/uart.sv
foreach f {vproc_adder.sv vproc_mul.sv vproc_logic.sv vproc_shifter.sv
           vproc_compare.sv vproc_compare_combine.sv vproc_minmax.sv
           vproc_reduction.sv vproc_merge_unit.sv vproc_processor_lane.sv
           vproc_vregfile.sv vproc_mux_cells.sv vproc_mask_enable.sv
           vproc_mask_write_buffer.sv vproc_vcsr.sv vproc_cfg_encoder.sv
           vproc_cycle_counter.sv vproc_vrf_addr_gen.sv vproc_scalar_expand.sv
           vproc_fsm.sv vproc_fifo.sv vproc_vdecoder.sv
           vproc_vec_lsu.sv vproc_system_wrapper.sv} {
    vlog -quiet -sv -work work $FPGA/rtl/vpu/$f
}
vlog -quiet -sv -work work $FPGA/rtl/bus/dmem_arbiter.sv
vlog -quiet -sv -work work $FPGA/rtl/mem/dmem_qip_wrapper.sv
vlog -quiet -sv -work work $FPGA/rtl/hdmi/vga_timing.sv
vlog -quiet -sv -work work $FPGA/rtl/vga/vga_ctrl.sv
vlog -quiet -sv -work work $FPGA/rtl/top/riscv_vpu_top_fpga.sv
vlog -quiet -sv -work work $BENCH/tb_scalar_bench.sv

vsim -c -voptargs=+acc work.tb_scalar_bench
run 30000000ns
quit -f
