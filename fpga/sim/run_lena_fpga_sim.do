# =============================================================================
# run_lena_fpga_sim.do — Full FPGA UART→VPU→VGA lena simulation
#
# Chạy từ ModelSim console:
#   cd C:/CapstoneProject2/riscv_vpu
#   vsim -do fpga/sim/run_lena_fpga_sim.do
# =============================================================================

set RTL   C:/CapstoneProject2/riscv_vpu/fpga/rtl
set BENCH C:/CapstoneProject2/riscv_vpu/fpga/bench
set IP    C:/CapstoneProject2/riscv_vpu/fpga/ip

vlib work
vmap work work

# ── TileLink package ──────────────────────────────────────────────────────────
vlog -sv $RTL/bus/tl_pkg.sv

# ── Scalar pipeline leaf cells ────────────────────────────────────────────────
foreach f {
    full_adder.sv eight_bit_adder.sv adder.sv
    d_ff.sv register.sv
    decoder5to32.sv Regfile.sv register_file.sv
    mux2to1.sv mux2X1.sv mux4to1.sv mux8to1.sv mux32to1.sv
    immgen.sv
    mag_comparator.sv mag_comparator8.sv brc_comparator.sv brc.sv
    word_and.sv word_or.sv word_xor.sv
    barrel_shifter_32bit.sv barrel_shifter_32bit_left.sv
    alu.sv control_unit.sv pipelined_vpu.sv
} {
    vlog -sv $RTL/pipeline/$f
}

# ── IMEM sync wrapper (uses imem_b0..b3 below) ───────────────────────────────
vlog -sv $RTL/pipeline/imem_sync.sv

# ── IP behavioral models (replaces Quartus-generated .v for simulation) ───────
vlog -sv $IP/imem_b0.sv
vlog -sv $IP/imem_b1.sv
vlog -sv $IP/imem_b2.sv
vlog -sv $IP/imem_b3.sv
vlog -sv $IP/dmem_bank.sv
vlog -sv $IP/pll.sv

# ── UART ─────────────────────────────────────────────────────────────────────
vlog -sv $RTL/uart/uart.sv

# ── VPU modules ──────────────────────────────────────────────────────────────
foreach f {
    vproc_adder.sv vproc_mul.sv vproc_logic.sv vproc_shifter.sv
    vproc_compare.sv vproc_compare_combine.sv
    vproc_minmax.sv vproc_reduction.sv vproc_merge_unit.sv
    vproc_processor_lane.sv vproc_vregfile.sv vproc_mux_cells.sv
    vproc_mask_enable.sv vproc_mask_write_buffer.sv
    vproc_vcsr.sv vproc_cfg_encoder.sv vproc_cycle_counter.sv
    vproc_vrf_addr_gen.sv vproc_scalar_expand.sv
    vproc_fsm.sv vproc_fifo.sv vproc_vdecoder.sv
    vproc_vec_lsu.sv vproc_system_wrapper.sv
} {
    vlog -sv $RTL/vpu/$f
}

# ── DMEM wrapper ──────────────────────────────────────────────────────────────
vlog -sv $RTL/bus/dmem_arbiter.sv
vlog -sv $RTL/mem/dmem_qip_wrapper.sv

# ── VGA controller ────────────────────────────────────────────────────────────
vlog -sv $RTL/hdmi/vga_timing.sv
vlog -sv $RTL/vga/vga_ctrl.sv

# ── FPGA top + testbench ──────────────────────────────────────────────────────
vlog -sv $RTL/top/riscv_vpu_top_fpga.sv
vlog -sv $BENCH/tb_lena_fpga.sv

# ── Launch ────────────────────────────────────────────────────────────────────
vsim -t 1ps -voptargs=+acc work.tb_lena_fpga

# ── Waves ─────────────────────────────────────────────────────────────────────
add wave -divider "=== Clock / Reset ==="
add wave -radix hex     sim:/tb_lena_fpga/clk
add wave -radix hex     sim:/tb_lena_fpga/i_reset

add wave -divider "=== UART RX/TX ==="
add wave -color cyan    sim:/tb_lena_fpga/uart_rx_tb
add wave -color yellow  sim:/tb_lena_fpga/uart_tx_obs
add wave -radix unsigned sim:/tb_lena_fpga/dut/u_uart/rx_wptr
add wave -radix unsigned sim:/tb_lena_fpga/dut/u_uart/rx_rptr

add wave -divider "=== CPU ==="
add wave -radix hex     sim:/tb_lena_fpga/dut/o_pc_debug
add wave -radix hex     sim:/tb_lena_fpga/dut/o_insn_vld

add wave -divider "=== VPU ==="
add wave -color magenta sim:/tb_lena_fpga/dut/o_vpu_busy
add wave -radix unsigned sim:/tb_lena_fpga/dut/o_fsm_state
add wave -radix unsigned sim:/tb_lena_fpga/dut/o_vpu_cycles

add wave -divider "=== VGA output ==="
add wave -color green   sim:/tb_lena_fpga/dut/vga_hs
add wave -color green   sim:/tb_lena_fpga/dut/vga_vs
add wave -color green   sim:/tb_lena_fpga/dut/vga_blank_n
add wave -radix hex     sim:/tb_lena_fpga/dut/vga_r
add wave -radix hex     sim:/tb_lena_fpga/dut/vga_g
add wave -radix hex     sim:/tb_lena_fpga/dut/vga_b

run -all
