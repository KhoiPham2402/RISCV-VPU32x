## run_wave_full_vpu.do
## Full design waveform debug — scalar core + VPU, program từ vpu_demo.hex
##
## Cách đọc waveform:
##   Group 1  SCALAR PC/INST  : biết scalar core đang fetch lệnh nào, OP-V hay scalar
##   Group 2  VPU DISPATCH     : khi nào lệnh VPU được issue vào FIFO
##   Group 3  FSM STATE        : VPU đang ở giai đoạn nào (IDLE/CONFIG/EXEC/...)
##   Group 4  VRF OPERANDS     : data đọc từ VRF vào ALU
##   Group 5  ALU → WRITEBACK  : kết quả tính ra và ghi về VRF
##   Group 6  VLSU BUS         : vle32/vse32 memory transactions
##   Group 7  IO (HEX0)        : tiến trình chương trình (0→1→2→3→4→5→d)
##
## Chạy: vsim -do run_wave_full_vpu.do

transcript on

if {![file exists work]} { vlib work }

## ── Compile Scalar Core ──────────────────────────────────────────────────────
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

## ── Compile VPU ──────────────────────────────────────────────────────────────
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

## ── Compile Top + TB ─────────────────────────────────────────────────────────
vlog -sv \
    rtl/riscv_vpu_top.sv \
    bench/tb_wave_full_vpu.sv

vsim -voptargs=+acc work.tb_wave_full_vpu

## =============================================================================
## WAVEFORM SETUP
## =============================================================================

## ── Group 1: Scalar Core PC + Instruction ────────────────────────────────────
add wave -divider "━━━━━ SCALAR CORE ━━━━━"
add wave -color White   -radix hex      /tb_wave_full_vpu/pc_debug
add wave -color White   -radix hex      /tb_wave_full_vpu/dut/u_scalar_core/inst
add wave -color Gray    -radix binary   /tb_wave_full_vpu/insn_vld
add wave -color Orange  -radix binary   /tb_wave_full_vpu/dut/u_scalar_core/vpu_stall
add wave -color Cyan    -radix binary   /tb_wave_full_vpu/dut/u_scalar_core/vpu_insn_vld
add wave -color Cyan    -radix hex      /tb_wave_full_vpu/dut/u_scalar_core/vpu_insn_vld
# Scalar registers (s1..s4 = x9,x18,x19,x20 = kết quả read-back)
add wave -color Gray    -radix unsigned /tb_wave_full_vpu/dut/u_scalar_core/u_register_file/data9
add wave -color Gray    -radix unsigned /tb_wave_full_vpu/dut/u_scalar_core/u_register_file/data18

## ── Group 2: VPU Dispatch ────────────────────────────────────────────────────
add wave -divider "━━━━━ VPU DISPATCH ━━━━━"
add wave -color Yellow  -radix binary   /tb_wave_full_vpu/dut/u_scalar_core/vpu_insn_vld
add wave -color Yellow  -radix hex      /tb_wave_full_vpu/dut/u_vpu/instruction
add wave -color Yellow  -radix binary   /tb_wave_full_vpu/dut/u_vpu/vpu_ready
add wave -color Orange  -radix binary   /tb_wave_full_vpu/dut/u_vpu/fifo_full
add wave -color Orange  -radix binary   /tb_wave_full_vpu/dut/u_vpu/fifo_data_valid

## ── Group 3: FSM State ───────────────────────────────────────────────────────
add wave -divider "━━━━━ VPU FSM STATE ━━━━━"
add wave -color Yellow  -radix unsigned /tb_wave_full_vpu/vpu_fsm_state
add wave -color Yellow  -radix binary   /tb_wave_full_vpu/vpu_busy
add wave -color Orange  -radix binary   /tb_wave_full_vpu/dut/u_vpu/fsm_vrf_wren
add wave -color Orange  -radix binary   /tb_wave_full_vpu/dut/u_vpu/fsm_s_offset_en
add wave -color Orange  -radix binary   /tb_wave_full_vpu/dut/u_vpu/counter_done
add wave -color White   -radix unsigned /tb_wave_full_vpu/vpu_cycles
add wave -color White   -radix unsigned /tb_wave_full_vpu/dut/u_vpu/csr_vl_o
add wave -color White   -radix hex      /tb_wave_full_vpu/dut/u_vpu/csr_vtype_o

## ── Group 4: Decode — thanh ghi nào đang dùng ───────────────────────────────
add wave -divider "━━━━━ OPERAND ADDRESSES ━━━━━"
add wave -color Magenta -radix hex      /tb_wave_full_vpu/dut/u_vpu/funct6_r
add wave -color Magenta -radix unsigned /tb_wave_full_vpu/dut/u_vpu/cfg_sew
add wave -color Magenta -radix unsigned /tb_wave_full_vpu/dut/u_vpu/vs2_addr_eff
add wave -color Magenta -radix unsigned /tb_wave_full_vpu/dut/u_vpu/vs1_addr_eff
add wave -color Magenta -radix unsigned /tb_wave_full_vpu/dut/u_vpu/vd_addr_eff

## ── Group 5: VRF Read (operands vào ALU) ─────────────────────────────────────
add wave -divider "━━━━━ VRF READ → ALU ━━━━━"
add wave -color Green   -radix hex      /tb_wave_full_vpu/dut/u_vpu/rs2_data_lane0
add wave -color Green   -radix hex      /tb_wave_full_vpu/dut/u_vpu/rs2_data_lane1
add wave -color Green   -radix hex      /tb_wave_full_vpu/dut/u_vpu/rs2_data_lane2
add wave -color Green   -radix hex      /tb_wave_full_vpu/dut/u_vpu/rs2_data_lane3
add wave -color Cyan    -radix hex      /tb_wave_full_vpu/dut/u_vpu/rs1_data_lane0
add wave -color Cyan    -radix hex      /tb_wave_full_vpu/dut/u_vpu/rs1_data_lane1
add wave -color Cyan    -radix hex      /tb_wave_full_vpu/dut/u_vpu/rs1_data_lane2
add wave -color Cyan    -radix hex      /tb_wave_full_vpu/dut/u_vpu/rs1_data_lane3

## ── Group 6: ALU Output + VRF Writeback ──────────────────────────────────────
add wave -divider "━━━━━ ALU OUTPUT → VRF WB ━━━━━"
add wave -color Red     -radix hex      /tb_wave_full_vpu/dut/u_vpu/wb_lane0
add wave -color Red     -radix hex      /tb_wave_full_vpu/dut/u_vpu/wb_lane1
add wave -color Red     -radix hex      /tb_wave_full_vpu/dut/u_vpu/wb_lane2
add wave -color Red     -radix hex      /tb_wave_full_vpu/dut/u_vpu/wb_lane3
add wave -color Lime    -radix unsigned /tb_wave_full_vpu/dut/u_vpu/vrf_waddr_eff
add wave -color Lime    -radix hex      /tb_wave_full_vpu/dut/u_vpu/vrf_we0_eff
add wave -color Lime    -radix hex      /tb_wave_full_vpu/dut/u_vpu/vrf_wdata0_eff
add wave -color Lime    -radix hex      /tb_wave_full_vpu/dut/u_vpu/vrf_wdata1_eff
add wave -color Lime    -radix hex      /tb_wave_full_vpu/dut/u_vpu/vrf_wdata2_eff
add wave -color Lime    -radix hex      /tb_wave_full_vpu/dut/u_vpu/vrf_wdata3_eff

## ── Group 7: VLSU Memory Bus ─────────────────────────────────────────────────
add wave -divider "━━━━━ VLSU MEMORY BUS ━━━━━"
add wave -color White   -radix binary   /tb_wave_full_vpu/dut/u_vpu/vlsu_mem_req
add wave -color White   -radix binary   /tb_wave_full_vpu/dut/u_vpu/vlsu_mem_we
add wave -color White   -radix hex      /tb_wave_full_vpu/dut/u_vpu/vlsu_mem_addr
add wave -color White   -radix hex      /tb_wave_full_vpu/dut/u_vpu/vlsu_mem_wdata
add wave -color Cyan    -radix hex      /tb_wave_full_vpu/dut/u_vpu/vlsu_mem_rdata
add wave -color Yellow  -radix binary   /tb_wave_full_vpu/dut/vlsu_mem_ready
add wave -color Gray    -radix binary   /tb_wave_full_vpu/dut/u_vpu/vlsu_busy_o

## ── Group 8: IO Progress (HEX0 thay đổi theo step) ──────────────────────────
add wave -divider "━━━━━ PROGRESS (HEX0) ━━━━━"
add wave -color Cyan    -radix hex      /tb_wave_full_vpu/io_hex0
add wave -color Cyan    -radix hex      /tb_wave_full_vpu/io_hex1
add wave -color Gray    -radix hex      /tb_wave_full_vpu/io_ledr
add wave -color Gray    -radix hex      /tb_wave_full_vpu/io_ledg

## ── Run ──────────────────────────────────────────────────────────────────────
run -all
wave zoom full
