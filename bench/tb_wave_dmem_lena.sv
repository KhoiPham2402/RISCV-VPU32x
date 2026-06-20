`timescale 1ns/1ps
// tb_wave_dmem_lena.sv — Waveform-friendly wrapper for DMEM lena sim.
// Adds decoded instruction/FSM strings so engineers read names, not hex.
//
// Run: vsim -do run_wave_dmem_lena.do

module tb_wave_dmem_lena;

    localparam int CLK_HALF  = 10;       // 50 MHz
    localparam int RST_CYCS  = 20;       // KEY[0] held for 20 cycles
    localparam int RUN_CYCS  = 90_000;

    logic        clk = 1'b0;
    logic        reset;
    logic        vpu_busy;

    always #(CLK_HALF) clk = ~clk;

    // ── DUT ──────────────────────────────────────────────────────────────────
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
        .o_io_hex0(), .o_io_hex1(), .o_io_hex2(), .o_io_hex3(),
        .o_io_hex4(), .o_io_hex5(), .o_io_hex6(), .o_io_hex7(),
        .vga_r(), .vga_g(), .vga_b(),
        .vga_clk(), .vga_hs(), .vga_vs(), .vga_blank_n(), .vga_sync_n(),
        .o_pc_debug       (),
        .o_insn_vld       (),
        .o_vpu_cycles     (),
        .o_vmask16        (),
        .o_vpu_busy       (vpu_busy),
        .o_fsm_state      (),
        .o_wb_result_lane0(), .o_wb_result_lane1(),
        .o_wb_result_lane2(), .o_wb_result_lane3()
    );

    // ── DMEM pre-load ─────────────────────────────────────────────────────────
    logic [31:0] dmem_init [0:16383];

    initial begin
        $readmemh("sw/benchmarks/lena_gray/lena_dmem_init.hex", dmem_init);
        for (int i = 0; i < 16384; i++) begin
            dut.u_dmem.bank0.u.mem[i] = dmem_init[i][ 7: 0];
            dut.u_dmem.bank1.u.mem[i] = dmem_init[i][15: 8];
            dut.u_dmem.bank2.u.mem[i] = dmem_init[i][23:16];
            dut.u_dmem.bank3.u.mem[i] = dmem_init[i][31:24];
        end

        // KEY[0] press = reset high
        reset = 1'b1;
        repeat (RST_CYCS) @(posedge clk);
        // KEY[0] release = reset low; PLL locks 16 cycles later
        reset = 1'b0;

        repeat (RUN_CYCS) @(posedge clk);
        $display("[%0t ns] Simulation done.", $time);
        $finish;
    end

    // ═════════════════════════════════════════════════════════════════════════
    // DECODED SIGNALS — these appear as readable strings in the wave window
    // ═════════════════════════════════════════════════════════════════════════

    // ── Scalar instruction name ───────────────────────────────────────────────
    string scalar_insn;
    always_comb begin
        automatic logic [31:0] insn = dut.u_core.inst_exe; // EX-stage instruction
        automatic logic [6:0]  op   = insn[6:0];
        automatic logic [2:0]  f3   = insn[14:12];
        case (op)
            7'b0110011: begin // R-type ALU
                case ({insn[31:25], f3})
                    10'b0000000_000: scalar_insn = "add";
                    10'b0100000_000: scalar_insn = "sub";
                    10'b0000000_111: scalar_insn = "and";
                    10'b0000001_000: scalar_insn = "mul";
                    default:         scalar_insn = "alu_r";
                endcase
            end
            7'b0010011: begin // I-type ALU
                case (f3)
                    3'b000: scalar_insn = (insn[31:20]==12'h000) ? "nop/mv" : "addi";
                    3'b010: scalar_insn = "slti";
                    3'b100: scalar_insn = "xori";
                    3'b110: scalar_insn = "ori";
                    3'b111: scalar_insn = "andi";
                    3'b001: scalar_insn = "slli";
                    3'b101: scalar_insn = "srli/a";
                    default: scalar_insn = "alu_i";
                endcase
            end
            7'b0110111: scalar_insn = "lui";
            7'b0010111: scalar_insn = "auipc";
            7'b1101111: scalar_insn = "jal";
            7'b1100111: scalar_insn = "jalr";
            7'b1100011: begin // Branch
                case (f3)
                    3'b000: scalar_insn = "beq";
                    3'b001: scalar_insn = "bne";
                    3'b100: scalar_insn = "blt";
                    3'b101: scalar_insn = "bge";
                    3'b110: scalar_insn = "bltu";
                    3'b111: scalar_insn = "bgeu";
                    default: scalar_insn = "branch";
                endcase
            end
            7'b0000011: begin // Load
                case (f3)
                    3'b000: scalar_insn = "lb";
                    3'b001: scalar_insn = "lh";
                    3'b010: scalar_insn = "lw";
                    3'b100: scalar_insn = "lbu";
                    3'b101: scalar_insn = "lhu";
                    default: scalar_insn = "load";
                endcase
            end
            7'b0100011: begin // Store
                case (f3)
                    3'b000: scalar_insn = "sb";
                    3'b001: scalar_insn = "sh";
                    3'b010: scalar_insn = "sw";
                    default: scalar_insn = "store";
                endcase
            end
            7'b1010111: begin // VPU (OP-V)
                if (f3 == 3'b111 && insn[31] == 1'b0)
                    scalar_insn = "vsetvli";
                else begin
                    case (insn[6:0])
                        default: scalar_insn = "vpu_disp";
                    endcase
                end
            end
            7'b0000111: begin // VLE
                case (f3)
                    3'b000: scalar_insn = "vle8.v";
                    3'b101: scalar_insn = "vle16.v";
                    3'b110: scalar_insn = "vle32.v";
                    default: scalar_insn = "vle?.v";
                endcase
            end
            7'b0100111: begin // VSE
                case (f3)
                    3'b000: scalar_insn = "vse8.v";
                    3'b101: scalar_insn = "vse16.v";
                    3'b110: scalar_insn = "vse32.v";
                    default: scalar_insn = "vse?.v";
                endcase
            end
            7'b1110011: scalar_insn = "csr/*";
            default:    scalar_insn = (insn == 32'h0) ? "---" : "other";
        endcase
    end

    // ── VPU instruction name (what enters the VPU FIFO) ───────────────────────
    string vpu_insn_name;
    always_comb begin
        automatic logic [31:0] vi  = dut.vpu_insn;
        automatic logic [6:0]  op  = vi[6:0];
        automatic logic [2:0]  f3  = vi[14:12];
        automatic logic [5:0]  f6  = vi[31:26];
        if (!dut.vpu_insn_vld) begin
            vpu_insn_name = "---";
        end else begin
            case (op)
                7'b1010111: begin
                    if (f3 == 3'b111 && vi[31] == 0)
                        vpu_insn_name = "vsetvli";
                    else case (f3)
                        3'b000: case (f6) // OPIVV
                            6'h00: vpu_insn_name = "vadd.vv";
                            6'h02: vpu_insn_name = "vsub.vv";
                            default: vpu_insn_name = "opivv";
                        endcase
                        3'b100: case (f6) // OPIVX
                            6'h00: vpu_insn_name = "vadd.vx";
                            6'h02: vpu_insn_name = "vsub.vx";
                            6'h0D: vpu_insn_name = "vrsub.vx";
                            6'h15: vpu_insn_name = "vsll.vx";
                            6'h10: vpu_insn_name = "vsrl.vx";
                            default: vpu_insn_name = "opivx";
                        endcase
                        3'b011: vpu_insn_name = "opivi";
                        3'b010: case (f6) // OPMVV
                            6'h24: vpu_insn_name = "vmul.vv";
                            6'h25: vpu_insn_name = "vmulh.vv";
                            6'h26: vpu_insn_name = "vmulhu.vv";
                            6'h27: vpu_insn_name = "vmulhsu.vv";
                            6'h00: vpu_insn_name = "vredsum.vs";
                            6'h07: vpu_insn_name = "vredmax.vs";
                            6'h05: vpu_insn_name = "vredmin.vs";
                            default: vpu_insn_name = "opmvv";
                        endcase
                        3'b110: case (f6) // OPMVX
                            6'h24: vpu_insn_name = "vmul.vx";
                            6'h25: vpu_insn_name = "vmulh.vx";
                            6'h26: vpu_insn_name = "vmulhu.vx";
                            6'h27: vpu_insn_name = "vmulhsu.vx";
                            default: vpu_insn_name = "opmvx";
                        endcase
                        default: vpu_insn_name = "vpu?";
                    endcase
                end
                7'b0000111: case (f3)
                    3'b000: vpu_insn_name = "vle8.v";
                    3'b101: vpu_insn_name = "vle16.v";
                    3'b110: vpu_insn_name = "vle32.v";
                    default: vpu_insn_name = "vle?.v";
                endcase
                7'b0100111: case (f3)
                    3'b000: vpu_insn_name = "vse8.v";
                    3'b101: vpu_insn_name = "vse16.v";
                    3'b110: vpu_insn_name = "vse32.v";
                    default: vpu_insn_name = "vse?.v";
                endcase
                default: vpu_insn_name = "other";
            endcase
        end
    end

    // ── VPU FSM state name ────────────────────────────────────────────────────
    string fsm_state_name;
    always_comb begin
        case (dut.u_vpu.fsm_state)
            4'd0: fsm_state_name = "IDLE";
            4'd1: fsm_state_name = "CONFIG";
            4'd2: fsm_state_name = "EXEC";
            4'd3: fsm_state_name = "WIDENL";
            4'd4: fsm_state_name = "WIDENH";
            4'd5: fsm_state_name = "MASKING";
            4'd6: fsm_state_name = "FINAL_MASK";
            4'd7: fsm_state_name = "REDUCTION";
            4'd8: fsm_state_name = "RED_DONE";
            default: fsm_state_name = "???";
        endcase
    end

    // ── Register name decode ─────────────────────────────────────────────────
    function automatic string reg_name(input logic [4:0] r);
        case (r)
            5'd0:  reg_name = "x0/zero";
            5'd1:  reg_name = "x1/ra";
            5'd2:  reg_name = "x2/sp";
            5'd3:  reg_name = "x3/gp";
            5'd4:  reg_name = "x4/tp";
            5'd5:  reg_name = "x5/t0";
            5'd6:  reg_name = "x6/t1";
            5'd7:  reg_name = "x7/t2";
            5'd8:  reg_name = "x8/s0";
            5'd9:  reg_name = "x9/s1";
            5'd10: reg_name = "x10/a0";
            5'd11: reg_name = "x11/a1";
            5'd12: reg_name = "x12/a2";
            5'd13: reg_name = "x13/a3";
            5'd14: reg_name = "x14/a4";
            5'd15: reg_name = "x15/a5";
            5'd16: reg_name = "x16/a6";
            5'd17: reg_name = "x17/a7";
            5'd28: reg_name = "x28/t3";
            5'd29: reg_name = "x29/t4";
            5'd30: reg_name = "x30/t5";
            5'd31: reg_name = "x31/t6";
            default: reg_name = $sformatf("x%0d", r);
        endcase
    endfunction

    // WB port decode
    string wb_rd_name;
    always_comb begin
        if (dut.u_core.rf_wren && dut.u_core.rf_waddr != 5'd0)
            wb_rd_name = reg_name(dut.u_core.rf_waddr);
        else
            wb_rd_name = "---";
    end

    // ── VLSU operation name ───────────────────────────────────────────────────
    string vlsu_op;
    always_comb begin
        if (!dut.vlsu_req)          vlsu_op = "---";
        else if (dut.vlsu_we)       vlsu_op = "STORE";
        else                        vlsu_op = "LOAD";
    end

endmodule
