# ModelSim: compile, run tb_vproc_fifo, dump waveform
if {[file exists work]} { vdel -all }
vlib work
vlog -sv ../rtl/vproc_fifo.sv
vlog -sv tb_vproc_fifo.sv
vsim -c work.tb_vproc_fifo -do "run -all; quit -f"
# Nếu chạy GUI: vsim work.tb_vproc_fifo -> run -all -> waveform đã dump vào tb_vproc_fifo.vcd
# Mở file sóng: File -> Open -> tb_vproc_fifo.vcd (hoặc dùng gtkwave tb_vproc_fifo.vcd)
