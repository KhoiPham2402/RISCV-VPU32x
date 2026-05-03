# Script to run testbench for vproc_processor_lane
# Usage: vsim -do "run_tb_lane.do"

# Create work directory
vlib work
vmap work work

puts "========================================"
puts "Compiling RTL modules..."
puts "========================================"
vlog -sv ../rtl/vproc_adder.sv
vlog -sv ../rtl/vproc_mul.sv
vlog -sv ../rtl/vproc_logic.sv
vlog -sv ../rtl/vproc_shifter.sv
vlog -sv ../rtl/vproc_compare.sv
vlog -sv ../rtl/vproc_processor_lane.sv

puts ""
puts "Compiling testbench..."
puts "========================================"
vlog -sv tb_vproc_lane.sv

puts ""
puts "Starting simulation..."
puts "========================================"
vsim -novopt work.tb_vproc_lane

puts ""
puts "Running testbench..."
run -all

puts ""
puts "Simulation completed!"
quit -f
