`timescale 1ns/1ps

// Trial testbench for riscv_vpu_top_v2.
// Adapted from tb_riscv_vpu_top.sv; differences:
//   - DUT is riscv_vpu_top_v2 (pipeline core + sync memory + UART + TL-UL)
//   - uart_rx tied to 1 (idle); uart_tx ignored
//   - Scalar RF accessed via dut.u_scalar_core.rf[] array
//   - Current instruction probed as dut.u_scalar_core.instr_ex
module tb_riscv_vpu_top_v2;

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

    parameter string VCD_FILE = "wave_riscv_vpu_v2.vcd";
    localparam int    MAX_SIM_CYCLES  = 10000;
    localparam logic [31:0] INST_TAIL_J = 32'hFFDFF06F;
    localparam int          TAIL_HITS_STOP = 24;

    riscv_vpu_top_v2 dut (
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
        .vpu_wb_lane3  (vpu_wb_lane3),
        .uart_rx       (1'b1),   // idle (no incoming serial data in this test)
        .uart_tx       ()
    );

    initial begin
        $dumpfile(VCD_FILE);
        $dumpvars(0, tb_riscv_vpu_top_v2);
    end

    initial clk = 0;
    always #5 clk = ~clk;

    `define CORE  dut.u_scalar_core
    `define VPU   dut.u_vpu
    `define DMEM  dut.u_dmem.mem

    // ── VRF access helper (same layout as original TB) ────────────────────
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

    task automatic dump_scalar_regs;
        integer i;
        begin
            $display("  ---- Scalar RF x0..x31 ----");
            for (i = 0; i < 32; i += 4) begin
                $display("  x%02d..x%02d: %08h %08h %08h %08h",
                    i, i+3,
                    `CORE.rf[i], `CORE.rf[i+1], `CORE.rf[i+2], `CORE.rf[i+3]);
            end
        end
    endtask

    task automatic dump_vpu_status;
        begin
            $display("  ---- VPU status ----");
            $display("  fsm=%0d busy=%b fifo_full=%b cycles=%0d vmask16=%04h",
                vpu_fsm_state, vpu_busy, vpu_fifo_full, vpu_cycles, vpu_vmask16);
            $display("  wb_lane0=%08h wb_lane1=%08h wb_lane2=%08h wb_lane3=%08h",
                vpu_wb_lane0, vpu_wb_lane1, vpu_wb_lane2, vpu_wb_lane3);
        end
    endtask

    task automatic dump_vrf;
        integer r;
        begin
            $display("  ---- VRF v0..v31 (lane0..lane3) ----");
            for (r = 0; r < 32; r++)
                $display("  v%0d  %08h  %08h  %08h  %08h", r,
                    vrf_word(0,r), vrf_word(1,r), vrf_word(2,r), vrf_word(3,r));
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

    integer cycle_cnt, tail_j_cnt;
    logic [31:0] cur_inst, prev_pc;
    string stop_reason;

    initial begin
        stop_reason = "";
        tail_j_cnt  = 0;

        $display("==========================================================");
        $display("  RISC-V + VPU trial testbench (v2: pipeline + sync mem)");
        $display("  VCD: %s", VCD_FILE);
        $display("==========================================================");

        io_sw = 32'h0000_0005;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        prev_pc = 32'hFFFF_FFFF;

        for (cycle_cnt = 0; cycle_cnt < MAX_SIM_CYCLES; cycle_cnt++) begin
            @(posedge clk);
            #1;

            cur_inst = `CORE.instr_ex;

            if (cur_inst === INST_TAIL_J)
                tail_j_cnt++;

            if (pc_debug !== prev_pc) begin
                $display("\n[Cycle %0d] PC=%08h  inst=%08h (%s)  vld=%b  bubble=%b",
                    cycle_cnt, pc_debug, cur_inst,
                    decode_opcode(cur_inst[6:0]),
                    insn_vld, `CORE.ex_bubble);
            end

            if (`CORE.vpu_stall)
                $display("  [Cycle %0d] VPU STALL (cfg_pending=%b cfg_done=%b ready=%b)",
                    cycle_cnt, `CORE.vpu_cfg_pending_r,
                    dut.vpu_cfg_done, dut.vpu_ready);

            if (`CORE.load_stall)
                $display("  [Cycle %0d] LOAD STALL (rd=%0d op=%03b)",
                    cycle_cnt, `CORE.rd_addr, `CORE.funct3);

            prev_pc = pc_debug;

            if (cur_inst == 32'h0000006f) begin
                stop_reason = "jal x0,0 (infinite loop)";
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
        $display("  Stopped: %s  (cycles=%0d)", stop_reason, cycle_cnt + 1);
        $display("==========================================================");
        $display("  PC=%08h  inst=%08h", pc_debug, cur_inst);

        // matmul mailbox check (DMEM words at byte offset 0x1E0 = word 0x78 = 120)
        $display("\n  -- Mailbox DMEM[0x1E0..0x1EC] (matmul result) --");
        $display("  [0]=%0d  [1]=%0d  [2]=%0d  [3]=%0d",
            `DMEM[120], `DMEM[121], `DMEM[122], `DMEM[123]);
        $display("  Expected: 10, 26, 42, 58");

        dump_scalar_regs();
        dump_vpu_status();
        dump_vrf();

        $display("\n  IO: ledr=%08h ledg=%08h lcd=%08h", io_ledr, io_ledg, io_lcd);
        $display("  VCD: %s", VCD_FILE);
        $display("==========================================================");

        $dumpflush;
        $finish;
    end

endmodule
