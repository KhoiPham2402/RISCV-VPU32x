// =============================================================================
// de10_standard_top.sv  —  Board-level wrapper for DE10-Standard (Cyclone V)
//
// Maps DE10-Standard physical port names to riscv_vpu_top_fpga.
// Handles signal polarity mismatches and absent board peripherals:
//   • KEY[0] is active-low  → invert to active-high i_reset
//   • SW[9:0] board         → zero-pad to i_io_sw[31:0]
//   • LEDR[9:0] board       → lower 10 bits of o_io_ledr[31:0]
//   • HEX0–HEX5 only        → HEX6/HEX7 ports tied off internally
//   • No LEDG / LCD pins    → those ports left unconnected
//   • VGA via ADV7123 DAC   → no I2C required, just wire RGB + sync
// =============================================================================

module de10_standard_top (
    // ── Clock ─────────────────────────────────────────────────────────────────
    input  logic        CLOCK_50,

    // ── Push-buttons (active-low) ─────────────────────────────────────────────
    input  logic [1:0]  KEY,

    // ── Slide switches ────────────────────────────────────────────────────────
    input  logic [9:0]  SW,

    // ── Red LEDs (active-high) ────────────────────────────────────────────────
    output logic [9:0]  LEDR,

    // ── 7-Segment displays (active-low, segments a–g = bits [0]–[6]) ─────────
    output logic [6:0]  HEX0,
    output logic [6:0]  HEX1,
    output logic [6:0]  HEX2,
    output logic [6:0]  HEX3,
    output logic [6:0]  HEX4,
    output logic [6:0]  HEX5,

    // ── GPIO_0 (JP1) — bit[0]=UART_RX, bit[1]=UART_TX ───────────────────────
    input  logic        GPIO_0_RX,   // JP1 pin 3  (GPIO_0[0], FPGA PIN_W15)
    output logic        GPIO_0_TX,   // JP1 pin 4  (GPIO_0[1], FPGA PIN_AK2)

    // ── VGA (ADV7123 DAC, no I2C required) ───────────────────────────────────
    output logic [7:0]  VGA_R,
    output logic [7:0]  VGA_G,
    output logic [7:0]  VGA_B,
    output logic        VGA_CLK,
    output logic        VGA_HS,
    output logic        VGA_VS,
    output logic        VGA_BLANK_N,
    output logic        VGA_SYNC_N
);

    // ── Tie-off wires for absent board peripherals ────────────────────────────
    logic [31:0] ledr_32, ledg_32, lcd_32;
    logic [6:0]  hex6_nc, hex7_nc;

    // Debug LED overlay (firmware uses ledr_32[7:0]; we overlay status on [9:8])
    // LEDR[9] = VPU busy (blinks during computation)
    // LEDR[8] = VPU FSM not idle (ST_EXEC / ST_REDUCTION / etc.)
    logic        dbg_vpu_busy;
    logic [3:0]  dbg_fsm_state;
    assign LEDR = {dbg_vpu_busy, (dbg_fsm_state != 4'd0), ledr_32[7:0]};

    // ── Core instantiation ────────────────────────────────────────────────────
    riscv_vpu_top_fpga u_core (
        .i_clk           (CLOCK_50),
        .i_reset         (~KEY[0]),          // KEY[0]=0 pressed → active-high reset

        // Switches: zero-pad SW[9:0] to 32-bit port
        .i_io_sw         ({22'd0, SW}),

        // UART via GPIO_0 (JP1)
        .uart_rx         (GPIO_0_RX),
        .uart_tx         (GPIO_0_TX),

        // VGA
        .vga_r           (VGA_R),
        .vga_g           (VGA_G),
        .vga_b           (VGA_B),
        .vga_clk         (VGA_CLK),
        .vga_hs          (VGA_HS),
        .vga_vs          (VGA_VS),
        .vga_blank_n     (VGA_BLANK_N),
        .vga_sync_n      (VGA_SYNC_N),

        // LEDs / HEX
        .o_io_ledr       (ledr_32),
        .o_io_ledg       (ledg_32),          // DE10-Standard has no green LEDs
        .o_io_lcd        (lcd_32),           // DE10-Standard has no LCD port
        .o_io_hex0       (HEX0),
        .o_io_hex1       (HEX1),
        .o_io_hex2       (HEX2),
        .o_io_hex3       (HEX3),
        .o_io_hex4       (HEX4),
        .o_io_hex5       (HEX5),
        .o_io_hex6       (hex6_nc),          // HEX6/HEX7 don't exist on DE10-Standard
        .o_io_hex7       (hex7_nc),

        // Debug observe — VPU status wired to overlay LEDs
        .o_pc_debug      (),
        .o_insn_vld      (),
        .o_vpu_cycles    (),
        .o_vmask16       (),
        .o_vpu_busy      (dbg_vpu_busy),
        .o_fsm_state     (dbg_fsm_state),
        .o_wb_result_lane0(),
        .o_wb_result_lane1(),
        .o_wb_result_lane2(),
        .o_wb_result_lane3()
    );

endmodule
