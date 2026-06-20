`timescale 1ns/1ps

// Lena RGB→Grayscale benchmark on riscv_vpu_top_v3
// (5-stage pipeline + sync DMEM + VPU)
//
// Adapted from tb_lena_gray.sv; differences:
//   - DUT is riscv_vpu_top_v3 (active-HIGH reset i_reset)
//   - DMEM accessed via dut.u_dmem.mem (dmem_sync)
//   - Scalar RF accessed via dut.u_core.u_regfile.data*
//   - Instruction probed as dut.u_core.inst_decode (decode-stage, from imem_sync)
//   - No vpu_fifo_full port in v3
//   - MAX_CYCLES increased (5-stage pipeline + VPU stalls)
module tb_lena_gray_v3;

    logic        clk;
    logic        rst;          // active-HIGH
    logic [31:0] io_sw;

    logic [31:0] io_ledr, io_ledg, io_lcd;
    logic [ 6:0] io_hex0, io_hex1, io_hex2, io_hex3;
    logic [ 6:0] io_hex4, io_hex5, io_hex6, io_hex7;
    logic [31:0] pc_debug;
    logic        insn_vld;
    logic [3:0]  vpu_cycles;
    logic [15:0] vpu_vmask16;
    logic        vpu_busy;
    logic [3:0]  vpu_fsm_state;
    logic [31:0] vpu_wb_lane0, vpu_wb_lane1, vpu_wb_lane2, vpu_wb_lane3;

    parameter string DMEM_INIT = "C:\\CapstoneProject2\\riscv_vpu\\sw\\benchmarks\\lena_gray\\lena_dmem_init.hex";
    parameter string DMEM_OUT  = "C:\\CapstoneProject2\\riscv_vpu\\sw\\benchmarks\\lena_gray\\v3_output\\lena_dmem_out_v3.hex";
    localparam int   MAX_CYCLES = 200000;

    // ── DUT ────────────────────────────────────────────────────────────────
    riscv_vpu_top_v3 dut (
        .i_clk              (clk),
        .i_reset            (rst),
        .i_io_sw            (io_sw),
        .o_io_ledr          (io_ledr), .o_io_ledg (io_ledg), .o_io_lcd (io_lcd),
        .o_io_hex0(io_hex0),.o_io_hex1(io_hex1),.o_io_hex2(io_hex2),.o_io_hex3(io_hex3),
        .o_io_hex4(io_hex4),.o_io_hex5(io_hex5),.o_io_hex6(io_hex6),.o_io_hex7(io_hex7),
        .o_pc_debug         (pc_debug),
        .o_insn_vld         (insn_vld),
        .o_vpu_cycles       (vpu_cycles),
        .o_vmask16          (vpu_vmask16),
        .o_vpu_busy         (vpu_busy),
        .o_fsm_state        (vpu_fsm_state),
        .o_wb_result_lane0  (vpu_wb_lane0),
        .o_wb_result_lane1  (vpu_wb_lane1),
        .o_wb_result_lane2  (vpu_wb_lane2),
        .o_wb_result_lane3  (vpu_wb_lane3)
    );

    `define DMEM       dut.u_dmem.mem
    `define SCALAR_RF  dut.u_core.u_regfile
    `define VPU        dut.u_vpu

    // ── Clock ───────────────────────────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── VLSU store diagnostic — first 8 stores with full VRF state ──────────
    int vlsu_store_cnt;
    initial vlsu_store_cnt = 0;
    always @(posedge clk) begin
        if (dut.u_dmem.vlsu_req && dut.u_dmem.vlsu_we && vlsu_store_cnt < 8) begin
            $display("  [VLSU-STORE #%0d] cycle=%0d addr=0x%08h data=0x%08h be=%04b  vs2_sel=%02h rs2l0=%08h rs2l1=%08h",
                vlsu_store_cnt, $time/10,
                dut.u_dmem.vlsu_addr,
                dut.u_dmem.vlsu_wdata,
                dut.u_dmem.vlsu_be,
                dut.u_vpu.vs2_addr_to_vrf,
                dut.u_vpu.rs2_data_lane0,
                dut.u_vpu.rs2_data_lane1);
            vlsu_store_cnt = vlsu_store_cnt + 1;
        end
    end

    // ── VRF lane0 writes to register 1 (v1) ────────────────────────────────
    int vrf_v1_write_cnt;
    initial vrf_v1_write_cnt = 0;
    always @(posedge clk) begin
        if (|dut.u_vpu.vrf_we0_eff && dut.u_vpu.vrf_waddr_eff == 5'd1 && vrf_v1_write_cnt < 10) begin
            $display("  [VRF-WRITE v1 L0] cycle=%0d we=%04b wdata=%08h vd_eff=%02h",
                $time/10, dut.u_vpu.vrf_we0_eff, dut.u_vpu.vrf_wdata0_eff,
                dut.u_vpu.vrf_waddr_eff);
            vrf_v1_write_cnt = vrf_v1_write_cnt + 1;
        end
    end

    // ── vls_fire events (first 8 loads/stores) ─────────────────────────────
    int vpu_dispatch_cnt;
    initial vpu_dispatch_cnt = 0;
    always @(posedge clk) begin
        if (dut.u_vpu.vls_fire && vpu_dispatch_cnt < 8) begin
            $display("  [VLS-FIRE #%0d] cycle=%0d insn=0x%08h rs1=0x%08h is_load=%b  bank0_v1=%02h bank1_v1=%02h bank2_v1=%02h bank3_v1=%02h",
                vpu_dispatch_cnt, $time/10,
                dut.u_core.vpu_insn_o,
                dut.u_core.vpu_rs1_data_o,
                dut.u_vpu.is_vls_load_raw,
                dut.u_vpu.vrf_lane0.bank0[1],
                dut.u_vpu.vrf_lane0.bank1[1],
                dut.u_vpu.vrf_lane0.bank2[1],
                dut.u_vpu.vrf_lane0.bank3[1]);
            vpu_dispatch_cnt = vpu_dispatch_cnt + 1;
        end
    end

    // ── Stimulus ────────────────────────────────────────────────────────────
    integer  cycle_cnt;
    integer  jdone_cnt;    // consecutive j-done hits (require >=3 to avoid flush false-positive)
    integer  jdone_grace;  // allow up to 2 flush NOPs between j-done hits
    logic [31:0] cur_inst;
    integer  out_fd;

    initial begin
        $display("=================================================================");
        $display("  Lena Grayscale — RISC-V VPU v3 Benchmark");
        $display("  128x128 pixels, SEW=8, BT.601 via vmulhu.vx");
        $display("  5-stage pipelined core + sync DMEM + VPU");
        $display("  DMEM init: %s", DMEM_INIT);
        $display("=================================================================");

        io_sw = 32'h0;
        rst   = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(negedge clk);

        // Backdoor-load RGB planes into DMEM after reset clears it
        $readmemh(DMEM_INIT, `DMEM);
        $display("  [TB] DMEM loaded.  R[0..3]=%02h%02h%02h%02h  G[0..3]=%02h%02h%02h%02h  B[0..3]=%02h%02h%02h%02h",
            `DMEM[0][7:0],    `DMEM[0][15:8],    `DMEM[0][23:16],    `DMEM[0][31:24],
            `DMEM[4096][7:0], `DMEM[4096][15:8], `DMEM[4096][23:16], `DMEM[4096][31:24],
            `DMEM[8192][7:0], `DMEM[8192][15:8], `DMEM[8192][23:16], `DMEM[8192][31:24]);

        // ── Run until program spins on 'j done' (0x0000006f) confirmed ≥3 times ──
        // The j-done self-loop (`jal x0, 0`) causes a flush each iteration, so decode
        // alternates j-done / NOP. Require 3 hits with ≤2 non-j-done cycles between
        // to distinguish from the one-shot false-positive during crt0 startup.
        jdone_cnt   = 0;
        jdone_grace = 0;
        for (cycle_cnt = 0; cycle_cnt < MAX_CYCLES; cycle_cnt++) begin
            @(posedge clk); #1;
            cur_inst = dut.u_core.inst_decode;

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
                $display("  [Cycle %0d] j done confirmed — draining VPU/VLSU...", cycle_cnt);
                repeat (32) @(posedge clk);
                $display("  [Cycle %0d] drain complete.", cycle_cnt + 32);
                break;
            end
        end

        if (cycle_cnt >= MAX_CYCLES - 1)
            $display("  WARNING: simulation timeout after %0d cycles!", MAX_CYCLES);

        // ── Results ────────────────────────────────────────────────────────
        // Y channel starts at DMEM word 12288 (byte addr 0x0C000, 128x128 layout)
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
        $display("  scalar t1=%08h t2=%08h t3=%08h t4=%08h",
            `SCALAR_RF.data6,  `SCALAR_RF.data7,
            `SCALAR_RF.data28, `SCALAR_RF.data29);
        $display("  VPU CSR: vl=%0d  vtype=%08h",
            `VPU.csr_vl_o, `VPU.csr_vtype_o);

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
        $display("  Next step: python sw/benchmarks/lena_gray/reconstruct.py");
        $display("=================================================================");
        $finish;
    end

endmodule
