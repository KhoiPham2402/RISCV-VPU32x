// =============================================================================
// tb_uart_lena.sv  —  Simulation testbench for UART → VPU grayscale firmware
//
// Tests uart_lena_test.S:
//   1. Send 48 bytes (16R + 16G + 16B) via uart_rx, test pattern R=G=B=128.
//   2. Wait for firmware ACK byte 0xAA on uart_tx.
//   3. Check DMEM Y output: all 16 bytes should be 127 (0x7F).
//
// Timing: CLK_FREQ=14_745_600, BAUD_RATE=115_200 → baud_div=7 → 8 clk/bit.
// Each UART byte = 10 bits × 8 cycles = 80 clock cycles.
// =============================================================================

module tb_uart_lena;

    localparam int CLK_FREQ   = 14_745_600;
    localparam int BAUD_RATE  = 115_200;
    localparam int BAUD_DIV   = CLK_FREQ / (16 * BAUD_RATE) - 1; // = 7
    localparam int BIT_CYCLES = BAUD_DIV + 1;                     // = 8 clk/bit
    localparam int TIMEOUT    = 200_000;

    // ── Test pattern ─────────────────────────────────────────────────────────
    // R=G=B=128 → Y = floor(128*77/256)+floor(128*150/256)+floor(128*29/256)
    //               = 38 + 75 + 14 = 127
    localparam logic [7:0] TEST_PIXEL = 8'd128;
    localparam logic [7:0] EXPECTED_Y = 8'd127;
    localparam logic [7:0] ACK_BYTE   = 8'hAA;

    // ── DUT signals ──────────────────────────────────────────────────────────
    logic        clk;
    logic        reset;
    logic        uart_rx_drv;
    logic        uart_tx_obs;
    logic [31:0] pc_debug;

    riscv_vpu_top_v4 #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .i_clk           (clk),
        .i_reset         (reset),
        .i_io_sw         (32'h0),
        .o_io_ledr       (),
        .o_io_ledg       (),
        .o_io_lcd        (),
        .o_io_hex0       (),
        .o_io_hex1       (),
        .o_io_hex2       (),
        .o_io_hex3       (),
        .o_io_hex4       (),
        .o_io_hex5       (),
        .o_io_hex6       (),
        .o_io_hex7       (),
        .o_pc_debug      (pc_debug),
        .o_insn_vld      (),
        .o_vpu_cycles    (),
        .o_vmask16       (),
        .o_vpu_busy      (),
        .o_fsm_state     (),
        .o_wb_result_lane0(),
        .o_wb_result_lane1(),
        .o_wb_result_lane2(),
        .o_wb_result_lane3(),
        .uart_rx         (uart_rx_drv),
        .uart_tx         (uart_tx_obs)
    );

    // ── Clock ─────────────────────────────────────────────────────────────────
    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz wallclock; baud timing is cycle-counted

    // ── UART send task (drives uart_rx) ───────────────────────────────────────
    // Bit period = BIT_CYCLES clock edges.  Drive after posedge so the
    // synchronizer inside UART sees the new value at the next posedge.
    task automatic uart_send_bit(input logic val);
        uart_rx_drv = val;
        repeat(BIT_CYCLES) @(posedge clk);
    endtask

    task automatic uart_send_byte(input logic [7:0] data);
        integer b;
        uart_send_bit(1'b0);             // start bit
        for (b = 0; b < 8; b++)
            uart_send_bit(data[b]);      // data bits, LSB first
        uart_send_bit(1'b1);             // stop bit
    endtask

    // ── UART receive task (samples uart_tx) ───────────────────────────────────
    // Waits for start bit then samples at each bit center.
    task automatic uart_recv_byte(output logic [7:0] data);
        integer b;
        @(negedge uart_tx_obs);
        // Skip to center of first data bit: 1.5 bit-periods from start-bit edge
        repeat(BIT_CYCLES + BIT_CYCLES/2) @(posedge clk);
        for (b = 0; b < 8; b++) begin
            data[b] = uart_tx_obs;
            repeat(BIT_CYCLES) @(posedge clk);
        end
        // Consume stop bit
        repeat(BIT_CYCLES/2) @(posedge clk);
    endtask

    // ── Check helpers ─────────────────────────────────────────────────────────
    int pass_count = 0;
    int fail_count = 0;

    task automatic check_byte(
        input string    label,
        input logic [7:0] got,
        input logic [7:0] expected
    );
        if (got === expected) begin
            pass_count++;
        end else begin
            $display("[FAIL] %s: got=0x%02X expected=0x%02X", label, got, expected);
            fail_count++;
        end
    endtask

    // ── Main stimulus ─────────────────────────────────────────────────────────
    logic [7:0] rx_byte;

    initial begin
        uart_rx_drv = 1'b1;   // idle line
        reset       = 1'b1;
        repeat(10) @(posedge clk);
        reset = 1'b0;
        repeat(5)  @(posedge clk);

        // ── Send R channel (16 bytes × TEST_PIXEL) ──────────────────────────
        $display("[INFO] Sending R channel (16 bytes = 0x%02X)...", TEST_PIXEL);
        for (int i = 0; i < 16; i++)
            uart_send_byte(TEST_PIXEL);

        // ── Send G channel ───────────────────────────────────────────────────
        $display("[INFO] Sending G channel...");
        for (int i = 0; i < 16; i++)
            uart_send_byte(TEST_PIXEL);

        // ── Send B channel ───────────────────────────────────────────────────
        $display("[INFO] Sending B channel...");
        for (int i = 0; i < 16; i++)
            uart_send_byte(TEST_PIXEL);

        // ── Wait for ACK on uart_tx ──────────────────────────────────────────
        // Global watchdog (below) terminates simulation on timeout.
        $display("[INFO] Waiting for ACK...");
        uart_recv_byte(rx_byte);

        check_byte("ACK byte", rx_byte, ACK_BYTE);

        // ── Verify DMEM Y output ──────────────────────────────────────────────
        // uart_lena_test stores Y at byte 0x030 = word index 12 (for 4 words).
        // dmem_sync is 32-bit words little-endian.
        $display("[INFO] Checking DMEM Y output...");
        begin
            logic [31:0] w32;
            for (int w = 0; w < 4; w++) begin
                w32 = dut.u_dmem.mem[12 + w];
                for (int b = 0; b < 4; b++)
                    check_byte($sformatf("Y[%0d]", w*4+b), w32[8*b +: 8], EXPECTED_Y);
            end
        end

        // ── Summary ──────────────────────────────────────────────────────────
        $display("");
        $display("TEST SUMMARY: %0d PASS  %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("[PASS] UART → VPU grayscale test PASSED");
        else
            $display("[FAIL] %0d checks failed", fail_count);

        $finish;
    end

    // ── Cycle watchdog ────────────────────────────────────────────────────────
    initial begin
        repeat(TIMEOUT + 10000) @(posedge clk);
        $display("[FAIL] Global simulation timeout");
        $finish;
    end

endmodule
