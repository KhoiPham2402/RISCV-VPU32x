# =============================================================================
# run_dmem_arbiter.do — directed unit checks for fpga/rtl/bus/dmem_arbiter.sv
# See fpga/bench/tb_dmem_arbiter.sv.
#
# Chạy từ project root: vsim -c -do fpga/sim/run_dmem_arbiter.do
# =============================================================================
vlib work
vmap work work

vlog -sv fpga/rtl/bus/dmem_arbiter.sv
vlog -sv fpga/bench/dmem_model_sp.sv
vlog -sv fpga/bench/tb_dmem_arbiter.sv

vsim -c work.tb_dmem_arbiter
run -all
quit -f
