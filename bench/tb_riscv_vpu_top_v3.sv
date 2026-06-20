`timescale 1ns/1ps

module tb_riscv_vpu_top_v3;

    logic        clk;
    logic        rst;        // active-HIGH
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

    parameter string VCD_FILE       = "wave_riscv_vpu_v3.vcd";
    localparam int   MAX_SIM_CYCLES = 5000;
    // Termination: self-loop JAL (0x0000006F) OR jal x0,+4 used in test_alu.hex (0x0040006F)
    localparam logic [31:0] INST_J_DONE  = 32'h0000_006F;
    localparam logic [31:0] INST_J_ALT   = 32'h0040_006F;  // test_alu.hex end-of-test jump
    // Tail-spin: count consecutive FFDFF06F (tolerating up to 3 NOPs between hits)
    localparam logic [31:0] INST_TAIL_J  = 32'hFFDFF06F;
    localparam int   TAIL_HITS_STOP = 5;   // 5 cumulative hits within the spin loop

    riscv_vpu_top_v3 dut (
        .i_clk              (clk),
        .i_reset            (rst),
        .i_io_sw            (io_sw),
        .o_io_ledr          (io_ledr),
        .o_io_ledg          (io_ledg),
        .o_io_lcd           (io_lcd),
        .o_io_hex0          (io_hex0),
        .o_io_hex1          (io_hex1),
        .o_io_hex2          (io_hex2),
        .o_io_hex3          (io_hex3),
        .o_io_hex4          (io_hex4),
        .o_io_hex5          (io_hex5),
        .o_io_hex6          (io_hex6),
        .o_io_hex7          (io_hex7),
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

    `define SCALAR_RF dut.u_core.u_regfile
    `define VPU       dut.u_vpu
    `define DMEM      dut.u_dmem.mem

    function automatic logic [31:0] vrf_word(input int lane, input int r);
        case (lane)
            0: vrf_word = {`VPU.vrf_lane0.bank3[r], `VPU.vrf_lane0.bank2[r],
                           `VPU.vrf_lane0.bank1[r], `VPU.vrf_lane0.bank0[r]};
            1: vrf_word = {`VPU.vrf_lane1.bank3[r], `VPU.vrf_lane1.bank2[r],
                           `VPU.vrf_lane1.bank1[r], `VPU.vrf_lane1.bank0[r]};
            2: vrf_word = {`VPU.vrf_lane2.bank3[r], `VPU.vrf_lane2.bank2[r],
                           `VPU.vrf_lane2.bank1[r], `VPU.vrf_lane2.bank0[r]};
            3: vrf_word = {`VPU.vrf_lane3.bank3[r], `VPU.vrf_lane3.bank2[r],
                           `VPU.vrf_lane3.bank1[r], `VPU.vrf_lane3.bank0[r]};
            default: vrf_word = 32'h0;
        endcase
    endfunction

    task automatic init_vrf_random(ref int rnd_state);
        int r, ln; logic [31:0] w;
        for (r = 0; r < 32; r++) for (ln = 0; ln < 4; ln++) begin
            w = $random(rnd_state);
            case (ln)
                0: begin `VPU.vrf_lane0.bank0[r]=w[7:0];  `VPU.vrf_lane0.bank1[r]=w[15:8];
                         `VPU.vrf_lane0.bank2[r]=w[23:16]; `VPU.vrf_lane0.bank3[r]=w[31:24]; end
                1: begin `VPU.vrf_lane1.bank0[r]=w[7:0];  `VPU.vrf_lane1.bank1[r]=w[15:8];
                         `VPU.vrf_lane1.bank2[r]=w[23:16]; `VPU.vrf_lane1.bank3[r]=w[31:24]; end
                2: begin `VPU.vrf_lane2.bank0[r]=w[7:0];  `VPU.vrf_lane2.bank1[r]=w[15:8];
                         `VPU.vrf_lane2.bank2[r]=w[23:16]; `VPU.vrf_lane2.bank3[r]=w[31:24]; end
                3: begin `VPU.vrf_lane3.bank0[r]=w[7:0];  `VPU.vrf_lane3.bank1[r]=w[15:8];
                         `VPU.vrf_lane3.bank2[r]=w[23:16]; `VPU.vrf_lane3.bank3[r]=w[31:24]; end
            endcase
        end
    endtask

    task automatic dump_scalar_regs;
        $display("  ---- Scalar RF ----");
        $display("  x00-x03: %08h %08h %08h %08h",
            32'd0,             `SCALAR_RF.data1,  `SCALAR_RF.data2,  `SCALAR_RF.data3);
        $display("  x04-x07: %08h %08h %08h %08h",
            `SCALAR_RF.data4,  `SCALAR_RF.data5,  `SCALAR_RF.data6,  `SCALAR_RF.data7);
        $display("  x08-x11: %08h %08h %08h %08h",
            `SCALAR_RF.data8,  `SCALAR_RF.data9,  `SCALAR_RF.data10, `SCALAR_RF.data11);
        $display("  x28-x31: %08h %08h %08h %08h",
            `SCALAR_RF.data28, `SCALAR_RF.data29, `SCALAR_RF.data30, `SCALAR_RF.data31);
    endtask

    task automatic dump_vpu_status;
        $display("  ---- VPU status ----");
        $display("  fsm=%0d  busy=%b  cycles=%0d  vmask16=%04h",
            vpu_fsm_state, vpu_busy, vpu_cycles, vpu_vmask16);
        $display("  CSR: vl=%0d  vtype=%08h",
            `VPU.csr_vl_o, `VPU.csr_vtype_o);
    endtask

    task automatic dump_vrf_key;
        $display("  ---- VRF Lane0 (key registers) ----");
        $display("  v0 =%08h  v1 =%08h  v2 =%08h  v3 =%08h",
            vrf_word(0,0), vrf_word(0,1), vrf_word(0,2), vrf_word(0,3));
        $display("  v4 =%08h  v5 =%08h  v7 =%08h  v8 =%08h",
            vrf_word(0,4), vrf_word(0,5), vrf_word(0,7), vrf_word(0,8));
        $display("  v10=%08h  v11=%08h",
            vrf_word(0,10), vrf_word(0,11));
    endtask

    initial clk = 0;
    always #5 clk = ~clk;

    int  cycle_cnt;
    int  seed;
    int  tail_j_cnt;
    int  nop_grace;     // allow up to 3 NOPs between tail-spin hits
    logic [31:0] cur_inst;
    string stop_reason;

    // IMEM load check
    initial begin
        #1;
        $display("[TB-DIAG] IMEM[0]=%08h [1]=%08h [2]=%08h [3]=%08h",
            dut.u_core.u_imem.mem[0], dut.u_core.u_imem.mem[1],
            dut.u_core.u_imem.mem[2], dut.u_core.u_imem.mem[3]);
        if (dut.u_core.u_imem.mem[0] === 32'hxxxxxxxx)
            $display("[TB-DIAG] WARNING: IMEM mem[0] is X — $readmemh may have failed!");
    end

    initial begin
        stop_reason = "";
        tail_j_cnt  = 0;
        nop_grace   = 0;
        seed        = 42;
        io_sw       = 32'b0;
        rst         = 1'b1;
        repeat(4) @(posedge clk);
        rst = 1'b0;
        init_vrf_random(seed);

        $display("[TB] Reset released. Running up to %0d cycles.", MAX_SIM_CYCLES);

        for (cycle_cnt = 0; cycle_cnt < MAX_SIM_CYCLES; cycle_cnt++) begin
            @(posedge clk); #1;
            cur_inst = dut.u_core.inst_decode;

            // j-done: exact self-loop or test_alu.hex's end-of-test jump
            if (cur_inst == INST_J_DONE || cur_inst == INST_J_ALT) begin
                stop_reason = "j done";
                // Drain VPU before reporting
                repeat(50) @(posedge clk);
                break;
            end

            // Tail-spin counter — tolerates up to 3 non-tail cycles between hits
            if (cur_inst == INST_TAIL_J) begin
                tail_j_cnt++;
                nop_grace = 0;
            end else if (tail_j_cnt > 0) begin
                nop_grace++;
                if (nop_grace > 3) begin
                    // Too many non-tail cycles → reset counter
                    tail_j_cnt = 0;
                    nop_grace  = 0;
                end
            end

            if (tail_j_cnt >= TAIL_HITS_STOP) begin
                stop_reason = "tail spin (ffdff06f) — program finished";
                repeat(50) @(posedge clk);
                break;
            end
        end

        if (stop_reason == "") stop_reason = "MAX_SIM_CYCLES timeout";

        $display("\n==========================================================");
        $display("  Stopped : %s", stop_reason);
        $display("  Cycles  : %0d", cycle_cnt + 1);
        $display("  PC      : %08h  inst: %08h", pc_debug, cur_inst);
        $display("==========================================================");
        dump_scalar_regs;
        dump_vpu_status;
        dump_vrf_key;

        // ── Sanity checks (test_alu.hex) ─────────────────────────────────
        $display("\n  ---- test_alu.hex sanity checks ----");
        if (`SCALAR_RF.data9 === 32'd2)
            $display("  [PASS] x9/s1 = 2  (scalar ADDI forwarding OK)");
        else
            $display("  [FAIL] x9/s1 = %0d (expected 2)", `SCALAR_RF.data9);

        if (`VPU.csr_vl_o === 32'd4)
            $display("  [PASS] VPU vl = 4  (vsetvli dispatch OK)");
        else
            $display("  [FAIL] VPU vl = %0d (expected 4)", `VPU.csr_vl_o);

        $display("==========================================================");
        $finish;
    end

    // Tohost sentinel — ignore data==0 (startup clear)
    always @(posedge clk) begin
        if (dut.u_core.s_dmem_we_o &&
            dut.u_core.s_dmem_addr_o == 32'hFFFF_FFFC &&
            dut.u_core.s_dmem_wdata_o != 32'h0) begin
            $display("[TB] Tohost write @cycle %0d: data=%08h  (%s)",
                cycle_cnt, dut.u_core.s_dmem_wdata_o,
                dut.u_core.s_dmem_wdata_o[0] ? "PASS" : "FAIL");
            #20; dump_scalar_regs; dump_vpu_status; $finish;
        end
    end

endmodule
