// =============================================================================
// tb_uart_lena_assert.sv  —  Full-system assertion testbench for lena 128×128
//
// Verifies the complete UART → firmware → VPU BT.601 → DMEM pipeline.
// Runs on riscv_vpu_top_v4 (pipelined scalar + dmem_sync TDP + UART + VPU).
//
// Assertion categories
//   [A1]  Reset: no memory access before reset releases
//   [A2]  PC watchdog: PC must advance (no infinite stall before VPU loop)
//   [A3]  UART frame: every TX byte has correct start/stop bit
//   [A4]  UART byte range: no garbage bit patterns on uart_tx
//   [A5]  DMEM write range: scalar SB only targets [0x0000–0xBFFF] (R/G/B area)
//   [A6]  DMEM hazard: Port A + B simultaneous same-word write → error (in dmem_sync)
//   [A7]  ACK: firmware sends exactly 0xAA after processing
//   [A8]  BT.601 correctness: all 16384 Y pixels match reference model
//   [A9]  Y range: no pixel value > 253 (max BT.601 for 8-bit inputs, no overflow)
//   [A10] R/G/B data integrity: DMEM[0x0000–0xBFFF] matches what was sent via UART
//   [A11] Timeout: global simulation guard
// =============================================================================

module tb_uart_lena_assert;

    // ── Baud timing ──────────────────────────────────────────────────────────
    localparam int CLK_FREQ   = 14_745_600;
    localparam int BAUD_RATE  = 115_200;
    localparam int BAUD_DIV   = CLK_FREQ / (16 * BAUD_RATE) - 1;  // 7
    localparam int BIT_CYCLES = BAUD_DIV + 1;                      // 8 clk/bit

    localparam int N_PIXELS   = 16384;              // 128×128
    localparam int TIMEOUT    = 8_000_000;          // cycles
    localparam int PC_WATCHDOG= 2000;               // max cycles with same PC
    localparam string DMEM_OUT = "sw/benchmarks/lena_gray/v3_output/lena_dmem_out_uart.hex";

    // ── DUT signals ──────────────────────────────────────────────────────────
    logic        clk;
    logic        reset;
    logic        uart_rx_drv;
    logic        uart_tx_obs;

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
        .o_pc_debug      (),
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
    always #5 clk = ~clk;

    // ── Reference pixel data ──────────────────────────────────────────────────
    // Layout in lena_dmem_init.hex: word[0..4095]=R, word[4096..8191]=G, word[8192..12287]=B
    logic [31:0] dmem_init [0:16383];

    // ── Counters and tracking ─────────────────────────────────────────────────
    int           total_pass, total_fail;
    int           pc_watchdog_ctr;
    logic [31:0]  last_pc_seen;
    int           cycles_done;
    int           uart_bytes_sent;

    // ── [A1] Reset guard: track DMEM access before reset releases ─────────────
    // Check that s_dmem_re / s_dmem_we are 0 while reset is asserted.
    logic reset_active;
    assign reset_active = reset;

    always @(posedge clk) begin
        if (reset_active) begin
            if (dut.s_dmem_re !== 1'b0 || dut.s_dmem_we !== 1'b0) begin
                $display("[FAIL][A1] DMEM access during reset at cycle %0t", $time);
                total_fail++;
            end
        end
    end

    // ── [A2] PC watchdog ──────────────────────────────────────────────────────
    // PC must change within PC_WATCHDOG cycles (except during VPU stall loops).
    // Only active after reset releases and before firmware reaches done: loop.
    logic watchdog_en;

    always @(posedge clk) begin
        if (!reset_active && watchdog_en) begin
            if (dut.o_pc_debug !== last_pc_seen) begin
                last_pc_seen      <= dut.o_pc_debug;
                pc_watchdog_ctr   <= 0;
            end else begin
                pc_watchdog_ctr <= pc_watchdog_ctr + 1;
                if (pc_watchdog_ctr == PC_WATCHDOG) begin
                    $display("[FAIL][A2] PC stuck at 0x%08x for %0d cycles",
                             last_pc_seen, PC_WATCHDOG);
                    total_fail++;
                    // Reset counter so we only fire once per stuck event
                    pc_watchdog_ctr <= 0;
                end
            end
        end
    end

    // ── [A5] DMEM scalar write range ──────────────────────────────────────────
    // Scalar SB instructions should only write to [0x0000–0xBFFF] (R/G/B input).
    // VLSU VSE8 writes to [0xC000–0xFFFF] via Port B — not visible here.
    always @(posedge clk) begin
        if (!reset_active && dut.s_dmem_we) begin
            if (dut.s_dmem_addr > 32'h0000BFFF &&
                dut.s_dmem_addr[31:8] != 24'hFF0000) begin  // exclude UART MMIO
                $display("[FAIL][A5] Scalar write outside R/G/B region: addr=0x%08x data=0x%08x",
                         dut.s_dmem_addr, dut.s_dmem_wdata);
                total_fail++;
            end
        end
    end

    // ── [A3][A4] UART TX frame checker ───────────────────────────────────────
    // Runs as a continuous background process; checks every byte transmitted.
    logic [7:0] uart_rx_captured[$];  // queue of bytes received from uart_tx

    task automatic uart_monitor_tx();
        logic [7:0] data;
        logic start_bit;
        logic stop_bit;
        int b;
        forever begin
            // Wait for start bit (falling edge on uart_tx)
            @(negedge uart_tx_obs);
            // Sample mid-first-bit
            repeat(BIT_CYCLES + BIT_CYCLES/2) @(posedge clk);
            // [A3] Start bit must be 0 — checked by negedge trigger (implicit)
            // Sample 8 data bits
            data = 8'h00;
            for (b = 0; b < 8; b++) begin
                data[b] = uart_tx_obs;
                repeat(BIT_CYCLES) @(posedge clk);
            end
            // [A3] Stop bit must be 1
            stop_bit = uart_tx_obs;
            if (stop_bit !== 1'b1) begin
                $display("[FAIL][A3] UART TX stop bit wrong: got %b, data=0x%02x", stop_bit, data);
                total_fail++;
            end else begin
                total_pass++;
            end
            // [A4] No X or Z in received data
            if (^data === 1'bx || ^data === 1'bz) begin
                $display("[FAIL][A4] UART TX data has X/Z: 0x%02x", data);
                total_fail++;
            end
            uart_rx_captured.push_back(data);
            repeat(BIT_CYCLES/2) @(posedge clk);
        end
    endtask

    // ── UART send tasks ───────────────────────────────────────────────────────
    task automatic uart_send_bit(input logic val);
        uart_rx_drv = val;
        repeat(BIT_CYCLES) @(posedge clk);
    endtask

    task automatic uart_send_byte(input logic [7:0] data);
        integer b;
        uart_send_bit(1'b0);               // start
        for (b = 0; b < 8; b++)
            uart_send_bit(data[b]);
        uart_send_bit(1'b1);               // stop
    endtask

    task automatic send_channel(input int ch_start, input string name);
        logic [7:0] px;
        $display("[INFO] Sending %s channel (%0d bytes)...", name, N_PIXELS);
        for (int i = 0; i < N_PIXELS; i++) begin
            px = dmem_init[ch_start + i/4][8*(i%4) +: 8];
            uart_send_byte(px);
            uart_bytes_sent++;
        end
        $display("[INFO] %s channel sent.", name);
    endtask

    // ── UART recv task ────────────────────────────────────────────────────────
    task automatic uart_recv_byte(output logic [7:0] data);
        integer b;
        @(negedge uart_tx_obs);
        repeat(BIT_CYCLES + BIT_CYCLES/2) @(posedge clk);
        for (b = 0; b < 8; b++) begin
            data[b] = uart_tx_obs;
            repeat(BIT_CYCLES) @(posedge clk);
        end
        repeat(BIT_CYCLES/2) @(posedge clk);
    endtask

    // ── Dump DMEM ─────────────────────────────────────────────────────────────
    task automatic dump_dmem();
        int fd;
        fd = $fopen(DMEM_OUT, "w");
        if (fd == 0) begin
            $display("[ERROR] Cannot open output file: %s", DMEM_OUT);
            return;
        end
        for (int w = 0; w < 16384; w++)
            $fwrite(fd, "%08x\n", dut.u_dmem.mem[w]);
        $fclose(fd);
        $display("[INFO] DMEM dumped to %s", DMEM_OUT);
    endtask

    // ── [A8] BT.601 reference model + [A9] Y range + [A10] RGB integrity ─────
    task automatic check_results();
        logic [7:0]  r_px, g_px, b_px;
        logic [15:0] yr, yg, yb;
        logic [7:0]  y_exp, y_act;
        int          n_ok, n_err, n_overflow;
        int          max_err_px;
        n_ok = 0; n_err = 0; n_overflow = 0; max_err_px = -1;

        $display("[INFO] Checking all %0d pixels...", N_PIXELS);

        for (int i = 0; i < N_PIXELS; i++) begin
            // Extract R/G/B from reference words
            r_px = dmem_init[       i/4][8*(i%4) +: 8];
            g_px = dmem_init[4096 + i/4][8*(i%4) +: 8];
            b_px = dmem_init[8192 + i/4][8*(i%4) +: 8];

            // [A10] R/G/B data integrity: compare DMEM vs what we sent
            if (dut.u_dmem.mem[i/4][8*(i%4) +: 8] !== r_px) begin
                if (n_err < 5)
                    $display("[FAIL][A10] R[%0d] DMEM=0x%02x, sent=0x%02x",
                             i, dut.u_dmem.mem[i/4][8*(i%4) +: 8], r_px);
                n_err++;
            end
            if (dut.u_dmem.mem[4096 + i/4][8*(i%4) +: 8] !== g_px) begin
                if (n_err < 5)
                    $display("[FAIL][A10] G[%0d] DMEM=0x%02x, sent=0x%02x",
                             i, dut.u_dmem.mem[4096+i/4][8*(i%4) +: 8], g_px);
                n_err++;
            end
            if (dut.u_dmem.mem[8192 + i/4][8*(i%4) +: 8] !== b_px) begin
                if (n_err < 5)
                    $display("[FAIL][A10] B[%0d] DMEM=0x%02x, sent=0x%02x",
                             i, dut.u_dmem.mem[8192+i/4][8*(i%4) +: 8], b_px);
                n_err++;
            end

            // BT.601 reference: vmulhu.vx SEW=8 = upper byte of 8×8 unsigned mul
            yr = {8'h0, r_px} * 16'd77;
            yg = {8'h0, g_px} * 16'd150;
            yb = {8'h0, b_px} * 16'd29;
            y_exp = yr[15:8] + yg[15:8] + yb[15:8];

            // [A9] Y overflow check (max theoretical = 76+149+28 = 253)
            if (y_exp > 8'd253) begin
                $display("[FAIL][A9] BT.601 overflow px=%0d: R=%0d G=%0d B=%0d Y_exp=%0d",
                         i, r_px, g_px, b_px, y_exp);
                n_overflow++;
            end

            // [A8] Pixel correctness
            y_act = dut.u_dmem.mem[12288 + i/4][8*(i%4) +: 8];
            if (y_act !== y_exp) begin
                total_fail++;
                if (n_err < 10)
                    $display("[FAIL][A8] px=%5d R=%3d G=%3d B=%3d  Y_exp=%3d Y_act=%3d",
                             i, r_px, g_px, b_px, y_exp, y_act);
                max_err_px = i;
            end else begin
                n_ok++;
                total_pass++;
            end
        end

        // Summary
        $display("");
        $display("── Pixel check summary ──────────────────────────────────");
        $display("  PASS: %0d / %0d", n_ok, N_PIXELS);
        $display("  FAIL: %0d / %0d (first bad px=%0d)", N_PIXELS - n_ok, N_PIXELS, max_err_px);
        if (n_overflow > 0)
            $display("  [WARN] BT.601 overflow count: %0d (check inputs)", n_overflow);
        if (n_ok == N_PIXELS)
            $display("[PASS][A8] All %0d Y pixels correct", N_PIXELS);
        else
            $display("[FAIL][A8] %0d pixel errors", N_PIXELS - n_ok);
        if (n_err == 0)
            $display("[PASS][A10] All R/G/B data received correctly");
        else
            $display("[FAIL][A10] %0d R/G/B mismatches", n_err);
    endtask

    // ── Main stimulus ─────────────────────────────────────────────────────────
    logic [7:0] ack_byte;

    initial begin
        total_pass     = 0;
        total_fail     = 0;
        cycles_done    = 0;
        uart_bytes_sent = 0;
        pc_watchdog_ctr = 0;
        last_pc_seen   = 32'hFFFFFFFF;
        watchdog_en    = 1'b0;

        $readmemh("sw/benchmarks/lena_gray/lena_dmem_init.hex", dmem_init);
        $display("[INFO] Loaded lena_dmem_init.hex");
        $display("[INFO] Sample: R[0]=%02x G[0]=%02x B[0]=%02x",
                 dmem_init[0][7:0], dmem_init[4096][7:0], dmem_init[8192][7:0]);

        uart_rx_drv = 1'b1;
        reset       = 1'b1;
        repeat(10) @(posedge clk);
        reset = 1'b0;
        repeat(5) @(posedge clk);

        // Enable PC watchdog after reset
        watchdog_en = 1'b1;

        // Fork background UART TX monitor
        fork
            uart_monitor_tx();
        join_none

        // ── Send R, G, B planes ──────────────────────────────────────────────
        send_channel(0,    "R");
        send_channel(4096, "G");
        send_channel(8192, "B");

        // Disable PC watchdog: firmware now enters `done: j done` spin loop
        // which will look like a stuck PC — that's expected
        watchdog_en = 1'b0;

        // ── [A7] Wait for ACK ────────────────────────────────────────────────
        $display("[INFO] Waiting for ACK from uart_tx...");
        uart_recv_byte(ack_byte);

        if (ack_byte === 8'hAA) begin
            $display("[PASS][A7] ACK received: 0x%02X", ack_byte);
            total_pass++;
        end else begin
            $display("[FAIL][A7] Wrong ACK: got 0x%02X, expected 0xAA", ack_byte);
            total_fail++;
        end

        // ── Wait a few cycles for VPU to fully commit ────────────────────────
        repeat(200) @(posedge clk);

        // ── [A8][A9][A10] Pixel correctness checks ────────────────────────────
        check_results();

        // ── Dump DMEM for reconstruct.py ─────────────────────────────────────
        dump_dmem();

        // ── Quick sanity print ────────────────────────────────────────────────
        $display("[INFO] Y[0..3] = %02x %02x %02x %02x",
                 dut.u_dmem.mem[12288][7:0],
                 dut.u_dmem.mem[12288][15:8],
                 dut.u_dmem.mem[12288][23:16],
                 dut.u_dmem.mem[12288][31:24]);

        // ── Final summary ─────────────────────────────────────────────────────
        $display("");
        $display("═══════════════════════════════════════════════════════");
        $display("  TEST SUMMARY:  PASS=%0d  FAIL=%0d", total_pass, total_fail);
        if (total_fail == 0)
            $display("  RESULT: *** ALL PASS *** FPGA-ready");
        else
            $display("  RESULT: *** FAIL — FIX BEFORE FPGA DEPLOY ***");
        $display("═══════════════════════════════════════════════════════");
        $display("Run: python sw/benchmarks/lena_gray/reconstruct.py %s", DMEM_OUT);

        $finish;
    end

    // ── [A11] Global timeout ──────────────────────────────────────────────────
    initial begin
        repeat(TIMEOUT) @(posedge clk);
        $display("[FAIL][A11] Global timeout at %0d cycles — system hung", TIMEOUT);
        $display("  Last PC observed: 0x%08x", dut.o_pc_debug);
        $display("  VPU busy: %b  FSM state: %0d",
                 dut.o_vpu_busy, dut.o_fsm_state);
        total_fail++;
        dump_dmem();
        $display("  TEST SUMMARY: PASS=%0d FAIL=%0d (timeout)", total_pass, total_fail);
        $finish;
    end

    // ── Continuous cycle counter ───────────────────────────────────────────────
    always @(posedge clk)
        if (!reset) cycles_done++;

endmodule
