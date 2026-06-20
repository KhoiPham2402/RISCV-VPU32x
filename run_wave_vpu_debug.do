## run_wave_vpu_debug.do
## "Embedded Engineer" waveform debug — xem VPU execution từng lệnh
##
## Cách đọc waveform:
##   - instr_label : đang chạy lệnh gì (text string)
##   - fsm_state   : 0=IDLE, 1=CONFIG, 2=EXEC, 7=REDUCTION, 8=RED_DONE
##   - busy        : 1 khi VPU đang xử lý
##   - vs1/vs2 addr: địa chỉ thanh ghi nguồn
##   - vd_addr_eff : địa chỉ thanh ghi đích
##   - rs1_data_lane* / rs2_data_lane*: dữ liệu đọc từ VRF (operands)
##   - wb_lane*    : kết quả từ ALU (trước khi ghi VRF)
##   - vrf_we*_eff : write enable — khi =4'hF là đang ghi VRF
##   - vrf_wdata*_eff: data đang được ghi vào VRF
##
## Run từ project root: vsim -do run_wave_vpu_debug.do

transcript on

if {![file exists work]} { vlib work }

## ── Compile toàn bộ VPU RTL ──────────────────────────────────────────────────
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
    rtl/vproc_system_wrapper.sv \
    bench/tb_wave_vpu_debug.sv

vsim -voptargs=+acc work.tb_wave_vpu_debug

## ── Setup waveform window ─────────────────────────────────────────────────────

## --- Group 1: Nhãn lệnh + Clock/Reset ---
add wave -divider "━━━━━ CLOCK / LABEL ━━━━━"
add wave -color Cyan -radix ascii    /tb_wave_vpu_debug/instr_label
add wave -color White -radix binary  /tb_wave_vpu_debug/clk
add wave -color White -radix binary  /tb_wave_vpu_debug/rst_n

## --- Group 2: FSM State (quan trọng nhất) ---
add wave -divider "━━━━━ FSM CONTROL ━━━━━"
add wave -color Yellow  -radix unsigned  /tb_wave_vpu_debug/fsm_state
add wave -color Yellow  -radix binary    /tb_wave_vpu_debug/busy
add wave -color Orange  -radix binary    /tb_wave_vpu_debug/vpu_ready
add wave -color Orange  -radix binary    /tb_wave_vpu_debug/dut/fsm_vrf_wren
add wave -color Orange  -radix binary    /tb_wave_vpu_debug/dut/fsm_s_offset_en
add wave -color Orange  -radix binary    /tb_wave_vpu_debug/dut/counter_done
add wave -color Orange  -radix unsigned  /tb_wave_vpu_debug/cycles

## --- Group 3: Instruction Decode (biết lệnh đang chạy) ---
add wave -divider "━━━━━ DECODE / OPERAND ADDR ━━━━━"
add wave -color Magenta -radix hex       /tb_wave_vpu_debug/dut/funct6_r
add wave -color Magenta -radix unsigned  /tb_wave_vpu_debug/dut/cfg_sew
add wave -color White   -radix unsigned  /tb_wave_vpu_debug/csr_vl_o
add wave -color Magenta -radix unsigned  /tb_wave_vpu_debug/dut/vs2_addr_eff
add wave -color Magenta -radix unsigned  /tb_wave_vpu_debug/dut/vs1_addr_eff
add wave -color Magenta -radix unsigned  /tb_wave_vpu_debug/dut/vd_addr_eff
add wave -color Gray    -radix binary    /tb_wave_vpu_debug/dut/use_rs1_r
add wave -color Gray    -radix binary    /tb_wave_vpu_debug/dut/use_imm_r

## --- Group 4: Operand Data đọc từ VRF ---
add wave -divider "━━━━━ VRF READ (OPERANDS) ━━━━━"
add wave -color Green   -radix hex       /tb_wave_vpu_debug/dut/rs2_data_lane0
add wave -color Green   -radix hex       /tb_wave_vpu_debug/dut/rs2_data_lane1
add wave -color Green   -radix hex       /tb_wave_vpu_debug/dut/rs2_data_lane2
add wave -color Green   -radix hex       /tb_wave_vpu_debug/dut/rs2_data_lane3
add wave -color Cyan    -radix hex       /tb_wave_vpu_debug/dut/rs1_data_lane0
add wave -color Cyan    -radix hex       /tb_wave_vpu_debug/dut/rs1_data_lane1
add wave -color Cyan    -radix hex       /tb_wave_vpu_debug/dut/rs1_data_lane2
add wave -color Cyan    -radix hex       /tb_wave_vpu_debug/dut/rs1_data_lane3

## --- Group 5: ALU Output (trước khi ghi VRF) ---
add wave -divider "━━━━━ ALU OUTPUT (wb_lane) ━━━━━"
add wave -color Red     -radix hex       /tb_wave_vpu_debug/dut/wb_lane0
add wave -color Red     -radix hex       /tb_wave_vpu_debug/dut/wb_lane1
add wave -color Red     -radix hex       /tb_wave_vpu_debug/dut/wb_lane2
add wave -color Red     -radix hex       /tb_wave_vpu_debug/dut/wb_lane3

## --- Group 6: VRF Write Path (QUAN TRỌNG — kết quả thực sự ghi vào VRF) ---
add wave -divider "━━━━━ VRF WRITE (ACTUAL WRITEBACK) ━━━━━"
add wave -color Yellow  -radix unsigned  /tb_wave_vpu_debug/dut/vrf_waddr_eff
add wave -color Yellow  -radix hex       /tb_wave_vpu_debug/dut/vrf_we0_eff
add wave -color Yellow  -radix hex       /tb_wave_vpu_debug/dut/vrf_we1_eff
add wave -color Yellow  -radix hex       /tb_wave_vpu_debug/dut/vrf_we2_eff
add wave -color Yellow  -radix hex       /tb_wave_vpu_debug/dut/vrf_we3_eff
add wave -color Lime    -radix hex       /tb_wave_vpu_debug/dut/vrf_wdata0_eff
add wave -color Lime    -radix hex       /tb_wave_vpu_debug/dut/vrf_wdata1_eff
add wave -color Lime    -radix hex       /tb_wave_vpu_debug/dut/vrf_wdata2_eff
add wave -color Lime    -radix hex       /tb_wave_vpu_debug/dut/vrf_wdata3_eff

## --- Group 7: Output cấp độ cao (visible từ top) ---
add wave -divider "━━━━━ TOP-LEVEL OUTPUTS ━━━━━"
add wave -color White   -radix hex       /tb_wave_vpu_debug/wb_result_lane0
add wave -color White   -radix hex       /tb_wave_vpu_debug/wb_result_lane1
add wave -color White   -radix hex       /tb_wave_vpu_debug/wb_result_lane2
add wave -color White   -radix hex       /tb_wave_vpu_debug/wb_result_lane3
add wave -color Gray    -radix binary    /tb_wave_vpu_debug/fifo_full
add wave -color Gray    -radix hex       /tb_wave_vpu_debug/vmask16

## --- Group 8: CSR state ---
add wave -divider "━━━━━ CSR / CONFIG ━━━━━"
add wave -color Cyan    -radix unsigned  /tb_wave_vpu_debug/csr_vl_o
add wave -color Cyan    -radix hex       /tb_wave_vpu_debug/csr_vtype_o

## ── Run simulation ────────────────────────────────────────────────────────────
run -all

## Zoom về phần EXEC (bỏ qua reset ở đầu)
wave zoom full
