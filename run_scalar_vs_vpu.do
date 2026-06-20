# run_scalar_vs_vpu.do
# Runs scalar_axpy and scalar_bt601 on the SINGLE-CYCLE riscv_vpu_top,
# then prints comparison against known VPU simulation results.
#
# Usage: vsim -c -do run_scalar_vs_vpu.do   (from project root)
#
# Detection: PC stability — once max_pc stops advancing for 500 cycles,
# benchmark is done. Works for scalar "j done" tail-spin pattern.

transcript on

set ROOT  [file normalize [pwd]]
set SW    [file join $ROOT sw benchmarks]
set IMEM  [file join $ROOT rtl imem_from_gcc.hex]

# ──────────────────────────────────────────────────────────────────────────────
proc compile_scalar_top {} {
    global ROOT
    catch { vdel -lib work -all }
    vlib work
    vmap work work

    set rtl [file join $ROOT rtl]

    foreach f {
        d_ff.sv full_adder.sv eight_bit_adder.sv adder.sv register.sv
        decoder5to32.sv Regfile.sv register_file.sv
        mux2to1.sv mux2X1.sv mux4to1.sv mux8to1.sv mux32to1.sv
        immgen.sv mag_comparator.sv mag_comparator8.sv
        brc_comparator.sv brc.sv word_and.sv word_or.sv word_xor.sv
        barrel_shifter_32bit.sv barrel_shifter_32bit_left.sv
        alu.sv lsu.sv imem.sv control_unit.sv single_cycle.sv
    } {
        vlog -quiet -sv -work work [file join $rtl riscv $f]
    }

    foreach f {
        vproc_adder.sv vproc_mul.sv vproc_logic.sv vproc_shifter.sv
        vproc_compare.sv vproc_compare_combine.sv vproc_minmax.sv
        vproc_reduction.sv vproc_merge_unit.sv vproc_processor_lane.sv
        vproc_vregfile.sv vproc_mux_cells.sv vproc_mask_enable.sv
        vproc_mask_write_buffer.sv vproc_vcsr.sv vproc_cfg_encoder.sv
        vproc_cycle_counter.sv vproc_vrf_addr_gen.sv vproc_scalar_expand.sv
        vproc_fsm.sv vproc_fifo.sv vproc_vdecoder.sv
        vproc_vec_lsu.sv vproc_system_wrapper.sv
    } {
        vlog -quiet -sv -work work [file join $rtl $f]
    }

    vlog -quiet -sv -work work [file join $rtl riscv_vpu_top.sv]
    vlog -quiet -sv -work work [file join $ROOT bench tb_scalar_cycle_count.sv]
    puts "INFO: Compile done."
}

# ──────────────────────────────────────────────────────────────────────────────
proc run_scalar {hex_path label max_ns} {
    global IMEM ROOT

    # Swap imem hex (save original first)
    set backup [file join $ROOT rtl imem_backup.hex]
    if { ![file exists $backup] } {
        file copy $IMEM $backup
    }
    file copy -force $hex_path $IMEM
    puts "INFO: \[$label\] IMEM <- [file tail $hex_path]"

    vsim -quiet -c -voptargs=+acc work.tb_scalar_cycle_count
    run $max_ns
    quit -sim

    # Restore original imem
    file copy -force $backup $IMEM
    file delete -force $backup
}

# ──────────────────────────────────────────────────────────────────────────────
# Write testbench
set TB [file join $ROOT bench tb_scalar_cycle_count.sv]
set fh [open $TB w]
puts $fh {`timescale 1ns/1ps
module tb_scalar_cycle_count;

    logic        clk   = 1'b0;
    logic        rst_n;
    logic [31:0] pc;
    logic [31:0] ledr;

    riscv_vpu_top dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .io_sw      (32'd0),
        .io_ledr    (ledr),
        .io_ledg    (),
        .io_hex0    (), .io_hex1    (), .io_hex2    (),
        .io_hex3    (), .io_hex4    (), .io_hex5    (),
        .io_hex6    (), .io_hex7    (),
        .io_lcd     (),
        .pc_debug   (pc),
        .insn_vld   (),
        .vpu_cycles (), .vpu_vmask16 (), .vpu_fifo_full(),
        .vpu_busy   (), .vpu_fsm_state(),
        .vpu_wb_lane0(), .vpu_wb_lane1(),
        .vpu_wb_lane2(), .vpu_wb_lane3()
    );

    always #5 clk = ~clk;   // 100 MHz for faster sim

    integer      cyc;
    logic [31:0] max_pc;
    integer      stable_cnt;

    initial begin
        rst_n = 1'b0;
        repeat(10) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        cyc = 0; max_pc = 32'h0; stable_cnt = 0;

        @(posedge clk); max_pc = pc;

        forever begin
            @(posedge clk);
            cyc = cyc + 1;
            if (pc > max_pc) begin
                max_pc     = pc;
                stable_cnt = 0;
            end else begin
                stable_cnt = stable_cnt + 1;
                if (stable_cnt == 500) begin
                    $display("[BENCH] done at cycle %0d  (max_pc=0x%08X)", cyc, max_pc);
                    $finish;
                end
            end
            if (cyc % 50000 == 0)
                $display("[BENCH] ... %0d cycles  pc=0x%08X  max=0x%08X",
                         cyc, pc, max_pc);
        end
    end

    initial begin
        repeat(2100000) @(posedge clk);
        $display("[BENCH] TIMEOUT at 2100000 cycles");
        $finish;
    end
endmodule}
close $fh
puts "INFO: tb_scalar_cycle_count.sv written."

# ──────────────────────────────────────────────────────────────────────────────
compile_scalar_top

puts ""
puts "========================================================"
puts " BENCHMARK A: AXPY N=16  (Scalar, single-cycle core)"
puts "========================================================"
run_scalar [file join $SW scalar_axpy.hex]  "AXPY-scalar"   200000ns

puts ""
puts "========================================================"
puts " BENCHMARK B: BT.601 Lena 16384px  (Scalar, single-cycle)"
puts "========================================================"
run_scalar [file join $SW scalar_bt601.hex] "BT601-scalar"  20000000ns

puts ""
puts "========================================================"
puts "  VPU SIMULATION REFERENCE (confirmed, Apr 2026)"
puts "========================================================"
puts "  AXPY  N=16          VPU = 221 cycles   (results/axpy/sim_log_raw.txt)"
puts "  MatMul 4x4          VPU = 317 cycles   (results/matmul/regression_raw.txt)"
puts "  Lena 128x128 BT601  VPU = 34828 cycles (PROJECT_STATUS.md, 2026-05-02)"
puts "========================================================"

quit -f
