`timescale 1ns/1ps

// Lena 128x128 RGB→Grayscale benchmark on riscv_vpu_top_pipeline
// (single_cycle scalar core + pipelined VPU wrapper)
//
// Differences from tb_lena_gray.sv (original, non-pipelined):
//   - DUT is riscv_vpu_top_pipeline (uses vproc_system_wrapper_p)
//   - IMEM backdoor-loaded from lena_imem.hex (overrides imem_from_gcc.hex)
//   - Output written to pipeline_output/lena_dmem_out_pipeline.hex
//   - MAX_CYCLES increased: pipeline adds ST_DRAIN per VPU op
module tb_pipeline_lena;

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

    parameter string IMEM_FILE = "C:\\CapstoneProject2\\riscv_vpu\\sw\\benchmarks\\lena_gray\\lena_imem.hex";
    parameter string DMEM_INIT = "C:\\CapstoneProject2\\riscv_vpu\\sw\\benchmarks\\lena_gray\\lena_dmem_init.hex";
    parameter string DMEM_OUT  = "C:\\CapstoneProject2\\riscv_vpu\\sw\\benchmarks\\lena_gray\\pipeline_output\\lena_dmem_out_pipeline.hex";
    localparam int   MAX_CYCLES = 120000;

    // ── DUT ────────────────────────────────────────────────────────────────
    riscv_vpu_top_pipeline dut (
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

    `define IMEM       dut.u_scalar_core.IMEM.inst_mem
    `define DMEM       dut.u_scalar_core.lsu_u.dmem
    `define SCALAR_RF  dut.u_scalar_core.u_register_file

    // ── Clock ───────────────────────────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Stimulus ────────────────────────────────────────────────────────────
    integer  cycle_cnt;
    integer  jdone_cnt;
    integer  jdone_grace;
    logic [31:0] cur_inst;
    integer  out_fd;

    initial begin
        $display("=================================================================");
        $display("  Lena Grayscale — Pipelined VPU Benchmark");
        $display("  128x128 pixels, SEW=8, BT.601 via vmulhu.vx");
        $display("  scalar core + vproc_system_wrapper_p (1-cycle ALU pipeline)");
        $display("  DMEM init: %s", DMEM_INIT);
        $display("=================================================================");

        io_sw = 32'h0;
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // Backdoor-load program into IMEM (overrides imem_from_gcc.hex)
        $readmemh(IMEM_FILE, `IMEM);
        // Backdoor-load RGB planes into DMEM
        $readmemh(DMEM_INIT, `DMEM);

        $display("  [TB] IMEM loaded from %s", IMEM_FILE);
        $display("  [TB] DMEM loaded.  R[0..3]=%02h%02h%02h%02h  G[0..3]=%02h%02h%02h%02h  B[0..3]=%02h%02h%02h%02h",
            `DMEM[0][7:0],    `DMEM[0][15:8],    `DMEM[0][23:16],    `DMEM[0][31:24],
            `DMEM[4096][7:0], `DMEM[4096][15:8], `DMEM[4096][23:16], `DMEM[4096][31:24],
            `DMEM[8192][7:0], `DMEM[8192][15:8], `DMEM[8192][23:16], `DMEM[8192][31:24]);

        // ── Run until program spins on 'j done' (0x0000006f) ───────────────
        // Confirmed ≥3 times with ≤2 grace cycles to avoid flush false-positives.
        jdone_cnt   = 0;
        jdone_grace = 0;
        for (cycle_cnt = 0; cycle_cnt < MAX_CYCLES; cycle_cnt++) begin
            @(posedge clk); #1;
            cur_inst = dut.u_scalar_core.inst;

            if (cur_inst == 32'h0000_006f) begin
                jdone_cnt++;
                jdone_grace = 0;
            end else if (jdone_cnt > 0) begin
                jdone_grace++;
                if (jdone_grace > 2) begin
                    jdone_cnt   = 0;
                    jdone_grace = 0;
                end
            end

            if (jdone_cnt >= 3) begin
                $display("  [Cycle %0d] j done confirmed — draining VLSU...", cycle_cnt);
                // Pipeline wrapper: last vse8.v has extra ST_DRAIN cycle.
                // Give 16 cycles: 8 for VLSU write-back + 8 for pipeline drain.
                repeat (16) @(posedge clk);
                $display("  [Cycle %0d] drain complete.", cycle_cnt + 16);
                break;
            end
        end

        if (cycle_cnt >= MAX_CYCLES - 1)
            $display("  WARNING: simulation timeout after %0d cycles!", MAX_CYCLES);

        // ── Results ────────────────────────────────────────────────────────
        // Y channel: DMEM words 12288–16383 (byte addr 0x0C000–0x0FFFF)
        $display("=================================================================");
        $display("  Cycles  : %0d", cycle_cnt + 1);
        $display("  Y[0..3] : %02h %02h %02h %02h  (DMEM word 12288)",
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
        $display("  Next step: python sw/benchmarks/lena_gray/reconstruct.py \\");
        $display("    sw/benchmarks/lena_gray/pipeline_output/lena_dmem_out_pipeline.hex");
        $display("=================================================================");
        $finish;
    end

endmodule
