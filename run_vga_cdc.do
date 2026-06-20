# run_vga_cdc.do — VGA CDC smoke test (sclk=40MHz, pclk=25MHz)
#
# Tests whether the registered-output fix in vga_ctrl resolves the white-screen
# bug without running the full scalar+VPU pipeline.
#
# Usage (from project root):
#   vsim -do run_vga_cdc.do
#
# Expected output:
#   [PASS] VGA CDC OK : N pixels correct (R=G=B=0x89)
#   → White-screen bug is NOT in VGA path.
#   → Root cause is in VPU computation (run vproc_all_instr.do).
# ─ OR ─
#   [FAIL] VGA CDC BAD : ...
#   → CDC fix did NOT work.

quietly set SRC_ROOT "C:/CapstoneProject2/riscv_vpu"

# ── Compile ───────────────────────────────────────────────────────────────────
vlib work
vmap work work

# VGA RTL
vlog -sv "$SRC_ROOT/fpga/rtl/hdmi/vga_timing.sv"
vlog -sv "$SRC_ROOT/fpga/rtl/vga/vga_ctrl.sv"

# Testbench
vlog -sv "$SRC_ROOT/bench/tb_vga_cdc.sv"

# ── Simulate ──────────────────────────────────────────────────────────────────
vsim -novopt -t 1ps work.tb_vga_cdc

# Useful waveform groups (optional — comment out for batch mode)
# add wave -divider "Clocks"
# add wave sim:/tb_vga_cdc/sclk
# add wave sim:/tb_vga_cdc/pclk
# add wave sim:/tb_vga_cdc/rst_n
# add wave -divider "DMEM side"
# add wave sim:/tb_vga_cdc/vid_addr
# add wave sim:/tb_vga_cdc/vid_re
# add wave -hex sim:/tb_vga_cdc/vid_rdata_i
# add wave -divider "VGA outputs"
# add wave sim:/tb_vga_cdc/vga_blank_n
# add wave -hex sim:/tb_vga_cdc/vga_r
# add wave -hex sim:/tb_vga_cdc/vga_g
# add wave -hex sim:/tb_vga_cdc/vga_b

run -all
quit -f
