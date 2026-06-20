`timescale 1ns/1ps

// Lena RGB→Grayscale benchmark on riscv_vpu_top_v2
// (2-stage pipeline + sync DMEM + TL-UL bus + UART)
//
// Adapted from tb_lena_gray.sv; differences:
//   - DUT is riscv_vpu_top_v2
//   - DMEM accessed via dut.u_dmem.mem (dmem_sync)
//   - Scalar RF accessed via dut.u_scalar_core.rf[]
//   - Instruction probed as dut.u_scalar_core.instr_ex
//   - MAX_CYCLES increased (VLSU reads 2-cycle latency → ~2× load time)
module tb_lena_gray_v2;

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

    parameter string DMEM_INIT = "C:\\CapstoneProject2\\riscv_vpu\\sw\\benchmarks\\lena_gray\\lena_dmem_init.hex";
    parameter string DMEM_OUT  = "C:\\CapstoneProject2\\riscv_vpu\\sw\\benchmarks\\lena_gray\\lena_dmem_out.hex";
    localparam int   MAX_CYCLES = 600000;

    riscv_vpu_top_v2 dut (
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
        .vpu_wb_lane3  (vpu_wb_lane3),
        .uart_rx       (1'b1),
        .uart_tx       ()
    );

    `define DMEM  dut.u_dmem.mem
    `define CORE  dut.u_scalar_core

    initial clk = 0;
    always #5 clk = ~clk;

    integer  cycle_cnt;
    logic [31:0] cur_inst;
    integer  out_fd;

    initial begin
        $display("=================================================================");
        $display("  Lena Grayscale v2 — RISC-V VPU Trial (2-stage + sync DMEM)");
        $display("  128x128 pixels, SEW=8, BT.601 via vmulhu.vx");
        $display("  DMEM init: %s", DMEM_INIT);
        $display("=================================================================");

        io_sw = 32'h0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // Load RGB planes into DMEM
        $readmemh(DMEM_INIT, `DMEM);
        $display("  [TB] DMEM loaded.  R[0..3]=%02h%02h%02h%02h  G[0..3]=%02h%02h%02h%02h  B[0..3]=%02h%02h%02h%02h",
            `DMEM[0][7:0],    `DMEM[0][15:8],    `DMEM[0][23:16],    `DMEM[0][31:24],
            `DMEM[4096][7:0], `DMEM[4096][15:8], `DMEM[4096][23:16], `DMEM[4096][31:24],
            `DMEM[8192][7:0], `DMEM[8192][15:8], `DMEM[8192][23:16], `DMEM[8192][31:24]);

        for (cycle_cnt = 0; cycle_cnt < MAX_CYCLES; cycle_cnt++) begin
            @(posedge clk); #1;
            cur_inst = `CORE.instr_ex;

            if (cur_inst == 32'h0000_006f) begin
                $display("  [Cycle %0d] j done — draining VLSU...", cycle_cnt);
                repeat (8) @(posedge clk);
                $display("  [Cycle %0d] VLSU drained.", cycle_cnt + 8);
                break;
            end
        end

        if (cycle_cnt >= MAX_CYCLES - 1)
            $display("  WARNING: timeout after %0d cycles!", MAX_CYCLES);

        // Y channel starts at DMEM word 12288 (byte addr 0x0C000)
        $display("=================================================================");
        $display("  Cycles  : %0d", cycle_cnt + 1);
        $display("  Y[0..3] : %02h %02h %02h %02h",
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
        $display("  scalar rf[6]=%08h rf[7]=%08h rf[28]=%08h rf[29]=%08h",
            `CORE.rf[6], `CORE.rf[7], `CORE.rf[28], `CORE.rf[29]);

        // Dump full DMEM for reconstruct.py
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
        $display("  Next step: python sw/benchmarks/lena_gray/reconstruct.py");
        $display("=================================================================");
        $finish;
    end

endmodule
