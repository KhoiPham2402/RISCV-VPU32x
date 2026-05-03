`timescale 1ns/1ps

// Testbench: Lena 128x128 RGB→Grayscale via VPU
// Initialises DMEM with RGB data from lena_dmem_init.hex, runs the lena_gray
// RISC-V program, then dumps the full DMEM to lena_dmem_out.hex for
// post-processing by reconstruct.py.
module tb_lena_gray;

    logic        clk;
    logic        rst_n;
    logic [31:0] io_sw;

    logic [31:0] io_ledr, io_ledg, io_lcd;
    logic [ 6:0] io_hex0, io_hex1, io_hex2, io_hex3;
    logic [ 6:0] io_hex4, io_hex5, io_hex6, io_hex7;
    logic [31:0] pc_debug;
    logic        insn_vld;
    logic [3:0]  vpu_cycles;
    logic [15:0] vpu_vmask16;
    logic        vpu_fifo_full, vpu_busy;
    logic [3:0]  vpu_fsm_state;
    logic [31:0] vpu_wb_lane0, vpu_wb_lane1, vpu_wb_lane2, vpu_wb_lane3;

    // Absolute paths — match imem.sv convention for this project
    parameter string DMEM_INIT = "C:\\CapstoneProject2\\riscv_vpu\\sw\\benchmarks\\lena_gray\\lena_dmem_init.hex";
    parameter string DMEM_OUT  = "C:\\CapstoneProject2\\riscv_vpu\\sw\\benchmarks\\lena_gray\\lena_dmem_out.hex";
    localparam int   MAX_CYCLES = 60000;

    // ── DUT ────────────────────────────────────────────────────────────────
    riscv_vpu_top dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .io_sw         (io_sw),
        .io_ledr       (io_ledr), .io_ledg (io_ledg), .io_lcd (io_lcd),
        .io_hex0(io_hex0),.io_hex1(io_hex1),.io_hex2(io_hex2),.io_hex3(io_hex3),
        .io_hex4(io_hex4),.io_hex5(io_hex5),.io_hex6(io_hex6),.io_hex7(io_hex7),
        .pc_debug      (pc_debug),
        .insn_vld      (insn_vld),
        .vpu_cycles    (vpu_cycles),
        .vpu_vmask16   (vpu_vmask16),
        .vpu_fifo_full (vpu_fifo_full),
        .vpu_busy      (vpu_busy),
        .vpu_fsm_state (vpu_fsm_state),
        .vpu_wb_lane0  (vpu_wb_lane0),
        .vpu_wb_lane1  (vpu_wb_lane1),
        .vpu_wb_lane2  (vpu_wb_lane2),
        .vpu_wb_lane3  (vpu_wb_lane3)
    );

    `define DMEM       dut.u_scalar_core.lsu_u.dmem
    `define SCALAR_RF  dut.u_scalar_core.u_register_file

    // ── Clock ───────────────────────────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Stimulus ────────────────────────────────────────────────────────────
    integer  cycle_cnt;
    logic [31:0] cur_inst;
    integer  out_fd;

    initial begin
        $display("=================================================================");
        $display("  Lena Grayscale — RISC-V VPU Benchmark");
        $display("  128x128 pixels, SEW=8, BT.601 via vmulhu.vx");
        $display("  DMEM init: %s", DMEM_INIT);
        $display("=================================================================");

        io_sw = 32'h0;
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // Load RGB planes into DMEM after reset clears it
        $readmemh(DMEM_INIT, `DMEM);
        $display("  [TB] DMEM loaded.  R[0..3]=%02h%02h%02h%02h  G[0..3]=%02h%02h%02h%02h  B[0..3]=%02h%02h%02h%02h",
            `DMEM[0][7:0],    `DMEM[0][15:8],    `DMEM[0][23:16],    `DMEM[0][31:24],
            `DMEM[4096][7:0], `DMEM[4096][15:8], `DMEM[4096][23:16], `DMEM[4096][31:24],
            `DMEM[8192][7:0], `DMEM[8192][15:8], `DMEM[8192][23:16], `DMEM[8192][31:24]);

        // ── Run until program spins on 'j done' (0x0000006f) ───────────────
        for (cycle_cnt = 0; cycle_cnt < MAX_CYCLES; cycle_cnt++) begin
            @(posedge clk); #1;
            cur_inst = dut.u_scalar_core.inst;

            if (cur_inst == 32'h0000_006f) begin
                $display("  [Cycle %0d] j done detected — draining VLSU...", cycle_cnt);
                // bne/ret/jal are not VPU instructions so they don't stall on vlsu_busy.
                // The last vse8.v needs up to 4 more posedges to commit all word-writes.
                repeat (8) @(posedge clk);
                $display("  [Cycle %0d] VLSU drained — program complete.", cycle_cnt + 8);
                break;
            end
        end

        if (cycle_cnt >= MAX_CYCLES - 1)
            $display("  WARNING: simulation timeout after %0d cycles!", MAX_CYCLES);

        // ── Results ────────────────────────────────────────────────────────
        // Y channel starts at DMEM word 12288 (byte addr 0x0C000)
        $display("=================================================================");
        $display("  Cycles  : %0d", cycle_cnt + 1);
        $display("  Y[0..3] : %02h %02h %02h %02h  (from DMEM word 12288)",
            `DMEM[12288][7:0], `DMEM[12288][15:8],
            `DMEM[12288][23:16],`DMEM[12288][31:24]);
        $display("  Y[4..7] : %02h %02h %02h %02h",
            `DMEM[12289][7:0], `DMEM[12289][15:8],
            `DMEM[12289][23:16],`DMEM[12289][31:24]);
        $display("  Y[8..11]: %02h %02h %02h %02h",
            `DMEM[12290][7:0], `DMEM[12290][15:8],
            `DMEM[12290][23:16],`DMEM[12290][31:24]);
        $display("  Y[12..15]:%02h %02h %02h %02h",
            `DMEM[12291][7:0], `DMEM[12291][15:8],
            `DMEM[12291][23:16],`DMEM[12291][31:24]);
        $display("  scalar t1=%08h t2=%08h t3=%08h t4=%08h",
            `SCALAR_RF.data6,  `SCALAR_RF.data7,
            `SCALAR_RF.data28, `SCALAR_RF.data29);

        // ── Dump full DMEM for reconstruct.py ──────────────────────────────
        out_fd = $fopen(DMEM_OUT, "w");
        if (out_fd == 0) begin
            $display("  WARNING: cannot open %s for write", DMEM_OUT);
        end else begin
            for (int i = 0; i < 16384; i++)
                $fdisplay(out_fd, "%08x", `DMEM[i]);
            $fclose(out_fd);
            $display("  DMEM dumped → %s", DMEM_OUT);
        end

        $display("=================================================================");
        $display("  Next step:");
        $display("    python sw/benchmarks/lena_gray/reconstruct.py");
        $display("    → lena_vpu_output.png + lena_comparison.png");
        $display("=================================================================");
        $finish;
    end

endmodule
