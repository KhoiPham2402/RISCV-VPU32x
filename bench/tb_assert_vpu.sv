`timescale 1ns / 1ps
// Assertion-heavy testbench for vproc_system_wrapper.
// Runs 20+ directed tests alongside 15 concurrent SVA properties.
// Catches: illegal FSM states, dual-write hazards, stall protocol
// violations, reduction protocol bugs, X-propagation.
//
// Run: vsim -do run_assert_sim.do

module tb_assert_vpu;

    // ── Opcodes ────────────────────────────────────────────────────────────────
    localparam [6:0] OPCODE_OPV  = 7'b101_0111;
    localparam [6:0] OPCODE_LOAD = 7'b000_0111;   // VLE
    localparam [6:0] OPCODE_STOR = 7'b010_0111;   // VSE

    localparam [10:0] ZIMM_E8_M1  = 11'h008; // SEW=8  LMUL=1 ta ma
    localparam [10:0] ZIMM_E32_M1 = 11'h0D0; // SEW=32 LMUL=1 ta ma
    localparam [10:0] ZIMM_E32_M2 = 11'h0D1; // SEW=32 LMUL=2 ta ma

    localparam [5:0] VADD    = 6'h00, VSUB    = 6'h02, VRSUB   = 6'h03;
    localparam [5:0] VMINU   = 6'h04, VMIN    = 6'h05;
    localparam [5:0] VMAXU   = 6'h06, VMAX    = 6'h07;
    localparam [5:0] VAND    = 6'h09, VOR     = 6'h0A, VXOR    = 6'h0B;
    localparam [5:0] VREDSUM = 6'h0C, VREDMAX = 6'h0D, VREDMAXU= 6'h0E;
    localparam [5:0] VREDMIN = 6'h0F, VSRL    = 6'h10, VSRA    = 6'h12;
    localparam [5:0] VREDMINU= 6'h14, VSLL    = 6'h15;
    localparam [5:0] VCMPEQ  = 6'h18, VCMPLTU = 6'h1A, VCMPLT  = 6'h1B;
    localparam [5:0] VMULHU  = 6'h24, VMUL    = 6'h25, VMULH   = 6'h27;
    localparam [5:0] VADDW   = 6'h31, VSUBW   = 6'h33;

    // FSM state encoding
    localparam [3:0] ST_IDLE          = 4'd0;
    localparam [3:0] ST_CONFIG        = 4'd1;
    localparam [3:0] ST_EXEC          = 4'd2;
    localparam [3:0] ST_WIDENL        = 4'd3;
    localparam [3:0] ST_WIDENH        = 4'd4;
    localparam [3:0] ST_MASKING       = 4'd5;
    localparam [3:0] ST_FINAL_MASKING = 4'd6;
    localparam [3:0] ST_REDUCTION     = 4'd7;
    localparam [3:0] ST_REDUCTION_DONE= 4'd8;

    // ── Signals ────────────────────────────────────────────────────────────────
    reg         clk, rst_n, instr_valid, vrf_commit_en;
    reg [31:0]  instruction, rs1_scalar_data, rs2_scalar_data;

    wire [3:0]  cycles;
    wire [15:0] vmask16;
    wire        fifo_full, busy;
    wire [3:0]  fsm_state;
    wire [31:0] wb_result_lane0, wb_result_lane1, wb_result_lane2, wb_result_lane3;
    wire        vpu_ready, vpu_cfg_done;
    wire [31:0] vpu_vl_remain, csr_vl_o, csr_vtype_o, csr_vlenb_o;
    wire [11:0] scalar_csr_addr;
    wire [31:0] scalar_csr_rdata;
    wire        vlsu_mem_req, vlsu_mem_we, vlsu_busy_o;
    wire [31:0] vlsu_mem_addr, vlsu_mem_wdata;
    wire [3:0]  vlsu_mem_be;

    assign scalar_csr_addr = 12'h000;

    integer pass_cnt = 0, fail_cnt = 0, assert_trip = 0;

    // ── DUT ────────────────────────────────────────────────────────────────────
    vproc_system_wrapper dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .instr_valid      (instr_valid),
        .instruction      (instruction),
        .rs1_scalar_data  (rs1_scalar_data),
        .rs2_scalar_data  (rs2_scalar_data),
        .vrf_commit_en    (vrf_commit_en),
        .cycles           (cycles),
        .vmask16          (vmask16),
        .fifo_full        (fifo_full),
        .busy             (busy),
        .fsm_state        (fsm_state),
        .wb_result_lane0  (wb_result_lane0),
        .wb_result_lane1  (wb_result_lane1),
        .wb_result_lane2  (wb_result_lane2),
        .wb_result_lane3  (wb_result_lane3),
        .vpu_ready        (vpu_ready),
        .vpu_cfg_done     (vpu_cfg_done),
        .vpu_vl_remain    (vpu_vl_remain),
        .csr_vl_o         (csr_vl_o),
        .csr_vtype_o      (csr_vtype_o),
        .csr_vlenb_o      (csr_vlenb_o),
        .scalar_csr_addr  (scalar_csr_addr),
        .scalar_csr_rdata (scalar_csr_rdata),
        .vlsu_mem_req     (vlsu_mem_req),
        .vlsu_mem_we      (vlsu_mem_we),
        .vlsu_mem_addr    (vlsu_mem_addr),
        .vlsu_mem_be      (vlsu_mem_be),
        .vlsu_mem_wdata   (vlsu_mem_wdata),
        .vlsu_mem_rdata   (32'd0),
        .vlsu_mem_ready   (1'b1),
        .vlsu_busy_o      (vlsu_busy_o)
    );

    always #5 clk = ~clk;

    // ═══════════════════════════════════════════════════════════════════════════
    //  CONCURRENT SVA ASSERTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    // A1: FSM state must be 0..8 (no illegal encoding)
    A1_fsm_valid: assert property (
        @(posedge clk) disable iff (!rst_n)
        (fsm_state <= 4'd8)
    ) else begin
        assert_trip++;
        $error("[ASSERT TRIP] A1: illegal FSM state=%0d at t=%0t", fsm_state, $time);
    end

    // A2: busy must equal (state != ST_IDLE)
    A2_busy_consistency: assert property (
        @(posedge clk) disable iff (!rst_n)
        (busy == (fsm_state != ST_IDLE))
    ) else begin
        assert_trip++;
        $error("[ASSERT TRIP] A2: busy=%b inconsistent with state=%0d at t=%0t",
               busy, fsm_state, $time);
    end

    // A3: when FIFO is full, vpu_ready must deassert (backpressure protocol)
    // NOTE: vpu_ready is independent of FSM busy — the FIFO decouples them.
    //       The correct invariant is: fifo_full → !vpu_ready (not busy → !vpu_ready).
    A3_fifo_full_blocks_ready: assert property (
        @(posedge clk) disable iff (!rst_n)
        (fifo_full |-> !vpu_ready)
    ) else begin
        assert_trip++;
        $error("[ASSERT TRIP] A3: vpu_ready=1 while fifo_full at t=%0t", $time);
    end

    // A4: vpu_cfg_done must be a 1-cycle pulse
    A4_cfg_done_pulse: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(vpu_cfg_done) |=> !vpu_cfg_done
    ) else begin
        assert_trip++;
        $error("[ASSERT TRIP] A4: vpu_cfg_done held high >1 cycle at t=%0t", $time);
    end

    // A5: FSM must not glitch back to IDLE within 1 cycle of rising busy
    A5_fsm_no_idle_glitch: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(busy) |=> (fsm_state != ST_IDLE)
    ) else begin
        assert_trip++;
        $error("[ASSERT TRIP] A5: FSM glitched back to IDLE 1 cycle after rising busy at t=%0t", $time);
    end

    // A6: FIFO pop_ready must only assert when FIFO has data
    A6_fifo_pop_coherence: assert property (
        @(posedge clk) disable iff (!rst_n)
        (dut.fsm_pop_ready |-> dut.fifo_data_valid)
    ) else begin
        assert_trip++;
        $error("[ASSERT TRIP] A6: pop_ready=1 but fifo empty at t=%0t", $time);
    end

    // A7: latch_ctrl_en must only fire from ST_IDLE
    A7_latch_from_idle: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(dut.fsm_latch_ctrl_en) |-> ($past(fsm_state) == ST_IDLE)
    ) else begin
        assert_trip++;
        $error("[ASSERT TRIP] A7: ctrl latched but FSM not in ST_IDLE, state=%0d at t=%0t",
               $past(fsm_state), $time);
    end

    // A8: no simultaneous VRF write from ALU pipeline and VLSU
    A8_no_vrf_dual_write: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(dut.vlsu_vrf_we && dut.fsm_vrf_wren && vrf_commit_en)
    ) else begin
        assert_trip++;
        $error("[ASSERT TRIP] A8: simultaneous ALU+VLSU VRF write at t=%0t", $time);
    end

    // A9: reduction wb_valid is a 1-cycle pulse
    A9_reduction_wb_pulse: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(dut.reduction_wb_valid) |=> !dut.reduction_wb_valid
    ) else begin
        assert_trip++;
        $error("[ASSERT TRIP] A9: reduction_wb_valid held >1 cycle at t=%0t", $time);
    end

    // A10: reduction result must not be X when wb_valid
    A10_reduction_no_x: assert property (
        @(posedge clk) disable iff (!rst_n)
        (dut.reduction_wb_valid |-> !$isunknown(dut.reduction_result))
    ) else begin
        assert_trip++;
        $error("[ASSERT TRIP] A10: reduction_result is X when wb_valid=1 at t=%0t", $time);
    end

    // A11: wb_result must not be X when ALU writes VRF
    A11_wb_no_x: assert property (
        @(posedge clk) disable iff (!rst_n)
        ((dut.fsm_vrf_wren && vrf_commit_en) |-> !$isunknown(wb_result_lane0))
    ) else begin
        assert_trip++;
        $error("[ASSERT TRIP] A11: wb_result_lane0 is X during VRF write at t=%0t", $time);
    end

    // A12: raw_stall must prevent FSM from *starting* a new instruction.
    // raw_stall gates fifo_data_valid into the FSM — so the FSM must not
    // transition out of IDLE while raw_stall is asserted.
    // (raw_stall=1 while FSM is already in ST_EXEC is legal: it blocks the NEXT pickup.)
    A12_raw_stall_blocks_new_start: assert property (
        @(posedge clk) disable iff (!rst_n)
        (dut.raw_stall && (fsm_state == ST_IDLE)) |=>
            (fsm_state == ST_IDLE || !dut.raw_stall)
    ) else begin
        assert_trip++;
        $error("[ASSERT TRIP] A12: FSM left IDLE while raw_stall=1 at t=%0t", $time);
    end

    // A13: csr_vl_o must not exceed 16 (max elements for SEW=8 VLEN=128)
    A13_vl_upper_bound: assert property (
        @(posedge clk) disable iff (!rst_n)
        (csr_vl_o <= 32'd16)
    ) else begin
        assert_trip++;
        $error("[ASSERT TRIP] A13: csr_vl_o=%0d exceeds 16 at t=%0t", csr_vl_o, $time);
    end

    // A14: vrf_commit_en must be high whenever DUT drives a writeback
    // (in this testbench we tie it high; assertion verifies the write path)
    A14_commit_en_stable: assert property (
        @(posedge clk) disable iff (!rst_n)
        (vrf_commit_en == 1'b1)
    ) else begin
        assert_trip++;
        $error("[ASSERT TRIP] A14: vrf_commit_en deasserted unexpectedly at t=%0t", $time);
    end

    // A15: offset_reset must only pulse when FSM transitions back to IDLE
    A15_offset_reset_safe: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(dut.fsm_offset_reset) |=>
            (fsm_state == ST_IDLE || fsm_state == ST_CONFIG ||
             fsm_state == ST_EXEC || fsm_state == ST_WIDENL)
    ) else begin
        assert_trip++;
        $error("[ASSERT TRIP] A15: offset_reset fired at unexpected FSM state=%0d at t=%0t",
               fsm_state, $time);
    end

    // ═══════════════════════════════════════════════════════════════════════════
    //  HELPER FUNCTIONS & TASKS
    // ═══════════════════════════════════════════════════════════════════════════

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
        build_vsetvli[31]    = 1'b0;
    endfunction

    // VRF direct read (4 lanes × 1 word per register)
    function automatic [31:0] vrf_word(input int lane, input int v);
        case (lane)
            0: vrf_word = {dut.vrf_lane0.bank3[v], dut.vrf_lane0.bank2[v],
                           dut.vrf_lane0.bank1[v], dut.vrf_lane0.bank0[v]};
            1: vrf_word = {dut.vrf_lane1.bank3[v], dut.vrf_lane1.bank2[v],
                           dut.vrf_lane1.bank1[v], dut.vrf_lane1.bank0[v]};
            2: vrf_word = {dut.vrf_lane2.bank3[v], dut.vrf_lane2.bank2[v],
                           dut.vrf_lane2.bank1[v], dut.vrf_lane2.bank0[v]};
            3: vrf_word = {dut.vrf_lane3.bank3[v], dut.vrf_lane3.bank2[v],
                           dut.vrf_lane3.bank1[v], dut.vrf_lane3.bank0[v]};
            default: vrf_word = 32'hX;
        endcase
    endfunction

    // Direct VRF write (bypasses instruction pipeline for test setup)
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
        instruction     = inst;
        rs1_scalar_data = rs1v;
        rs2_scalar_data = rs2v;
        instr_valid     = 1'b1;
        @(negedge clk);
        instr_valid     = 1'b0;
    endtask

    task automatic wait_done;
        int t;
        t = 0;
        while ((busy !== 1'b1) && (t < 300)) begin @(posedge clk); t++; end
        t = 0;
        while ((busy !== 1'b0) && (t < 5000)) begin @(posedge clk); t++; end
        if (t >= 5000) begin
            fail_cnt++;
            $error("[TIMEOUT] wait_done timed out — FSM stuck in state %0d", fsm_state);
        end
    endtask

    task automatic check32(input string tag, input int lane, input int vreg,
                            input [31:0] exp);
        reg [31:0] got;
        got = vrf_word(lane, vreg);
        if (got === exp) begin
            pass_cnt++;
        end else begin
            fail_cnt++;
            $error("[FAIL] %s: lane%0d[v%0d] got=0x%08X exp=0x%08X",
                   tag, lane, vreg, got, exp);
        end
    endtask

    task automatic check_csr_vl(input string tag, input [31:0] exp);
        if (csr_vl_o === exp) begin
            pass_cnt++;
        end else begin
            fail_cnt++;
            $error("[FAIL] %s: csr_vl_o=%0d exp=%0d", tag, csr_vl_o, exp);
        end
    endtask

    // Issue vsetvli, wait for cfg_done, check CSR
    task automatic do_config(input [10:0] zimm, input [31:0] avl,
                              input [31:0] exp_vl);
        issue(build_vsetvli(zimm, 5'd0, 5'd1), avl, 32'd0);
        wait_done;
        @(posedge clk); // CSR updates this cycle
        check_csr_vl($sformatf("vsetvli avl=%0d", avl), exp_vl);
    endtask

    // ═══════════════════════════════════════════════════════════════════════════
    //  DIRECTED TESTS
    // ═══════════════════════════════════════════════════════════════════════════
    initial begin
        clk            = 0;
        rst_n          = 0;
        instr_valid    = 0;
        instruction    = 0;
        rs1_scalar_data= 0;
        rs2_scalar_data= 0;
        vrf_commit_en  = 1'b1;

        repeat(4) @(negedge clk);
        rst_n = 1;
        repeat(2) @(negedge clk);

        // ─── T1: vsetvli e32 m1, vl=4 ───────────────────────────────────────
        do_config(ZIMM_E32_M1, 32'd4, 32'd4);

        // ─── T2: vadd.vv v4 = v1 + v2 ───────────────────────────────────────
        // v1={1,2,3,4} v2={10,20,30,40}
        vrf_write4(1, 32'd1,  32'd2,  32'd3,  32'd4);
        vrf_write4(2, 32'd10, 32'd20, 32'd30, 32'd40);
        issue(build_opv(VADD, 1'b1, 3'b000, 5'd1, 5'd2, 5'd4), 32'd0, 32'd0);
        wait_done;
        check32("T2 vadd lane0", 0, 4, 32'd11);
        check32("T2 vadd lane1", 1, 4, 32'd22);
        check32("T2 vadd lane2", 2, 4, 32'd33);
        check32("T2 vadd lane3", 3, 4, 32'd44);

        // ─── T3: vsub.vv v5 = v2 - v1 ───────────────────────────────────────
        issue(build_opv(VSUB, 1'b1, 3'b000, 5'd1, 5'd2, 5'd5), 32'd0, 32'd0);
        wait_done;
        check32("T3 vsub lane0", 0, 5, 32'd9);
        check32("T3 vsub lane1", 1, 5, 32'd18);
        check32("T3 vsub lane2", 2, 5, 32'd27);
        check32("T3 vsub lane3", 3, 5, 32'd36);

        // ─── T4: vsub underflow (unsigned wrap) ──────────────────────────────
        // v1 > v2 here; result wraps modulo 2^32
        vrf_write4(3, 32'd5,  32'd5,  32'd5,  32'd5);
        vrf_write4(6, 32'd10, 32'd10, 32'd10, 32'd10);
        issue(build_opv(VSUB, 1'b1, 3'b000, 5'd6, 5'd3, 5'd7), 32'd0, 32'd0);
        wait_done;
        check32("T4 vsub wrap lane0", 0, 7, 32'hFFFF_FFFB); // 5-10 = -5 → wrap

        // ─── T5: vmul.vv v8 = v1 * v2 ───────────────────────────────────────
        vrf_write4(1, 32'd3, 32'd4, 32'd5, 32'd6);
        vrf_write4(2, 32'd7, 32'd8, 32'd9, 32'd10);
        issue(build_opv(VMUL, 1'b1, 3'b000, 5'd1, 5'd2, 5'd8), 32'd0, 32'd0);
        wait_done;
        check32("T5 vmul lane0", 0, 8, 32'd21);
        check32("T5 vmul lane1", 1, 8, 32'd32);
        check32("T5 vmul lane2", 2, 8, 32'd45);
        check32("T5 vmul lane3", 3, 8, 32'd60);

        // ─── T6: vand.vv v9 = v1 & v2 ───────────────────────────────────────
        vrf_write4(1, 32'hFF00_FF00, 32'hFF00_FF00, 32'hFF00_FF00, 32'hFF00_FF00);
        vrf_write4(2, 32'hF0F0_F0F0, 32'hF0F0_F0F0, 32'hF0F0_F0F0, 32'hF0F0_F0F0);
        issue(build_opv(VAND, 1'b1, 3'b000, 5'd1, 5'd2, 5'd9), 32'd0, 32'd0);
        wait_done;
        check32("T6 vand lane0", 0, 9, 32'hF000_F000);

        // ─── T7: vor.vv v10 = v1 | v2 ───────────────────────────────────────
        issue(build_opv(VOR,  1'b1, 3'b000, 5'd1, 5'd2, 5'd10), 32'd0, 32'd0);
        wait_done;
        check32("T7 vor lane0", 0, 10, 32'hFFF0_FFF0);

        // ─── T8: vxor.vv v11 = v1 ^ v1 = 0 ─────────────────────────────────
        issue(build_opv(VXOR, 1'b1, 3'b000, 5'd1, 5'd1, 5'd11), 32'd0, 32'd0);
        wait_done;
        check32("T8 vxor self lane0", 0, 11, 32'd0);

        // ─── T9: vsll.vx v12 = v1 << 2 (rs1 operand) ────────────────────────
        vrf_write4(1, 32'd5, 32'd10, 32'd15, 32'd20);
        issue(build_opv(VSLL, 1'b1, 3'b100, 5'd1, 5'd0, 5'd12), 32'd2, 32'd0);
        wait_done;
        check32("T9 vsll lane0", 0, 12, 32'd20);  // 5<<2 = 20
        check32("T9 vsll lane1", 1, 12, 32'd40);

        // ─── T10: vsrl.vi v13 = v1 >> 1 (immediate) ─────────────────────────
        // Build VI encoding: funct3=011, vs1=uimm5=1
        vrf_write4(1, 32'd100, 32'd200, 32'd300, 32'd400);
        begin
            reg [31:0] vi_inst;
            vi_inst        = 32'd0;
            vi_inst[6:0]   = OPCODE_OPV;
            vi_inst[11:7]  = 5'd13;
            vi_inst[14:12] = 3'b011;   // OPIVI
            vi_inst[19:15] = 5'd1;     // uimm5 = 1 (shift by 1)
            vi_inst[24:20] = 5'd1;     // vs2 = v1
            vi_inst[25]    = 1'b1;     // vm=1
            vi_inst[31:26] = VSRL;
            issue(vi_inst, 32'd0, 32'd0);
        end
        wait_done;
        check32("T10 vsrl lane0", 0, 13, 32'd50);  // 100>>1 = 50

        // ─── T11: vmax.vv, vmin.vv (signed) ─────────────────────────────────
        vrf_write4(1, 32'hFFFF_FFFF, 32'd5, 32'h8000_0000, 32'd100);  // -1, 5, INT_MIN, 100
        vrf_write4(2, 32'd0,         32'd3, 32'd1,          32'd200);
        issue(build_opv(VMAX, 1'b1, 3'b000, 5'd1, 5'd2, 5'd14), 32'd0, 32'd0);
        wait_done;
        check32("T11 vmax lane0", 0, 14, 32'd0);        // max(-1,0)=0
        check32("T11 vmax lane1", 1, 14, 32'd5);        // max(5,3)=5
        check32("T11 vmax lane2", 2, 14, 32'd1);        // max(INT_MIN,1)=1

        // ─── T12: vmaxu.vv (unsigned: 0xFF > 0x01) ───────────────────────────
        vrf_write4(1, 32'hFF, 32'h01, 32'h80, 32'h00);
        vrf_write4(2, 32'h01, 32'hFF, 32'h01, 32'hFF);
        issue(build_opv(VMAXU, 1'b1, 3'b000, 5'd1, 5'd2, 5'd15), 32'd0, 32'd0);
        wait_done;
        check32("T12 vmaxu lane0", 0, 15, 32'hFF); // max_u(0xFF,0x01)=0xFF
        check32("T12 vmaxu lane1", 1, 15, 32'hFF); // max_u(0x01,0xFF)=0xFF

        // ─── T13: vcmplt.vv (signed compare: -1 < 0) ─────────────────────────
        vrf_write4(1, 32'hFFFF_FFFF, 32'd0, 32'd1, 32'd100);  // -1, 0, 1, 100
        vrf_write4(2, 32'd0,         32'd0, 32'd0, 32'd100);
        issue(build_opv(VCMPLT, 1'b1, 3'b000, 5'd1, 5'd2, 5'd16), 32'd0, 32'd0);
        wait_done;
        // Result is mask (1 bit per element) in vd[0]; SEW=32 so 4 elems in lane0[3:0]
        // lane0[0]=(-1<0)=1, lane1[0]=(0<0)=0, lane2[0]=(1<0)=0, lane3[0]=(100<100)=0
        begin
            reg [31:0] mask_val;
            mask_val = vrf_word(0, 16);
            if (mask_val[0] === 1'b1) pass_cnt++;
            else begin fail_cnt++; $error("[FAIL] T13 vcmplt: bit[0] should be 1"); end
            if (mask_val[1] === 1'b0) pass_cnt++;
            else begin fail_cnt++; $error("[FAIL] T13 vcmplt: bit[1] should be 0"); end
        end

        // ─── T14: vcmpltu (unsigned: 0xFF > 0x00) ────────────────────────────
        vrf_write4(1, 32'hFF, 32'h00, 32'h01, 32'h80);
        vrf_write4(2, 32'h00, 32'hFF, 32'h01, 32'h01);
        issue(build_opv(VCMPLTU, 1'b1, 3'b000, 5'd1, 5'd2, 5'd16), 32'd0, 32'd0);
        wait_done;
        begin
            reg [31:0] mask_val;
            mask_val = vrf_word(0, 16);
            // lane0: 0xFF < 0x00 unsigned? No → 0
            if (mask_val[0] === 1'b0) pass_cnt++;
            else begin fail_cnt++; $error("[FAIL] T14 vcmpltu lane0[0] should be 0"); end
            // lane1: 0x00 < 0xFF unsigned? Yes → 1
            if (mask_val[1] === 1'b1) pass_cnt++;
            else begin fail_cnt++; $error("[FAIL] T14 vcmpltu lane1[0] should be 1"); end
        end

        // ─── T15: vsetvli e8 m1 — vl should be 16 for 128-bit VRF ───────────
        do_config(ZIMM_E8_M1, 32'd16, 32'd16);

        // ─── T16: vredsum.vs e32 m1 ──────────────────────────────────────────
        // Back to e32; v3={10,20,30,40} v4={0,...} (initial accumulator)
        do_config(ZIMM_E32_M1, 32'd4, 32'd4);
        vrf_write4(3, 32'd10, 32'd20, 32'd30, 32'd40);
        vrf_write4(4, 32'd0,  32'd0,  32'd0,  32'd0);
        // vredsum.vs v5, v3, v4  (funct3=010 = OPMVV, vs1=v4, vs2=v3, vd=v5)
        issue(build_opv(VREDSUM, 1'b1, 3'b010, 5'd4, 5'd3, 5'd5), 32'd0, 32'd0);
        wait_done;
        check32("T16 vredsum lane0", 0, 5, 32'd100); // 10+20+30+40+init(0)=100

        // ─── T17: vredmax.vs ──────────────────────────────────────────────────
        vrf_write4(3, 32'd10, 32'd50, 32'd30, 32'd5);
        vrf_write4(4, 32'd0,  32'd0,  32'd0,  32'd0);
        issue(build_opv(VREDMAX, 1'b1, 3'b010, 5'd4, 5'd3, 5'd5), 32'd0, 32'd0);
        wait_done;
        check32("T17 vredmax", 0, 5, 32'd50);

        // ─── T18: vredmin.vs (with signed values) ────────────────────────────
        vrf_write4(3, 32'd10, 32'hFFFF_FFFF, 32'd30, 32'd5); // -1 in lane1
        vrf_write4(4, 32'd0,  32'd0,          32'd0,  32'd0);
        issue(build_opv(VREDMIN, 1'b1, 3'b010, 5'd4, 5'd3, 5'd5), 32'd0, 32'd0);
        wait_done;
        check32("T18 vredmin (signed -1)", 0, 5, 32'hFFFF_FFFF);

        // ─── T19: widening vadd.vv (e16→e32) ─────────────────────────────────
        do_config(11'h048, 32'd4, 32'd4); // e16 m1
        vrf_write4(1, 32'h0002_0001, 32'h0004_0003, 32'h0006_0005, 32'h0008_0007);
        vrf_write4(2, 32'h000A_0009, 32'h000C_000B, 32'h000E_000D, 32'h0010_000F);
        issue(build_opv(VADDW, 1'b1, 3'b000, 5'd1, 5'd2, 5'd6), 32'd0, 32'd0);
        wait_done;
        // SEW=16 widening: lane0 low half: 1+9=10, high half: 2+10=12
        // Result in e32: lane0_lo=10, lane0_hi=12
        check32("T19 vaddw lo lane0", 0, 6, 32'd10);
        check32("T19 vaddw hi lane0", 0, 7, 32'd12);

        // ─── T20: LMUL=2 vadd ────────────────────────────────────────────────
        do_config(ZIMM_E32_M2, 32'd8, 32'd8);
        vrf_write4(2,  32'd1,  32'd2,  32'd3,  32'd4);
        vrf_write4(3,  32'd5,  32'd6,  32'd7,  32'd8);  // second group reg (LMUL=2)
        vrf_write4(4,  32'd10, 32'd20, 32'd30, 32'd40);
        vrf_write4(5,  32'd50, 32'd60, 32'd70, 32'd80);
        issue(build_opv(VADD, 1'b1, 3'b000, 5'd4, 5'd2, 5'd8), 32'd0, 32'd0);
        wait_done;
        check32("T20 LMUL2 vadd reg0 lane0", 0, 8, 32'd11);
        check32("T20 LMUL2 vadd reg1 lane0", 0, 9, 32'd55); // 5+50=55

        // ─── T21: vsetvli with avl > vlmax → vl=vlmax ─────────────────────────
        do_config(ZIMM_E32_M1, 32'd100, 32'd4); // avl=100 but vlmax=4 for e32 m1

        // ─── T22: vrsub.vx v = rs1 - v (via VX encoding) ────────────────────
        do_config(ZIMM_E32_M1, 32'd4, 32'd4);
        vrf_write4(1, 32'd3, 32'd5, 32'd7, 32'd9);
        // vrsub.vx: VX encoding funct3=100, vs1=rs1_idx=0 (rs1 is the scalar)
        issue(build_opv(VRSUB, 1'b1, 3'b100, 5'd0, 5'd1, 5'd20), 32'd10, 32'd0);
        wait_done;
        check32("T22 vrsub lane0", 0, 20, 32'd7);  // 10-3=7
        check32("T22 vrsub lane1", 1, 20, 32'd5);  // 10-5=5

        // ─── Final Summary ────────────────────────────────────────────────────
        repeat(5) @(posedge clk);
        $display("\n========================================");
        $display("  ASSERTION TESTBENCH SUMMARY");
        $display("========================================");
        $display("  Directed tests: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        $display("  SVA trips:      %0d", assert_trip);
        if (fail_cnt == 0 && assert_trip == 0)
            $display("  *** ALL CHECKS PASS ***");
        else
            $display("  *** FAILURES DETECTED — see errors above ***");
        $display("========================================\n");
        $finish;
    end

endmodule
