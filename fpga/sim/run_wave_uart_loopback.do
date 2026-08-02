# run_wave_uart_loopback.do — UART loopback waveform (FPGA system)
# vsim -do fpga/sim/run_wave_uart_loopback.do

set ROOT C:/CapstoneProject2/riscv_vpu
set FPGA $ROOT/fpga

catch {vdel -lib work -all}
vlib work; vmap work work

vlog -sv $FPGA/rtl/bus/tl_pkg.sv
vlog -sv $FPGA/ip/pll.sv
vlog -sv $FPGA/ip/dmem_bank.sv
vlog -sv $FPGA/ip/imem_b0.sv $FPGA/ip/imem_b1.sv $FPGA/ip/imem_b2.sv $FPGA/ip/imem_b3.sv
foreach f {
    full_adder.sv eight_bit_adder.sv adder.sv d_ff.sv register.sv
    decoder5to32.sv Regfile.sv register_file.sv
    mux2to1.sv mux2X1.sv mux4to1.sv mux8to1.sv mux32to1.sv
    immgen.sv mag_comparator.sv mag_comparator8.sv brc_comparator.sv brc.sv
    word_and.sv word_or.sv word_xor.sv barrel_shifter_32bit.sv
    barrel_shifter_32bit_left.sv alu.sv imem_sync.sv control_unit.sv pipelined_vpu.sv
} { vlog -sv $FPGA/rtl/pipeline/$f }
vlog -sv $FPGA/rtl/uart/uart.sv
foreach f {
    vproc_adder.sv vproc_mul.sv vproc_logic.sv vproc_shifter.sv
    vproc_compare.sv vproc_compare_combine.sv vproc_minmax.sv
    vproc_reduction.sv vproc_merge_unit.sv vproc_processor_lane.sv
    vproc_vregfile.sv vproc_mux_cells.sv vproc_mask_enable.sv
    vproc_mask_write_buffer.sv vproc_vcsr.sv vproc_cfg_encoder.sv
    vproc_cycle_counter.sv vproc_vrf_addr_gen.sv vproc_scalar_expand.sv
    vproc_fsm.sv vproc_fifo.sv vproc_vdecoder.sv
    vproc_vec_lsu.sv vproc_system_wrapper.sv
} { vlog -sv $FPGA/rtl/vpu/$f }
vlog -sv $FPGA/rtl/bus/dmem_arbiter.sv
vlog -sv $FPGA/rtl/mem/dmem_qip_wrapper.sv
vlog -sv $FPGA/rtl/hdmi/vga_timing.sv
vlog -sv $FPGA/rtl/vga/vga_ctrl.sv
vlog -sv $FPGA/rtl/top/riscv_vpu_top_fpga.sv
vlog -sv $FPGA/bench/tb_uart_loopback_system.sv

vsim -t 1ps -voptargs=+acc work.tb_uart_loopback_system

# ── Serial lines ──────────────────────────────────────────────────────────────
add wave -divider "Serial Lines"
add wave -color cyan   sim:/tb_uart_loopback_system/uart_rx_tb
add wave -color yellow sim:/tb_uart_loopback_system/uart_tx_fpga

# ── UART RX engine ────────────────────────────────────────────────────────────
add wave -divider "UART RX Engine"
add wave -color cyan   sim:/tb_uart_loopback_system/dut/u_uart/rx_sync1
add wave -color cyan   sim:/tb_uart_loopback_system/dut/u_uart/rx_active
add wave -color cyan   -radix unsigned sim:/tb_uart_loopback_system/dut/u_uart/rx_bit_cnt
add wave -color cyan   -radix unsigned sim:/tb_uart_loopback_system/dut/u_uart/rx_baud_cnt
add wave -color cyan   -radix hex      sim:/tb_uart_loopback_system/dut/u_uart/rx_shift
add wave -color green  sim:/tb_uart_loopback_system/dut/u_uart/rx_empty
add wave -color green  -radix hex      sim:/tb_uart_loopback_system/dut/u_uart/rx_fifo

# ── UART TX engine ────────────────────────────────────────────────────────────
add wave -divider "UART TX Engine"
add wave -color yellow sim:/tb_uart_loopback_system/dut/u_uart/tx_busy
add wave -color yellow -radix unsigned sim:/tb_uart_loopback_system/dut/u_uart/tx_bit_cnt
add wave -color yellow -radix unsigned sim:/tb_uart_loopback_system/dut/u_uart/tx_baud_cnt
add wave -color yellow -radix hex      sim:/tb_uart_loopback_system/dut/u_uart/tx_shift
add wave -color yellow sim:/tb_uart_loopback_system/dut/u_uart/tx_empty
add wave -color yellow -radix hex      sim:/tb_uart_loopback_system/dut/u_uart/tx_fifo

# ── TileLink bus (scalar → UART) ─────────────────────────────────────────────
add wave -divider "TL-UL (Scalar -> UART)"
add wave -color magenta sim:/tb_uart_loopback_system/dut/uart_tl_a.valid
add wave -color magenta -radix hex sim:/tb_uart_loopback_system/dut/uart_tl_a.address
add wave -color magenta -radix hex sim:/tb_uart_loopback_system/dut/uart_tl_a.data
add wave -color magenta -radix hex sim:/tb_uart_loopback_system/dut/uart_tl_d.data

# ── Scalar core PC ────────────────────────────────────────────────────────────
add wave -divider "Scalar Core"
add wave -color white  -radix hex sim:/tb_uart_loopback_system/dut/u_core/pc
add wave -color white  -radix hex sim:/tb_uart_loopback_system/dut/u_core/inst_decode

wave zoom full
run -all
wave zoom full
