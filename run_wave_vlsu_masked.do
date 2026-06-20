## run_wave_vlsu_masked.do — VLSU masked VSE8 waveform
## Shows mem_be bits zeroed for inactive mask elements
##
## Run: vsim -do run_wave_vlsu_masked.do

transcript on

if {![file exists work]} { vlib work }

vlog -sv \
    rtl/vproc_adder.sv rtl/vproc_mul.sv rtl/vproc_logic.sv \
    rtl/vproc_shifter.sv rtl/vproc_compare.sv \
    rtl/vproc_compare_combine.sv rtl/vproc_minmax.sv \
    rtl/vproc_reduction.sv rtl/vproc_merge_unit.sv \
    rtl/vproc_processor_lane.sv rtl/vproc_vregfile.sv \
    rtl/vproc_mux_cells.sv rtl/vproc_mask_enable.sv \
    rtl/vproc_mask_write_buffer.sv \
    rtl/vproc_vcsr.sv rtl/vproc_cfg_encoder.sv \
    rtl/vproc_cycle_counter.sv rtl/vproc_vrf_addr_gen.sv \
    rtl/vproc_scalar_expand.sv \
    rtl/vproc_fsm.sv rtl/vproc_fifo.sv rtl/vproc_vdecoder.sv \
    rtl/vproc_vec_lsu.sv rtl/vproc_system_wrapper.sv \
    bench/tb_vproc_vlsu.sv

vsim -voptargs=+acc work.tb_vproc_vlsu

# ── Clock & Reset ────────────────────────────────────────────────────────────
add wave -divider "━━━ CLOCK / RESET ━━━"
add wave -radix binary   /tb_vproc_vlsu/clk
add wave -radix binary   /tb_vproc_vlsu/rst_n

# ── VLSU Start Pulse & Config ─────────────────────────────────────────────
add wave -divider "━━━ VLSU ISSUE ━━━"
add wave -radix binary   /tb_vproc_vlsu/dut/vlsu_inst/vls_valid
add wave -radix binary   /tb_vproc_vlsu/dut/vlsu_inst/vm_i
add wave -radix hex      /tb_vproc_vlsu/dut/vlsu_inst/v0_flat_i
add wave -radix unsigned /tb_vproc_vlsu/dut/vlsu_inst/vl_i

# ── VLSU Internal State ──────────────────────────────────────────────────
add wave -divider "━━━ VLSU STATE ━━━"
add wave -radix ascii    /tb_vproc_vlsu/dut/vlsu_inst/state_r
add wave -radix unsigned /tb_vproc_vlsu/dut/vlsu_inst/word_ctr_r
add wave -radix binary   /tb_vproc_vlsu/dut/vlsu_inst/vm_r

# ── Memory Bus ───────────────────────────────────────────────────────────
add wave -divider "━━━ MEMORY BUS ━━━"
add wave -radix binary   /tb_vproc_vlsu/dut/vlsu_inst/mem_req
add wave -radix binary   /tb_vproc_vlsu/dut/vlsu_inst/mem_we
add wave -radix hex      /tb_vproc_vlsu/dut/vlsu_inst/mem_addr
add wave -radix binary   /tb_vproc_vlsu/dut/vlsu_inst/mem_be
add wave -radix hex      /tb_vproc_vlsu/dut/vlsu_inst/mem_wdata

# ── Mask Byte Enable ─────────────────────────────────────────────────────
add wave -divider "━━━ MASK BE ━━━"
add wave -radix binary   /tb_vproc_vlsu/dut/vlsu_inst/mask_be

# ── Done ─────────────────────────────────────────────────────────────────
add wave -divider "━━━ DONE ━━━"
add wave -radix binary   /tb_vproc_vlsu/dut/vlsu_inst/done

run -all
