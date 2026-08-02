# =============================================================================
# run_fpga_top_compile_check.do — Elaborate the full FPGA top level
# (de10_standard_top -> riscv_vpu_top_fpga -> pipeline + VPU + UART + VGA +
# DMEM + PLL) to catch compile/elaboration errors. Uses the behavioral
# simulation stand-ins under fpga/ip/ for the Quartus-generated dmem_bank and
# pll IP (real hardware uses the .qip versions instead).
#
# Chạy từ project root: vsim -c -do fpga/sim/run_fpga_top_compile_check.do
# =============================================================================
set RTL fpga/rtl
set IP  fpga/ip

vlib work
vmap work work

vlog -sv $RTL/bus/tl_pkg.sv

vlog -sv $IP/dmem_bank.sv
vlog -sv $IP/dmem_bank_b0.sv
vlog -sv $IP/dmem_bank_b1.sv
vlog -sv $IP/dmem_bank_b2.sv
vlog -sv $IP/dmem_bank_b3.sv
vlog -sv $IP/pll.sv

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

vlog -sv $RTL/uart/uart.sv

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

vlog -sv $RTL/bus/dmem_arbiter.sv
vlog -sv $RTL/mem/dmem_qip_wrapper.sv
vlog -sv $RTL/hdmi/vga_timing.sv
vlog -sv $RTL/vga/vga_ctrl.sv
vlog -sv $RTL/top/riscv_vpu_top_fpga.sv
vlog -sv $RTL/top/de10_standard_top.sv

vsim -c work.de10_standard_top
quit -f
