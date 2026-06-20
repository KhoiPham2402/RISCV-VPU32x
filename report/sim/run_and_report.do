# run_and_report.do — Run assertion simulation and save all output to report/sim/
#
# Tees ModelSim transcript to:
#   report/sim/sim_log.txt       — raw simulation log
#
# Usage (from project root):
#   vsim -c -do report/sim/run_and_report.do

transcript file report/sim/sim_log.txt
transcript on

source run_uart_lena_assert_sim.do
