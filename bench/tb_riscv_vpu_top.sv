`timescale 1ns/1ps

module tb_riscv_vpu_top;

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

    parameter string VCD_FILE = "wave_riscv_vpu.vcd";
    localparam int    MAX_SIM_CYCLES = 5000;
    // Lệnh cuối chương trình gcc (success_end): j success_end  -> ffdff06f
    localparam logic [31:0] INST_TAIL_J = 32'hFFDFF06F;
    localparam int          TAIL_HITS_STOP = 24;

    riscv_vpu_top dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .io_sw         (io_sw),
        .io_ledr       (io_ledr),
        .io_ledg       (io_ledg),
        .io_lcd        (io_lcd),
        .io_hex0       (io_hex0),
        .io_hex1       (io_hex1),
        .io_hex2       (io_hex2),
        .io_hex3       (io_hex3),
        .io_hex4       (io_hex4),
        .io_hex5       (io_hex5),
        .io_hex6       (io_hex6),
        .io_hex7       (io_hex7),
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

    initial begin
        $dumpfile(VCD_FILE);
        $dumpvars(0, tb_riscv_vpu_top);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    `define SCALAR_RF dut.u_scalar_core.u_register_file
    `define VPU       dut.u_vpu

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

    // Gán ngẫu nhiên tất cả bank VRF (4 lane x 32 reg x 4 bank)
    task automatic init_vrf_random(ref int rnd_state);
        int r, ln;
        logic [31:0] w;
        begin
            for (r = 0; r < 32; r++) begin
                for (ln = 0; ln < 4; ln++) begin
                    w = $random(rnd_state);
                    case (ln)
                        0: begin
                            `VPU.vrf_lane0.bank0[r] = w[7:0];
                            `VPU.vrf_lane0.bank1[r] = w[15:8];
                            `VPU.vrf_lane0.bank2[r] = w[23:16];
                            `VPU.vrf_lane0.bank3[r] = w[31:24];
                        end
                        1: begin
                            `VPU.vrf_lane1.bank0[r] = w[7:0];
                            `VPU.vrf_lane1.bank1[r] = w[15:8];
                            `VPU.vrf_lane1.bank2[r] = w[23:16];
                            `VPU.vrf_lane1.bank3[r] = w[31:24];
                        end
                        2: begin
                            `VPU.vrf_lane2.bank0[r] = w[7:0];
                            `VPU.vrf_lane2.bank1[r] = w[15:8];
                            `VPU.vrf_lane2.bank2[r] = w[23:16];
                            `VPU.vrf_lane2.bank3[r] = w[31:24];
                        end
                        3: begin
                            `VPU.vrf_lane3.bank0[r] = w[7:0];
                            `VPU.vrf_lane3.bank1[r] = w[15:8];
                            `VPU.vrf_lane3.bank2[r] = w[23:16];
                            `VPU.vrf_lane3.bank3[r] = w[31:24];
                        end
                    endcase
                end
            end
            $display("  [TB] VRF randomized ($random state), all lanes v0..v31.");
        end
    endtask

    task automatic dump_scalar_regs_full;
        begin
            $display("  ---- Scalar (integer) register file x0..x31 ----");
            $display("  x00..x03 : %08h %08h %08h %08h",
                `SCALAR_RF.data0, `SCALAR_RF.data1, `SCALAR_RF.data2, `SCALAR_RF.data3);
            $display("  x04..x07 : %08h %08h %08h %08h",
                `SCALAR_RF.data4, `SCALAR_RF.data5, `SCALAR_RF.data6, `SCALAR_RF.data7);
            $display("  x08..x11 : %08h %08h %08h %08h",
                `SCALAR_RF.data8, `SCALAR_RF.data9, `SCALAR_RF.data10, `SCALAR_RF.data11);
            $display("  x12..x15 : %08h %08h %08h %08h",
                `SCALAR_RF.data12, `SCALAR_RF.data13, `SCALAR_RF.data14, `SCALAR_RF.data15);
            $display("  x16..x19 : %08h %08h %08h %08h",
                `SCALAR_RF.data16, `SCALAR_RF.data17, `SCALAR_RF.data18, `SCALAR_RF.data19);
            $display("  x20..x23 : %08h %08h %08h %08h",
                `SCALAR_RF.data20, `SCALAR_RF.data21, `SCALAR_RF.data22, `SCALAR_RF.data23);
            $display("  x24..x27 : %08h %08h %08h %08h",
                `SCALAR_RF.data24, `SCALAR_RF.data25, `SCALAR_RF.data26, `SCALAR_RF.data27);
            $display("  x28..x31 : %08h %08h %08h %08h",
                `SCALAR_RF.data28, `SCALAR_RF.data29, `SCALAR_RF.data30, `SCALAR_RF.data31);
        end
    endtask

    task automatic dump_vrf_all;
        int r;
        begin
            $display("  ---- VRF (per lane 32-bit word, v0..v31) ----");
            $display("       Lane0        Lane1        Lane2        Lane3");
            for (r = 0; r < 32; r++) begin
                $display("  v%0d  %08h   %08h   %08h   %08h", r,
                    vrf_word(0, r), vrf_word(1, r), vrf_word(2, r), vrf_word(3, r));
            end
        end
    endtask

    task automatic dump_vpu_status;
        begin
            $display("  ---- VPU status ----");
            $display("  fsm_state=%0d  busy=%b  fifo_full=%b  cycles=%0d  vmask16=%04h",
                vpu_fsm_state, vpu_busy, vpu_fifo_full, vpu_cycles, vpu_vmask16);
            $display("  wb_lane0=%08h  wb_lane1=%08h  wb_lane2=%08h  wb_lane3=%08h",
                vpu_wb_lane0, vpu_wb_lane1, vpu_wb_lane2, vpu_wb_lane3);
            $display("  CSR: vl=%0d  vtype=%08h  vlenb=%0d",
                `VPU.csr_vl_o, `VPU.csr_vtype_o, `VPU.csr_vlenb_o);
        end
    endtask

    function string decode_opcode(input [6:0] opcode);
        case (opcode)
            7'b0110011: decode_opcode = "R-type";
            7'b0010011: decode_opcode = "I-type";
            7'b0000011: decode_opcode = "LOAD";
            7'b0100011: decode_opcode = "STORE";
            7'b1100011: decode_opcode = "BRANCH";
            7'b1101111: decode_opcode = "JAL";
            7'b1100111: decode_opcode = "JALR";
            7'b0110111: decode_opcode = "LUI";
            7'b0010111: decode_opcode = "AUIPC";
            7'b1010111: decode_opcode = "OP-V";
            7'b0000111: decode_opcode = "VL";
            7'b0100111: decode_opcode = "VS";
            7'b1110011: decode_opcode = "SYSTEM";
            default:    decode_opcode = "???";
        endcase
    endfunction

    integer cycle_cnt;
    integer tail_j_cnt;
    logic [31:0] cur_inst;
    logic [31:0] prev_pc;
    string       stop_reason;
    int          vrf_rnd_state;

    initial begin
        stop_reason   = "";
        tail_j_cnt    = 0;
        vrf_rnd_state = 32'hACE1_2026;
        void'($value$plusargs("SEED=%d", vrf_rnd_state));

        $display("==========================================================");
        $display("  RISC-V + VPU top testbench");
        $display("  VCD: %s", VCD_FILE);
        $display("  IMEM: see imem.sv $readmemh path");
        $display("  VRF random SEED=%0d (override: vsim ... +SEED=N)", vrf_rnd_state);
        $display("==========================================================");

        io_sw = 32'h0000_0005;
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        init_vrf_random(vrf_rnd_state);

        prev_pc = 32'hFFFF_FFFF;

        for (cycle_cnt = 0; cycle_cnt < MAX_SIM_CYCLES; cycle_cnt++) begin
            @(posedge clk);
            #1;

            cur_inst = dut.u_scalar_core.inst;

            if (cur_inst === INST_TAIL_J)
                tail_j_cnt++;

            if (pc_debug !== prev_pc) begin
                $display("\n[Cycle %0d] PC=%08h  inst=%08h  (%s)  vld=%b  vpu_vld=%b  stall=%b",
                    cycle_cnt, pc_debug, cur_inst,
                    decode_opcode(cur_inst[6:0]),
                    insn_vld,
                    dut.u_scalar_core.vpu_insn_vld,
                    dut.u_scalar_core.vpu_stall);

                if (cur_inst[6:0] == 7'b1010111) begin
                    $display("         >> OP-V  funct3=%03b  is_config=%b",
                        cur_inst[14:12],
                        dut.u_scalar_core.is_vpu_config);
                end
            end

            if (dut.u_scalar_core.vpu_stall)
                $display("  [Cycle %0d] STALL (vpu_cfg_pending=%b  cfg_done=%b  vpu_ready=%b)",
                    cycle_cnt,
                    dut.u_scalar_core.vpu_cfg_pending_r,
                    dut.u_vpu.vpu_cfg_done,
                    dut.u_vpu.vpu_ready);

            if (dut.u_vpu.vpu_cfg_done)
                $display("  [Cycle %0d] >>> VPU cfg done: vl_remain=%0d  wb -> x%0d",
                    cycle_cnt,
                    dut.u_vpu.vpu_vl_remain,
                    cur_inst[11:7]);

            // Debug: VRF write from FSM — shows cycle_mask16 to detect partial-write bugs
            if (dut.u_vpu.fsm_vrf_wren && !dut.u_vpu.vlsu_vrf_we)
                $display("  [Cycle %0d] FSM VRF write: vd=%0d  mask16=%04h  we0=%b we1=%b we2=%b we3=%b  wb0=%08h wb3=%08h",
                    cycle_cnt,
                    dut.u_vpu.vrf_waddr_eff,
                    dut.u_vpu.cycle_mask16_dbg,
                    dut.u_vpu.vrf_we0_eff,
                    dut.u_vpu.vrf_we1_eff,
                    dut.u_vpu.vrf_we2_eff,
                    dut.u_vpu.vrf_we3_eff,
                    dut.u_vpu.vrf_wdata0_eff,
                    dut.u_vpu.vrf_wdata3_eff);

            // Debug: VLSU VRF write
            if (dut.u_vpu.vlsu_vrf_we)
                $display("  [Cycle %0d] VLSU VRF write: vd=%0d  d0=%08h d1=%08h d2=%08h d3=%08h",
                    cycle_cnt,
                    dut.u_vpu.vlsu_vrf_waddr,
                    dut.u_vpu.vlsu_vrf_wdata_l0,
                    dut.u_vpu.vlsu_vrf_wdata_l1,
                    dut.u_vpu.vlsu_vrf_wdata_l2,
                    dut.u_vpu.vlsu_vrf_wdata_l3);

            prev_pc = pc_debug;

            if (cur_inst == 32'h0000006f) begin
                stop_reason = "jal x0,0 (old test style)";
                break;
            end

            if (tail_j_cnt >= TAIL_HITS_STOP) begin
                stop_reason = "tail spin (ffdff06f) — program finished";
                break;
            end
        end

        if (cycle_cnt >= MAX_SIM_CYCLES - 1 && stop_reason == "")
            stop_reason = "MAX_SIM_CYCLES timeout";

        $display("\n==========================================================");
        $display("  Stopped: %s", stop_reason);
        $display("  Cycles run: %0d", cycle_cnt + 1);
        $display("==========================================================");
        $display("  PC = %08h  cur_inst = %08h", pc_debug, cur_inst);

        dump_scalar_regs_full();
        dump_vpu_status();
        dump_vrf_all();

        $display("\n  IO: ledr=%08h  ledg=%08h  lcd=%08h",
            io_ledr, io_ledg, io_lcd);

        $display("\n==========================================================");
        $display("  VCD saved: %s  (open in GTKWave / ModelSim)", VCD_FILE);
        $display("==========================================================");
        $dumpflush;
        $finish;
    end

endmodule
