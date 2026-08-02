## run_wave_dmem_lena.do — Clean waveform: DMEM lena với tên lệnh decoded
## Run: vsim -do run_wave_dmem_lena.do
## Sau khi load: "run 30us" thấy 1-2 vòng lặp; "run -all" chạy toàn bộ ảnh.

transcript on

set ROOT  [file normalize [pwd]]
set FPGA  [file join $ROOT fpga]
set BENCH [file join $ROOT bench]

file copy -force [file join $FPGA dmem_lena.hex] [file join $FPGA uart_lena.hex]

catch {vdel -lib work -all}
vlib work ; vmap work work

vlog -sv -work work [file join $FPGA rtl bus tl_pkg.sv]

foreach f {pll.sv dmem_bank.sv dmem_bank_b0.sv dmem_bank_b1.sv
           dmem_bank_b2.sv dmem_bank_b3.sv
           imem_b0.sv imem_b1.sv imem_b2.sv imem_b3.sv} {
    vlog -sv -work work [file join $FPGA ip $f]
}
foreach f {full_adder.sv eight_bit_adder.sv adder.sv d_ff.sv register.sv
           decoder5to32.sv Regfile.sv register_file.sv
           mux2to1.sv mux2X1.sv mux4to1.sv mux8to1.sv mux32to1.sv immgen.sv
           mag_comparator.sv mag_comparator8.sv brc_comparator.sv brc.sv
           word_and.sv word_or.sv word_xor.sv
           barrel_shifter_32bit.sv barrel_shifter_32bit_left.sv
           alu.sv imem_sync.sv control_unit.sv pipelined_vpu.sv} {
    vlog -sv -work work [file join $FPGA rtl pipeline $f]
}
vlog -sv -work work [file join $FPGA rtl uart uart.sv]
foreach f {vproc_adder.sv vproc_mul.sv vproc_logic.sv vproc_shifter.sv
           vproc_compare.sv vproc_compare_combine.sv vproc_minmax.sv
           vproc_reduction.sv vproc_merge_unit.sv vproc_processor_lane.sv
           vproc_vregfile.sv vproc_mux_cells.sv vproc_mask_enable.sv
           vproc_mask_write_buffer.sv vproc_vcsr.sv vproc_cfg_encoder.sv
           vproc_cycle_counter.sv vproc_vrf_addr_gen.sv vproc_scalar_expand.sv
           vproc_fsm.sv vproc_fifo.sv vproc_vdecoder.sv
           vproc_vec_lsu.sv vproc_system_wrapper.sv} {
    vlog -sv -work work [file join $FPGA rtl vpu $f]
}
vlog -sv -work work [file join $FPGA rtl bus dmem_arbiter.sv]
vlog -sv -work work [file join $FPGA rtl mem dmem_qip_wrapper.sv]
vlog -sv -work work [file join $FPGA rtl hdmi vga_timing.sv]
vlog -sv -work work [file join $FPGA rtl vga vga_ctrl.sv]
vlog -sv -work work [file join $FPGA rtl top riscv_vpu_top_fpga.sv]
vlog -sv -work work [file join $BENCH tb_wave_dmem_lena.sv]

vsim -voptargs=+acc work.tb_wave_dmem_lena

# ════════════════════════════════════════════════════════════════════════════
# WAVEFORM — chỉ giữ tín hiệu cốt lõi, hiện tên lệnh thay vì hex
# ════════════════════════════════════════════════════════════════════════════

add wave -divider "══ CLOCK / RESET / PLL ══"
add wave -color White  -radix binary  /tb_wave_dmem_lena/clk
add wave -color Red    -radix binary  /tb_wave_dmem_lena/reset
add wave -color Yellow -radix binary  /tb_wave_dmem_lena/dut/pll_locked
add wave -color Cyan   -radix binary  /tb_wave_dmem_lena/dut/rst_n

add wave -divider "══ SCALAR CORE ══"
add wave -color White  -radix hex     /tb_wave_dmem_lena/dut/u_core/pce
add wave -color Gold   -label "insn@EX" \
                               /tb_wave_dmem_lena/scalar_insn
add wave -color Gray   -radix binary  /tb_wave_dmem_lena/dut/u_core/vpu_stall

add wave -divider "══ REGISTER FILE ══"
add wave -color Green  -radix binary   /tb_wave_dmem_lena/dut/u_core/rf_wren
add wave -color Gold   -label "WB→rd"  /tb_wave_dmem_lena/wb_rd_name
add wave -color Cyan   -radix hex      /tb_wave_dmem_lena/dut/u_core/rf_wdata
add wave -color White  -radix hex      /tb_wave_dmem_lena/dut/u_core/rs1_raw
add wave -color White  -radix hex      /tb_wave_dmem_lena/dut/u_core/rs2_raw

add wave -divider "══ VPU DISPATCH ══"
add wave -color Green  -radix binary  /tb_wave_dmem_lena/dut/vpu_insn_vld
add wave -color Gold   -label "vpu_insn" \
                               /tb_wave_dmem_lena/vpu_insn_name
add wave -color Yellow -radix hex     /tb_wave_dmem_lena/dut/vpu_rs1_data
add wave -color Cyan   -radix binary  /tb_wave_dmem_lena/dut/vpu_ready

add wave -divider "══ VPU FSM ══"
add wave -color Gold   -label "fsm_state" \
                               /tb_wave_dmem_lena/fsm_state_name
add wave -color Red    -radix binary  /tb_wave_dmem_lena/vpu_busy
add wave -color White  -radix unsigned /tb_wave_dmem_lena/dut/u_vpu/csr_vl_o

add wave -divider "══ VLSU ══"
add wave -color Gold   -label "vlsu_op"  /tb_wave_dmem_lena/vlsu_op
add wave -color White  -radix hex     /tb_wave_dmem_lena/dut/vlsu_addr
add wave -color Yellow -radix binary  /tb_wave_dmem_lena/dut/vlsu_be
add wave -color Cyan   -radix hex     /tb_wave_dmem_lena/dut/vlsu_wdata
add wave -color Gray   -radix hex     /tb_wave_dmem_lena/dut/vlsu_rdata

add wave -divider "══ VRF WRITE ══"
add wave -color Green  -radix unsigned /tb_wave_dmem_lena/dut/u_vpu/vrf_waddr_eff
add wave -color Yellow -radix binary   /tb_wave_dmem_lena/dut/u_vpu/vrf_we0_eff
add wave -color Cyan   -radix hex      /tb_wave_dmem_lena/dut/u_vpu/vrf_wdata0_eff
add wave -color Cyan   -radix hex      /tb_wave_dmem_lena/dut/u_vpu/vrf_wdata1_eff
add wave -color Cyan   -radix hex      /tb_wave_dmem_lena/dut/u_vpu/vrf_wdata2_eff
add wave -color Cyan   -radix hex      /tb_wave_dmem_lena/dut/u_vpu/vrf_wdata3_eff

# Chạy đủ thấy reset + PLL lock + 2 vòng lặp đầu (~3000 cycles = 60us)
run 60us
