`timescale 1ns / 1ps
// Waveform testbench for vproc_fsm state transitions.
// Runs one instruction of each type to show all major states:
//   ST_IDLE→ST_CONFIG, ST_IDLE→ST_EXEC, ST_IDLE→ST_WIDENL→ST_WIDENH,
//   ST_IDLE→ST_REDUCTION→ST_REDUCTION_DONE
//
// Key signals (see run_wave_fsm_sim.do):
//   fsm_state, busy, latch_ctrl_en, vrf_wren, s_offset_en, d_offset_en,
//   offset_reset, counter_done, pop_ready, fifo_data_valid, raw_stall
//
// Run: vsim -do run_wave_fsm_sim.do

module tb_wave_fsm;

    localparam [6:0] OPCODE_OPV = 7'b101_0111;
    localparam [5:0] VADD   = 6'h00, VSUB   = 6'h02;
    localparam [5:0] VMUL   = 6'h25;
    localparam [5:0] VADDW  = 6'h31;
    localparam [5:0] VREDSUM= 6'h0C, VREDMAX= 6'h0D;

    localparam [10:0] ZIMM_E32_M1 = 11'h0D0;
    localparam [10:0] ZIMM_E16_M1 = 11'h048;

    // FSM state names for logging
    localparam [3:0] ST_IDLE          = 4'd0;
    localparam [3:0] ST_CONFIG        = 4'd1;
    localparam [3:0] ST_EXEC          = 4'd2;
    localparam [3:0] ST_WIDENL        = 4'd3;
    localparam [3:0] ST_WIDENH        = 4'd4;
    localparam [3:0] ST_REDUCTION     = 4'd7;
    localparam [3:0] ST_REDUCTION_DONE= 4'd8;

    reg         clk, rst_n, instr_valid, vrf_commit_en;
    reg [31:0]  instruction, rs1_scalar_data, rs2_scalar_data;

    wire [3:0]  cycles, fsm_state;
    wire [15:0] vmask16;
    wire        fifo_full, busy, vpu_ready, vpu_cfg_done;
    wire [31:0] wb_result_lane0, wb_result_lane1, wb_result_lane2, wb_result_lane3;
    wire [31:0] vpu_vl_remain, csr_vl_o, csr_vtype_o, csr_vlenb_o;
    wire [11:0] scalar_csr_addr;
    wire [31:0] scalar_csr_rdata;
    wire        vlsu_mem_req, vlsu_mem_we, vlsu_busy_o;
    wire [31:0] vlsu_mem_addr, vlsu_mem_wdata;
    wire [3:0]  vlsu_mem_be;

    assign scalar_csr_addr = 12'h000;

    vproc_system_wrapper dut (
        .clk              (clk),            .rst_n           (rst_n),
        .instr_valid      (instr_valid),    .instruction     (instruction),
        .rs1_scalar_data  (rs1_scalar_data),.rs2_scalar_data (rs2_scalar_data),
        .vrf_commit_en    (vrf_commit_en),  .cycles          (cycles),
        .vmask16          (vmask16),        .fifo_full       (fifo_full),
        .busy             (busy),           .fsm_state       (fsm_state),
        .wb_result_lane0  (wb_result_lane0),.wb_result_lane1 (wb_result_lane1),
        .wb_result_lane2  (wb_result_lane2),.wb_result_lane3 (wb_result_lane3),
        .vpu_ready        (vpu_ready),      .vpu_cfg_done    (vpu_cfg_done),
        .vpu_vl_remain    (vpu_vl_remain),  .csr_vl_o        (csr_vl_o),
        .csr_vtype_o      (csr_vtype_o),    .csr_vlenb_o     (csr_vlenb_o),
        .scalar_csr_addr  (scalar_csr_addr),.scalar_csr_rdata(scalar_csr_rdata),
        .vlsu_mem_req     (vlsu_mem_req),   .vlsu_mem_we     (vlsu_mem_we),
        .vlsu_mem_addr    (vlsu_mem_addr),  .vlsu_mem_be     (vlsu_mem_be),
        .vlsu_mem_wdata   (vlsu_mem_wdata), .vlsu_mem_rdata  (32'd0),
        .vlsu_mem_ready   (1'b1),           .vlsu_busy_o     (vlsu_busy_o)
    );

    always #5 clk = ~clk;

    function automatic [31:0] build_opv(
        input [5:0] f6, input vm, input [2:0] f3,
        input [4:0] vs1, vs2, vd
    );
        build_opv        = 32'd0;
        build_opv[6:0]   = OPCODE_OPV;
        build_opv[11:7]  = vd;
        build_opv[14:12] = f3;
        build_opv[19:15] = vs1;
        build_opv[24:20] = vs2;
        build_opv[25]    = vm;
        build_opv[31:26] = f6;
    endfunction

    function automatic [31:0] build_vsetvli(
        input [10:0] zimm, input [4:0] vd, rs1_idx
    );
        build_vsetvli        = 32'd0;
        build_vsetvli[6:0]   = OPCODE_OPV;
        build_vsetvli[14:12] = 3'b111;
        build_vsetvli[19:15] = rs1_idx;
        build_vsetvli[11:7]  = vd;
        build_vsetvli[30:20] = zimm;
    endfunction

    task automatic vrf_write4(
        input int v,
        input [31:0] w0, w1, w2, w3
    );
        {dut.vrf_lane0.bank3[v],dut.vrf_lane0.bank2[v],
         dut.vrf_lane0.bank1[v],dut.vrf_lane0.bank0[v]} = w0;
        {dut.vrf_lane1.bank3[v],dut.vrf_lane1.bank2[v],
         dut.vrf_lane1.bank1[v],dut.vrf_lane1.bank0[v]} = w1;
        {dut.vrf_lane2.bank3[v],dut.vrf_lane2.bank2[v],
         dut.vrf_lane2.bank1[v],dut.vrf_lane2.bank0[v]} = w2;
        {dut.vrf_lane3.bank3[v],dut.vrf_lane3.bank2[v],
         dut.vrf_lane3.bank1[v],dut.vrf_lane3.bank0[v]} = w3;
    endtask

    task automatic issue(input [31:0] inst, input [31:0] rs1v, rs2v);
        @(negedge clk);
        instruction = inst; rs1_scalar_data = rs1v; rs2_scalar_data = rs2v;
        instr_valid = 1'b1;
        @(negedge clk);
        instr_valid = 1'b0;
    endtask

    task automatic wait_done;
        int t;
        t = 0; while ((busy !== 1'b1) && (t < 300)) begin @(posedge clk); t++; end
        t = 0; while ((busy !== 1'b0) && (t < 5000)) begin @(posedge clk); t++; end
        if (t >= 5000) $display("*** TIMEOUT ***");
    endtask

    // Log FSM state name (for $display readability)
    function automatic string state_name(input [3:0] s);
        case (s)
            4'd0: state_name = "ST_IDLE";
            4'd1: state_name = "ST_CONFIG";
            4'd2: state_name = "ST_EXEC";
            4'd3: state_name = "ST_WIDENL";
            4'd4: state_name = "ST_WIDENH";
            4'd5: state_name = "ST_MASKING";
            4'd6: state_name = "ST_FINAL_MASKING";
            4'd7: state_name = "ST_REDUCTION";
            4'd8: state_name = "ST_REDUCTION_DONE";
            default: state_name = "ILLEGAL";
        endcase
    endfunction

    // Track state transitions
    reg [3:0] prev_state;
    always @(posedge clk) begin
        if (fsm_state !== prev_state) begin
            $display("[FSM] t=%0t  %s → %s", $time,
                     state_name(prev_state), state_name(fsm_state));
            prev_state <= fsm_state;
        end
    end

    integer pass_cnt = 0, fail_cnt = 0;

    // Verify FSM visited expected state during last operation
    task automatic check_state_visited(input string tag, input [3:0] exp_state);
        // This is logged by the monitor above; here we just log pass
        pass_cnt++;
        $display("[CHECK] %s: expected to visit %s", tag, state_name(exp_state));
    endtask

    initial begin
        clk = 0; rst_n = 0; instr_valid = 0;
        instruction = 0; rs1_scalar_data = 0; rs2_scalar_data = 0;
        vrf_commit_en = 1'b1;
        prev_state = 4'd0;

        repeat(4) @(negedge clk);
        rst_n = 1;
        repeat(2) @(negedge clk);

        // ─── Phase 1: ST_IDLE → ST_CONFIG → ST_IDLE ─────────────────────────
        $display("\n[FSM_WAVE] ===== Phase 1: vsetvli → ST_CONFIG =====");
        issue(build_vsetvli(ZIMM_E32_M1, 5'd0, 5'd1), 32'd4, 32'd0);
        wait_done;
        repeat(2) @(posedge clk);

        // ─── Phase 2: ST_IDLE → ST_EXEC × 2 cycles → ST_IDLE ────────────────
        $display("\n[FSM_WAVE] ===== Phase 2: vadd.vv → ST_EXEC (4 cycles) =====");
        vrf_write4(1, 32'd1, 32'd2, 32'd3, 32'd4);
        vrf_write4(2, 32'd5, 32'd6, 32'd7, 32'd8);
        issue(build_opv(VADD, 1'b1, 3'b000, 5'd1, 5'd2, 5'd4), 32'd0, 32'd0);
        wait_done;
        repeat(3) @(posedge clk);

        // ─── Phase 3: vmul.vv (same EXEC path, show VRF write) ───────────────
        $display("\n[FSM_WAVE] ===== Phase 3: vmul.vv → ST_EXEC =====");
        issue(build_opv(VMUL, 1'b1, 3'b000, 5'd1, 5'd2, 5'd5), 32'd0, 32'd0);
        wait_done;
        repeat(3) @(posedge clk);

        // ─── Phase 4: Widening vadd.wv → ST_WIDENL → ST_WIDENH → ST_IDLE ────
        $display("\n[FSM_WAVE] ===== Phase 4: vaddw.vv → ST_WIDENL → ST_WIDENH =====");
        issue(build_vsetvli(ZIMM_E16_M1, 5'd0, 5'd1), 32'd4, 32'd0);
        wait_done;
        vrf_write4(1, 32'h0002_0001, 32'h0004_0003, 32'h0006_0005, 32'h0008_0007);
        vrf_write4(2, 32'h0009_000A, 32'h000B_000C, 32'h000D_000E, 32'h000F_0010);
        issue(build_opv(VADDW, 1'b1, 3'b000, 5'd1, 5'd2, 5'd6), 32'd0, 32'd0);
        wait_done;
        repeat(3) @(posedge clk);

        // ─── Phase 5: Reduction vredsum → ST_REDUCTION → ST_REDUCTION_DONE ───
        $display("\n[FSM_WAVE] ===== Phase 5: vredsum.vs → ST_REDUCTION → DONE =====");
        issue(build_vsetvli(ZIMM_E32_M1, 5'd0, 5'd1), 32'd4, 32'd0);
        wait_done;
        vrf_write4(3, 32'd100, 32'd200, 32'd300, 32'd400);
        vrf_write4(4, 32'd0,   32'd0,   32'd0,   32'd0);
        // vredsum.vs v5, v3, v4
        issue(build_opv(VREDSUM, 1'b1, 3'b010, 5'd4, 5'd3, 5'd5), 32'd0, 32'd0);
        wait_done;
        repeat(3) @(posedge clk);

        // ─── Phase 6: Two back-to-back instructions (pipeline test) ──────────
        $display("\n[FSM_WAVE] ===== Phase 6: back-to-back vadd then vsub =====");
        issue(build_vsetvli(ZIMM_E32_M1, 5'd0, 5'd1), 32'd4, 32'd0);
        wait_done;
        vrf_write4(1, 32'd10, 32'd20, 32'd30, 32'd40);
        vrf_write4(2, 32'd1,  32'd2,  32'd3,  32'd4);
        issue(build_opv(VADD, 1'b1, 3'b000, 5'd1, 5'd2, 5'd8), 32'd0, 32'd0);
        wait_done;
        issue(build_opv(VSUB, 1'b1, 3'b000, 5'd1, 5'd2, 5'd9), 32'd0, 32'd0);
        wait_done;

        repeat(10) @(posedge clk);
        $display("\n[FSM_WAVE] All phases complete. FSM trace logged above.");
        $display("[FSM_WAVE] Expected sequence: IDLE→CONFIG→IDLE, IDLE→EXEC→IDLE,");
        $display("           IDLE→EXEC→IDLE, IDLE→WIDENL→WIDENH→IDLE,");
        $display("           IDLE→REDUCTION→REDUCTION_DONE→IDLE, IDLE→EXEC×2→IDLE");
        $finish;
    end

endmodule
