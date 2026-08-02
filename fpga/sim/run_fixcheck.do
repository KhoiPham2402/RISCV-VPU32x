# =============================================================================
# run_fixcheck.do — Directed unit checks for Issue #19 (branch signed/unsigned)
# and Issue #20 (RV32M squash). See fpga/bench/tb_fixcheck.sv.
#
# Chạy từ project root: vsim -c -do fpga/sim/run_fixcheck.do
# =============================================================================
set RTL fpga/rtl
set BENCH fpga/bench

vlib work
vmap work work

vlog -sv $RTL/pipeline/mag_comparator.sv
vlog -sv $RTL/pipeline/mag_comparator8.sv
vlog -sv $RTL/pipeline/brc_comparator.sv
vlog -sv $RTL/pipeline/mux2X1.sv
vlog -sv $RTL/pipeline/brc.sv
vlog -sv $RTL/pipeline/control_unit.sv
vlog -sv $BENCH/tb_fixcheck.sv

vsim -c work.tb_fixcheck
run -all
quit -f
