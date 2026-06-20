// =============================================================================
// tb_uart_echo.sv — UART → VPU BT.601 grayscale → UART echo verification
//
// Sends 16 real RGB pixel values to the DUT via UART, receives the 16 Y bytes
// the firmware echoes back, and compares each against the exact BT.601 formula:
//   Y = (R*77 >> 8) + (G*150 >> 8) + (B*29 >> 8)   (vmulhu.vx SEW=8)
//
// Test vectors: 16 pixels covering primary colours, neutral tones, skin, and
// edge cases (black, white, near-white).
//
// Simulation time: ~65 bytes × 10 bits × 8 cycles/bit ≈ 5200 UART cycles
// plus VPU processing — total well under 20 000 cycles.
//
// Firmware loaded: uart_echo.hex (copy of uart_echo.hex → imem.hex by .do)
// =============================================================================

module tb_uart_echo;

    // ── Baud timing (matches run_uart_echo_sim.do) ───────────────────────────
    localparam int CLK_FREQ   = 14_745_600;
    localparam int BAUD_RATE  = 115_200;
    localparam int BAUD_DIV   = CLK_FREQ / (16 * BAUD_RATE) - 1;  // 7
    localparam int BIT_CYCLES = BAUD_DIV + 1;                      // 8 clk/bit
    localparam int TIMEOUT    = 50_000;

    // ── DUT signals ──────────────────────────────────────────────────────────
    logic clk;
    logic reset;
    logic uart_rx_drv;
    logic uart_tx_obs;

    riscv_vpu_top_v4 #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .i_clk            (clk),
        .i_reset          (reset),
        .i_io_sw          (32'h0),
        .o_io_ledr        (),
        .o_io_ledg        (),
        .o_io_lcd         (),
        .o_io_hex0        (),
        .o_io_hex1        (),
        .o_io_hex2        (),
        .o_io_hex3        (),
        .o_io_hex4        (),
        .o_io_hex5        (),
        .o_io_hex6        (),
        .o_io_hex7        (),
        .o_pc_debug       (),
        .o_insn_vld       (),
        .o_vpu_cycles     (),
        .o_vmask16        (),
        .o_vpu_busy       (),
        .o_fsm_state      (),
        .o_wb_result_lane0(),
        .o_wb_result_lane1(),
        .o_wb_result_lane2(),
        .o_wb_result_lane3(),
        .uart_rx          (uart_rx_drv),
        .uart_tx          (uart_tx_obs)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ── Test vectors: 16 pixels with known RGB and expected Y ────────────────
    //  Pixel  Colour         R    G    B    Y_exp
    //  ─────────────────────────────────────────────
    //   0     Black          0    0    0    0
    //   1     White        255  255  255  253
    //   2     Red          255    0    0   76
    //   3     Green          0  255    0  149
    //   4     Blue           0    0  255   28
    //   5     50% Gray     128  128  128  127
    //   6     Yellow       255  255    0  225
    //   7     Cyan           0  255  255  177
    //   8     Magenta      255    0  255  104
    //   9     Skin tone    220  170  130  179
    //  10     Orange       255  165    0  172
    //  11     Dark gray     64   64   64   63
    //  12     Teal           0  128  128   89
    //  13     Olive        128  128    0  113
    //  14     Lavender     180  120  200  146
    //  15     Near-white   240  240  240  239

    localparam int N = 16;
    logic [7:0] R_pix [0:N-1] = '{ 8'd0,   8'd255, 8'd255, 8'd0,   8'd0,   8'd128,
                                    8'd255, 8'd0,   8'd255, 8'd220, 8'd255, 8'd64,
                                    8'd0,   8'd128, 8'd180, 8'd240 };
    logic [7:0] G_pix [0:N-1] = '{ 8'd0,   8'd255, 8'd0,   8'd255, 8'd0,   8'd128,
                                    8'd255, 8'd255, 8'd0,   8'd170, 8'd165, 8'd64,
                                    8'd128, 8'd128, 8'd120, 8'd240 };
    logic [7:0] B_pix [0:N-1] = '{ 8'd0,   8'd255, 8'd0,   8'd0,   8'd255, 8'd128,
                                    8'd0,   8'd255, 8'd255, 8'd130, 8'd0,   8'd64,
                                    8'd128, 8'd0,   8'd200, 8'd240 };

    // Reference: vmulhu.vx SEW=8  →  upper byte of 16-bit unsigned product
    function automatic logic [7:0] bt601_y(input logic [7:0] r, g, b);
        logic [15:0] yr, yg, yb;
        yr = {8'h0, r} * 16'd77;
        yg = {8'h0, g} * 16'd150;
        yb = {8'h0, b} * 16'd29;
        return yr[15:8] + yg[15:8] + yb[15:8];
    endfunction

    // ── UART tasks ────────────────────────────────────────────────────────────
    task automatic uart_send_byte(input logic [7:0] data);
        integer b;
        uart_rx_drv = 1'b0;                          // start bit
        repeat(BIT_CYCLES) @(posedge clk);
        for (b = 0; b < 8; b++) begin
            uart_rx_drv = data[b];
            repeat(BIT_CYCLES) @(posedge clk);
        end
        uart_rx_drv = 1'b1;                          // stop bit
        repeat(BIT_CYCLES) @(posedge clk);
    endtask

    task automatic uart_recv_byte(output logic [7:0] data);
        integer b;
        @(negedge uart_tx_obs);                       // wait for start bit
        repeat(BIT_CYCLES + BIT_CYCLES/2) @(posedge clk);  // mid of bit 0
        for (b = 0; b < 8; b++) begin
            data[b] = uart_tx_obs;
            repeat(BIT_CYCLES) @(posedge clk);
        end
        repeat(BIT_CYCLES/2) @(posedge clk);
    endtask

    // ── Main stimulus ─────────────────────────────────────────────────────────
    logic [7:0] y_hw  [0:N-1];
    logic [7:0] y_exp [0:N-1];
    logic [7:0] ack;
    int         n_pass, n_fail;

    initial begin
        uart_rx_drv = 1'b1;
        reset       = 1'b1;
        repeat(10) @(posedge clk);
        reset = 1'b0;
        repeat(5)  @(posedge clk);

        // ── Pre-compute expected values ──────────────────────────────────────
        for (int i = 0; i < N; i++)
            y_exp[i] = bt601_y(R_pix[i], G_pix[i], B_pix[i]);

        // ── Send R channel ────────────────────────────────────────────────────
        $display("[INFO] Sending R channel...");
        for (int i = 0; i < N; i++) uart_send_byte(R_pix[i]);

        // ── Send G channel ────────────────────────────────────────────────────
        $display("[INFO] Sending G channel...");
        for (int i = 0; i < N; i++) uart_send_byte(G_pix[i]);

        // ── Send B channel ────────────────────────────────────────────────────
        $display("[INFO] Sending B channel...");
        for (int i = 0; i < N; i++) uart_send_byte(B_pix[i]);

        $display("[INFO] All RGB data sent. Waiting for Y bytes...");

        // ── Receive 16 Y bytes ────────────────────────────────────────────────
        for (int i = 0; i < N; i++) uart_recv_byte(y_hw[i]);

        // ── Receive ACK ───────────────────────────────────────────────────────
        uart_recv_byte(ack);

        // ── Print results ─────────────────────────────────────────────────────
        $display("");
        $display("Pixel   R    G    B   Y_exp  Y_hw   Result");
        $display("──────────────────────────────────────────────────────");
        n_pass = 0;
        n_fail = 0;
        for (int i = 0; i < N; i++) begin
            if (y_hw[i] === y_exp[i]) begin
                $display("  [%2d]  %3d  %3d  %3d   %3d    %3d    PASS",
                         i, R_pix[i], G_pix[i], B_pix[i], y_exp[i], y_hw[i]);
                n_pass++;
            end else begin
                $display("  [%2d]  %3d  %3d  %3d   %3d    %3d    FAIL *** err=%0d",
                         i, R_pix[i], G_pix[i], B_pix[i], y_exp[i], y_hw[i],
                         int'(y_hw[i]) - int'(y_exp[i]));
                n_fail++;
            end
        end
        $display("──────────────────────────────────────────────────────");

        if (ack === 8'hAA)
            $display("[PASS] ACK = 0x%02X", ack);
        else
            $display("[FAIL] ACK = 0x%02X (expected 0xAA)", ack);

        $display("");
        $display("═══════════════════════════════════════════════════════");
        $display("  TEST SUMMARY: PASS=%0d / %0d  FAIL=%0d",
                 n_pass, N, n_fail + (ack !== 8'hAA ? 1 : 0));
        if (n_fail == 0 && ack === 8'hAA)
            $display("  RESULT: *** ALL PASS ***");
        else
            $display("  RESULT: *** FAIL ***");
        $display("═══════════════════════════════════════════════════════");

        $finish;
    end

    // ── Global timeout ────────────────────────────────────────────────────────
    initial begin
        repeat(TIMEOUT) @(posedge clk);
        $display("[FAIL] Timeout at %0d cycles — DUT hung", TIMEOUT);
        $display("  uart_tx=%b  vpu_busy=%b  fsm=%0d",
                 uart_tx_obs, dut.o_vpu_busy, dut.o_fsm_state);
        $finish;
    end

endmodule
