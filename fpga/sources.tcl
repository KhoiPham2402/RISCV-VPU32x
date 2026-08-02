# sources.tcl — Add all synthesis RTL files to Quartus project
# Run from Quartus Tcl console: source fpga/sources.tcl
# Or add to .qsf: set_global_assignment -name SOURCE_TCL_SCRIPT_FILE sources.tcl
#
# Dependency order: packages first, leaves last.

set RTL_ROOT [file dirname [file normalize [info script]]]

# ── TileLink package (must be first — used by uart + top) ────────────────────
set_global_assignment -name SYSTEMVERILOG_FILE \
    [file join $RTL_ROOT rtl bus tl_pkg.sv]

# ── Pipeline leaf cells ───────────────────────────────────────────────────────
foreach f {
    full_adder.sv eight_bit_adder.sv adder.sv
    d_ff.sv register.sv
    decoder5to32.sv Regfile.sv register_file.sv
    mux2to1.sv mux2X1.sv mux4to1.sv mux8to1.sv mux32to1.sv
    immgen.sv
    mag_comparator.sv mag_comparator8.sv brc_comparator.sv brc.sv
    word_and.sv word_or.sv word_xor.sv
    barrel_shifter_32bit.sv barrel_shifter_32bit_left.sv
    alu.sv imem_sync.sv control_unit.sv pipelined_vpu.sv
} {
    set_global_assignment -name SYSTEMVERILOG_FILE \
        [file join $RTL_ROOT rtl pipeline $f]
}

# ── UART ─────────────────────────────────────────────────────────────────────
set_global_assignment -name SYSTEMVERILOG_FILE \
    [file join $RTL_ROOT rtl uart uart.sv]

# ── VPU modules ───────────────────────────────────────────────────────────────
foreach f {
    vproc_adder.sv vproc_mul.sv vproc_logic.sv vproc_shifter.sv
    vproc_compare.sv vproc_compare_combine.sv
    vproc_minmax.sv vproc_reduction.sv vproc_merge_unit.sv
    vproc_processor_lane.sv vproc_vregfile.sv vproc_mux_cells.sv
    vproc_mask_enable.sv vproc_mask_write_buffer.sv
    vproc_vcsr.sv vproc_cfg_encoder.sv vproc_cycle_counter.sv
    vproc_vrf_addr_gen.sv vproc_scalar_expand.sv
    vproc_fsm.sv vproc_fifo.sv vproc_vdecoder.sv
    vproc_vec_lsu.sv vproc_system_wrapper.sv
} {
    set_global_assignment -name SYSTEMVERILOG_FILE \
        [file join $RTL_ROOT rtl vpu $f]
}

# ── DMEM bus arbiter (VLSU > scalar > video priority, single shared port) ─────
set_global_assignment -name SYSTEMVERILOG_FILE \
    [file join $RTL_ROOT rtl bus dmem_arbiter.sv]

# ── DMEM (M10K single-port wrapper) ───────────────────────────────────────────
set_global_assignment -name SYSTEMVERILOG_FILE \
    [file join $RTL_ROOT rtl mem dmem_qip_wrapper.sv]

# ── VGA timing (shared, lives in rtl/hdmi/) ──────────────────────────────────
set_global_assignment -name SYSTEMVERILOG_FILE \
    [file join $RTL_ROOT rtl hdmi vga_timing.sv]

# ── VGA controller (ADV7123 on DE10-Standard, no I2C) ────────────────────────
set_global_assignment -name SYSTEMVERILOG_FILE \
    [file join $RTL_ROOT rtl vga vga_ctrl.sv]

# ── Top level ─────────────────────────────────────────────────────────────────
set_global_assignment -name SYSTEMVERILOG_FILE \
    [file join $RTL_ROOT rtl top riscv_vpu_top_fpga.sv]
set_global_assignment -name SYSTEMVERILOG_FILE \
    [file join $RTL_ROOT rtl top de10_standard_top.sv]

# ── SDC timing constraints ────────────────────────────────────────────────────
set_global_assignment -name SDC_FILE \
    [file join $RTL_ROOT constraints timing.sdc]

# ── Quartus IP (.qip) — generate these in Quartus IP Catalog first ────────────
# 1. DMEM bank: 8-bit TDP altsyncram, 16384 deep, M10K, no byteena
#    Output name: dmem_bank → generates fpga/ip/dmem_bank/dmem_bank.qip
# set_global_assignment -name QIP_FILE [file join $RTL_ROOT ip dmem_bank dmem_bank.qip]
#
# 2. PLL: 50 MHz in → c0=50 MHz, c1=25 MHz (pixel clock)
#    Output name: pll → generates fpga/ip/pll/pll.qip
# set_global_assignment -name QIP_FILE [file join $RTL_ROOT ip pll pll.qip]

puts "INFO: RTL sources loaded."
puts "      Remaining manual steps:"
puts "  1. Generate dmem_bank IP  (8-bit TDP, 16384 deep, M10K) → uncomment QIP line"
puts "  2. Generate pll IP        (50→25 MHz) → uncomment QIP line"
puts "  3. Add imem_from_gcc.hex / uart_lena.hex path to imem_sync parameter"
puts "  4. Source constraints/de10_standard_pins.tcl for pin assignments"
