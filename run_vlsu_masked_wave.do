transcript on
if {![file exists work]} { vlib work }

vlog -sv \
    rtl/vproc_adder.sv rtl/vproc_mul.sv rtl/vproc_logic.sv \
    rtl/vproc_shifter.sv rtl/vproc_compare.sv rtl/vproc_minmax.sv \
    rtl/vproc_reduction.sv rtl/vproc_processor_lane.sv \
    rtl/vproc_vregfile.sv rtl/vproc_mux_cells.sv \
    rtl/vproc_mask_enable.sv rtl/vproc_mask_write_buffer.sv \
    rtl/vproc_merge_unit.sv rtl/vproc_scalar_expand.sv \
    rtl/vproc_vcsr.sv rtl/vproc_cfg_encoder.sv \
    rtl/vproc_cycle_counter.sv rtl/vproc_vrf_addr_gen.sv \
    rtl/vproc_fsm.sv rtl/vproc_fifo.sv rtl/vproc_vdecoder.sv \
    rtl/vproc_vec_lsu.sv rtl/vproc_system_wrapper.sv \
    rtl/vproc_compare_combine.sv \
    bench/tb_vlsu_masked_store_wave.sv

vsim -voptargs=+acc work.tb_vlsu_masked_store_wave

# ── Wave window setup ─────────────────────────────────────────────────────────
add wave -divider "--- Clock / Reset ---"
add wave -color Gold        /tb_vlsu_masked_store_wave/clk
add wave -color Gold        /tb_vlsu_masked_store_wave/rst_n

add wave -divider "--- VLSU Activity ---"
add wave -color Cyan        /tb_vlsu_masked_store_wave/vlsu_busy_o
add wave -color White  -radix unsigned /tb_vlsu_masked_store_wave/dut/vlsu_inst/state_r

add wave -divider "--- Memory Bus ---"
add wave -color Lime        /tb_vlsu_masked_store_wave/vlsu_mem_req
add wave -color Lime        /tb_vlsu_masked_store_wave/vlsu_mem_we
add wave -color Yellow -radix hexadecimal /tb_vlsu_masked_store_wave/vlsu_mem_addr
add wave -color Orange -radix binary      /tb_vlsu_masked_store_wave/vlsu_mem_be
add wave -color White  -radix hexadecimal /tb_vlsu_masked_store_wave/vlsu_mem_wdata

add wave -divider "--- Word Counter (internal) ---"
add wave -color Cyan   -radix unsigned    /tb_vlsu_masked_store_wave/dut/vlsu_inst/word_ctr_r

add wave -divider "--- v0 mask flat (bits 15:0) ---"
add wave -color Magenta -radix binary     /tb_vlsu_masked_store_wave/dut/v0_mask_flat

configure wave -namecolwidth 280
configure wave -valuecolwidth 120
configure wave -timelineunits ns

run -all
wave zoom full
