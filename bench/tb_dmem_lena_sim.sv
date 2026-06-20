`timescale 1ns/1ps
// tb_dmem_lena_sim.sv — End-to-end sim: DMEM pre-init + VPU BT.601 + Y check
//
// Flow:
//   1. Pre-load DMEM with Lena RGB at time 0.
//   2. Reset for 100 cycles, release.
//   3. Run 80000 cycles (gives VPU > 1024 iterations × ~50 cycles headroom).
//   4. Wait for VPU busy=0 (all writes committed), then check Y output.
//   5. Compare all 4096 words vs lena_y_reference.hex.
//
// Hierarchy: dut.u_dmem.bank{0-3}.u.mem[]  (see dmem_qip_wrapper.sv)

module tb_dmem_lena_sim;

    localparam int CLK_HALF  = 10;      // 50 MHz (10 ns half-period)
    localparam int RST_CYCS  = 100;
    localparam int RUN_CYCS  = 80_000;  // >> 1024 iters × max VPU latency

    // ── DUT ──────────────────────────────────────────────────────────────────
    logic        clk = 1'b0;
    logic        reset;
    logic        vpu_busy;

    riscv_vpu_top_fpga #(
        .UART_CLK_FREQ (50_000_000),
        .UART_BAUD_RATE(115_200)
    ) dut (
        .i_clk            (clk),
        .i_reset          (reset),
        .i_io_sw          (32'd0),
        .uart_rx          (1'b1),
        .uart_tx          (),
        .o_io_ledr(), .o_io_ledg(), .o_io_lcd(),
        .o_io_hex0(), .o_io_hex1(), .o_io_hex2(),
        .o_io_hex3(), .o_io_hex4(), .o_io_hex5(),
        .o_io_hex6(), .o_io_hex7(),
        .vga_r(), .vga_g(), .vga_b(),
        .vga_clk(), .vga_hs(), .vga_vs(),
        .vga_blank_n(), .vga_sync_n(),
        .o_pc_debug       (),
        .o_insn_vld       (),
        .o_vpu_cycles     (),
        .o_vmask16        (),
        .o_vpu_busy       (vpu_busy),
        .o_fsm_state      (),
        .o_wb_result_lane0(), .o_wb_result_lane1(),
        .o_wb_result_lane2(), .o_wb_result_lane3()
    );

    always #(CLK_HALF) clk = ~clk;

    // ── DMEM pre-init + main stimulus (single initial block, sequential) ──────
    logic [31:0] dmem_init [0:16383];
    logic [31:0] y_ref     [0:4095];
    logic [31:0] y_got;
    int          errors, i;

    initial begin
        // ── Step 1: load and inject Lena RGB into DMEM at time 0 ─────────────
        $readmemh("sw/benchmarks/lena_gray/lena_dmem_init.hex", dmem_init);
        for (i = 0; i < 16384; i++) begin
            dut.u_dmem.bank0.u.mem[i] = dmem_init[i][ 7: 0];
            dut.u_dmem.bank1.u.mem[i] = dmem_init[i][15: 8];
            dut.u_dmem.bank2.u.mem[i] = dmem_init[i][23:16];
            dut.u_dmem.bank3.u.mem[i] = dmem_init[i][31:24];
        end
        $display("[%0t ns] DMEM pre-loaded: R[0]=0x%02X G[0]=0x%02X B[0]=0x%02X",
                 $time, dmem_init[0][7:0], dmem_init[4096][7:0], dmem_init[8192][7:0]);

        // ── Step 2: apply reset ───────────────────────────────────────────────
        reset = 1'b1;
        repeat (RST_CYCS) @(posedge clk);
        reset = 1'b0;
        $display("[%0t ns] Reset released.", $time);

        // ── Step 3: run fixed cycles ──────────────────────────────────────────
        repeat (RUN_CYCS) @(posedge clk);
        $display("[%0t ns] %0d run cycles elapsed.", $time, RUN_CYCS);

        // ── Step 4: wait for VPU to drain (up to 2000 extra cycles) ──────────
        i = 0;
        while (vpu_busy && i < 2000) begin
            @(posedge clk);
            i++;
        end
        if (vpu_busy)
            $display("[WARN] VPU still busy after drain wait — results may be partial.");
        else
            $display("[%0t ns] VPU idle. Checking Y output...", $time);

        // ── Sanity: dump input RGB and output Y for pixel 0 and 4 ────────────
        $display("  Pixel 0: R=0x%02X G=0x%02X B=0x%02X  Y_got=0x%02X Y_exp=0x%02X",
                 dut.u_dmem.bank0.u.mem[0],    // R[0]
                 dut.u_dmem.bank0.u.mem[4096],  // G[0]
                 dut.u_dmem.bank0.u.mem[8192],  // B[0]
                 dut.u_dmem.bank0.u.mem[12288], // Y[0]
                 y_ref[0][7:0]);
        $display("  Pixel 4: R=0x%02X G=0x%02X B=0x%02X  Y_got=0x%02X Y_exp=0x%02X",
                 dut.u_dmem.bank0.u.mem[1],    // R[4]
                 dut.u_dmem.bank0.u.mem[4097],  // G[4]
                 dut.u_dmem.bank0.u.mem[8193],  // B[4]
                 dut.u_dmem.bank0.u.mem[12289], // Y[4]
                 y_ref[1][7:0]);

        // ── Step 5: compare Y words ───────────────────────────────────────────
        $readmemh("sw/benchmarks/lena_gray/lena_y_reference.hex", y_ref);
        errors = 0;
        for (i = 0; i < 4096; i++) begin
            y_got = {dut.u_dmem.bank3.u.mem[12288 + i],
                     dut.u_dmem.bank2.u.mem[12288 + i],
                     dut.u_dmem.bank1.u.mem[12288 + i],
                     dut.u_dmem.bank0.u.mem[12288 + i]};
            if (y_got !== y_ref[i]) begin
                if (errors < 8)
                    $display("  MISMATCH word[%0d]: got=0x%08X exp=0x%08X", i, y_got, y_ref[i]);
                errors++;
            end
        end

        if (errors == 0) begin
            $display("[PASS] All 4096 Y words match lena_y_reference.hex");
            $display("       Y[0..3] = 0x%02X 0x%02X 0x%02X 0x%02X",
                     dut.u_dmem.bank0.u.mem[12288], dut.u_dmem.bank1.u.mem[12288],
                     dut.u_dmem.bank2.u.mem[12288], dut.u_dmem.bank3.u.mem[12288]);
        end else
            $display("[FAIL] %0d / 4096 words mismatch.", errors);

        #100;
        $finish;
    end

    // ── Watchdog ──────────────────────────────────────────────────────────────
    initial begin
        #((RST_CYCS + RUN_CYCS + 5000) * CLK_HALF * 2 + 1000);
        $display("[FAIL] Watchdog expired at %0t ns.", $time);
        $finish;
    end

endmodule
