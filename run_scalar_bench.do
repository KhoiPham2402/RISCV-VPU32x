# run_scalar_bench.do
# Runs scalar_bt601.S and scalar_axpy.S on the 5-stage pipelined core,
# measures cycle counts, prints comparison vs VPU.
#
# Usage: vsim -c -do run_scalar_bench.do

transcript on
set ROOT  [file normalize [pwd]]
set FPGA  [file join $ROOT fpga]
set BENCH [file join $ROOT bench]
set SW    [file join $ROOT sw benchmarks]

proc run_bench {hex_src label run_ns} {
    global FPGA ROOT

    # Point IMEM behavioral model at this firmware
    file copy -force $hex_src [file join $FPGA uart_lena.hex]
    puts "INFO: \[$label\] IMEM = [file tail $hex_src]"

    # Reload and re-simulate
    catch {vdel -lib work -all}
    vlib work
    vmap work work

    foreach f {tl_pkg.sv} {
        vlog -quiet -sv -work work [file join $FPGA rtl bus $f]
    }
    foreach f {pll.sv dmem_bank.sv dmem_bank_b0.sv dmem_bank_b1.sv
               dmem_bank_b2.sv dmem_bank_b3.sv
               imem_b0.sv imem_b1.sv imem_b2.sv imem_b3.sv} {
        vlog -quiet -sv -work work [file join $FPGA ip $f]
    }
    foreach f {full_adder.sv eight_bit_adder.sv adder.sv d_ff.sv register.sv
               decoder5to32.sv Regfile.sv register_file.sv
               mux2to1.sv mux2X1.sv mux4to1.sv mux8to1.sv mux32to1.sv
               immgen.sv mag_comparator.sv mag_comparator8.sv
               brc_comparator.sv brc.sv word_and.sv word_or.sv word_xor.sv
               barrel_shifter_32bit.sv barrel_shifter_32bit_left.sv
               alu.sv imem_sync.sv control_unit.sv pipelined_vpu.sv} {
        vlog -quiet -sv -work work [file join $FPGA rtl pipeline $f]
    }
    vlog -quiet -sv -work work [file join $FPGA rtl uart uart.sv]
    foreach f {vproc_adder.sv vproc_mul.sv vproc_logic.sv vproc_shifter.sv
               vproc_compare.sv vproc_compare_combine.sv vproc_minmax.sv
               vproc_reduction.sv vproc_merge_unit.sv vproc_processor_lane.sv
               vproc_vregfile.sv vproc_mux_cells.sv vproc_mask_enable.sv
               vproc_mask_write_buffer.sv vproc_vcsr.sv vproc_cfg_encoder.sv
               vproc_cycle_counter.sv vproc_vrf_addr_gen.sv vproc_scalar_expand.sv
               vproc_fsm.sv vproc_fifo.sv vproc_vdecoder.sv
               vproc_vec_lsu.sv vproc_system_wrapper.sv} {
        vlog -quiet -sv -work work [file join $FPGA rtl vpu $f]
    }
    vlog -quiet -sv -work work [file join $FPGA rtl bus dmem_arbiter.sv]
    vlog -quiet -sv -work work [file join $FPGA rtl mem dmem_qip_wrapper.sv]
    vlog -quiet -sv -work work [file join $FPGA rtl hdmi vga_timing.sv]
    vlog -quiet -sv -work work [file join $FPGA rtl vga vga_ctrl.sv]
    vlog -quiet -sv -work work [file join $FPGA rtl top riscv_vpu_top_fpga.sv]
    vlog -quiet -sv -work work [file join $ROOT bench tb_scalar_bench.sv]

    vsim -quiet -c -voptargs=+acc work.tb_scalar_bench
    run $run_ns
    quit -sim
}

# Create a simple testbench on-the-fly
set TB [file join $ROOT bench tb_scalar_bench.sv]
set fh [open $TB w]
puts $fh {`timescale 1ns/1ps
module tb_scalar_bench;
    logic clk = 1'b0;
    logic reset;
    logic [31:0] pc;

    riscv_vpu_top_fpga #(.UART_CLK_FREQ(50_000_000),.UART_BAUD_RATE(115200)) dut (
        .i_clk(clk), .i_reset(reset),
        .i_io_sw(32'd0), .uart_rx(1'b1), .uart_tx(),
        .o_io_ledr(), .o_io_ledg(), .o_io_lcd(),
        .o_io_hex0(),.o_io_hex1(),.o_io_hex2(),.o_io_hex3(),.o_io_hex4(),.o_io_hex5(),
        .o_io_hex6(),.o_io_hex7(),
        .vga_r(),.vga_g(),.vga_b(),.vga_clk(),.vga_hs(),.vga_vs(),
        .vga_blank_n(),.vga_sync_n(),
        .o_pc_debug(pc),.o_insn_vld(),.o_vpu_cycles(),.o_vmask16(),
        .o_vpu_busy(),.o_fsm_state(),
        .o_wb_result_lane0(),.o_wb_result_lane1(),
        .o_wb_result_lane2(),.o_wb_result_lane3()
    );
    always #10 clk = ~clk;

    integer cycle_start, cycle_end, cycle_prev;
    integer done_count;
    initial begin
        reset = 1; repeat(50) @(posedge clk); reset = 0;
        $display("[TB] Reset released at %0t ns", $time);
        cycle_start = 0; cycle_end = 0; cycle_prev = -1; done_count = 0;
        // Wait until PC stops changing (j done loop)
        repeat(3) @(posedge clk);
        cycle_start = 0;
        @(posedge clk); cycle_start = $time/20 - 50; // cycles after reset
        forever begin
            @(posedge clk);
            if (pc === cycle_prev) begin
                done_count = done_count + 1;
                if (done_count == 5) begin
                    cycle_end = $time/20 - 50;
                    $display("[RESULT] PC stuck at 0x%08X — done detected", pc);
                    $display("[CYCLES] Total = %0d cycles (from reset release)", cycle_end);
                    $finish;
                end
            end else begin
                done_count = 0;
            end
            cycle_prev = pc;
        end
    end
    initial begin #200000000; $display("[TIMEOUT] No done detected"); $finish; end
endmodule}
close $fh
puts "INFO: tb_scalar_bench.sv written"

# ── Run BT.601 scalar ─────────────────────────────────────────────────────────
puts ""
puts "========================================"
puts " BENCHMARK 1: BT.601 Lena 16384 px SCALAR"
puts "========================================"
run_bench [file join $SW scalar_bt601.hex] "BT601-scalar" 20000000ns

# ── Run AXPY scalar ───────────────────────────────────────────────────────────
puts ""
puts "========================================"
puts " BENCHMARK 2: AXPY N=16 SCALAR"
puts "========================================"
run_bench [file join $SW scalar_axpy.hex] "AXPY-scalar" 2000000ns

puts ""
puts "========================================"
puts " COMPARISON SUMMARY"
puts "========================================"
puts "  BT.601 Lena 16384px:  VPU=35853   Scalar=see above"
puts "  AXPY N=16:            VPU=221     Scalar=see above"
puts "  MatMul 4x4:           VPU=317     Scalar=analytical"
puts "========================================"

quit -f
