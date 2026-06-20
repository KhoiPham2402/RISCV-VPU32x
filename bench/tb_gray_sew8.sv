`timescale 1ns / 1ps
// =============================================================================
// tb_gray_sew8.sv — BT.601 grayscale computation smoke test (SEW=8)
//
// Verifies: vsetvli e8 m1 → vmulhu.vx ×3 → vadd.vv ×2
//   Y = floor(R×77/256) + floor(G×150/256) + floor(B×29/256)
//
// Two scenarios:
//   1. R=G=B=100  →  Y = 30+58+11 = 99  (0x63)
//   2. R=G=B=255  →  Y = 76+149+28 = 253 (0xFD, NOT 0xFF!)
//
// If either scenario gives 0xFF → vmulhu.vx SEW=8 is BROKEN.
//
// Run: vsim -do vproc_all_instr.do (reuses its compile list)
// or:  vsim -novopt work.tb_gray_sew8 after compiling manually.
// =============================================================================
module tb_gray_sew8;

    localparam [6:0] OPCODE_OPV = 7'b101_0111;

    // vsetvli zimm: e8 m1 ta ma = {vma=1,vta=1,vsew=000,vlmul=000} = 0xC0
    localparam [10:0] ZIMM_E8_M1  = 11'h0C0;

    localparam [5:0] VMULHU = 6'h24;
    localparam [5:0] VADD   = 6'h00;

    // ── DUT signals ───────────────────────────────────────────────────────────
    reg        clk = 0;
    reg        rst_n;
    reg        instr_valid;
    reg [31:0] instruction;
    reg [31:0] rs1_scalar_data;
    reg [31:0] rs2_scalar_data;
    reg        vrf_commit_en;

    wire        busy, vpu_ready, vpu_cfg_done;
    wire [3:0]  fsm_state;
    wire [31:0] wb0, wb1, wb2, wb3;
    wire [31:0] vpu_vl_remain;
    wire        vlsu_mem_req, vlsu_mem_we;
    wire [31:0] vlsu_mem_addr, vlsu_mem_wdata;
    wire [3:0]  vlsu_mem_be;
    wire        vlsu_busy_o;

    integer pass_cnt = 0, fail_cnt = 0;

    vproc_system_wrapper dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .instr_valid      (instr_valid),
        .instruction      (instruction),
        .rs1_scalar_data  (rs1_scalar_data),
        .rs2_scalar_data  (rs2_scalar_data),
        .vrf_commit_en    (vrf_commit_en),
        .cycles           (),
        .vmask16          (),
        .fifo_full        (),
        .busy             (busy),
        .fsm_state        (fsm_state),
        .wb_result_lane0  (wb0),
        .wb_result_lane1  (wb1),
        .wb_result_lane2  (wb2),
        .wb_result_lane3  (wb3),
        .vpu_ready        (vpu_ready),
        .vpu_cfg_done     (vpu_cfg_done),
        .vpu_vl_remain    (vpu_vl_remain),
        .csr_vl_o         (),
        .csr_vtype_o      (),
        .csr_vlenb_o      (),
        .scalar_csr_addr  (12'h0),
        .scalar_csr_rdata (),
        .vlsu_mem_req     (vlsu_mem_req),
        .vlsu_mem_we      (vlsu_mem_we),
        .vlsu_mem_addr    (vlsu_mem_addr),
        .vlsu_mem_be      (vlsu_mem_be),
        .vlsu_mem_wdata   (vlsu_mem_wdata),
        .vlsu_mem_rdata   (32'd0),
        .vlsu_busy_o      (vlsu_busy_o)
    );

    always #5 clk = ~clk;

    // ── Instruction helpers ───────────────────────────────────────────────────
    function automatic [31:0] build_opv(
        input [5:0] f6, input vm,
        input [2:0] f3,
        input [4:0] vs1, vs2, vd
    );
        build_opv = {f6, vm, vs2, vs1, f3, vd, OPCODE_OPV};
    endfunction

    function automatic [31:0] build_vsetvli(
        input [10:0] zimm, input [4:0] vd, rs1_idx
    );
        build_vsetvli = {1'b0, zimm, rs1_idx, 3'b111, vd, OPCODE_OPV};
    endfunction

    // Direct VRF helpers (hierarchical)
    function automatic [31:0] vrf_rd(input int lane, v);
        case (lane)
            0: vrf_rd = {dut.vrf_lane0.bank3[v], dut.vrf_lane0.bank2[v],
                         dut.vrf_lane0.bank1[v], dut.vrf_lane0.bank0[v]};
            1: vrf_rd = {dut.vrf_lane1.bank3[v], dut.vrf_lane1.bank2[v],
                         dut.vrf_lane1.bank1[v], dut.vrf_lane1.bank0[v]};
            2: vrf_rd = {dut.vrf_lane2.bank3[v], dut.vrf_lane2.bank2[v],
                         dut.vrf_lane2.bank1[v], dut.vrf_lane2.bank0[v]};
            3: vrf_rd = {dut.vrf_lane3.bank3[v], dut.vrf_lane3.bank2[v],
                         dut.vrf_lane3.bank1[v], dut.vrf_lane3.bank0[v]};
            default: vrf_rd = 32'h0;
        endcase
    endfunction

    task automatic vrf_wr(input int v,
                          input [31:0] w0, w1, w2, w3);
        {dut.vrf_lane0.bank3[v],dut.vrf_lane0.bank2[v],
         dut.vrf_lane0.bank1[v],dut.vrf_lane0.bank0[v]} = w0;
        {dut.vrf_lane1.bank3[v],dut.vrf_lane1.bank2[v],
         dut.vrf_lane1.bank1[v],dut.vrf_lane1.bank0[v]} = w1;
        {dut.vrf_lane2.bank3[v],dut.vrf_lane2.bank2[v],
         dut.vrf_lane2.bank1[v],dut.vrf_lane2.bank0[v]} = w2;
        {dut.vrf_lane3.bank3[v],dut.vrf_lane3.bank2[v],
         dut.vrf_lane3.bank1[v],dut.vrf_lane3.bank0[v]} = w3;
    endtask

    task automatic issue(input [31:0] inst, rs1v, rs2v);
        @(negedge clk);
        instruction = inst; rs1_scalar_data = rs1v; rs2_scalar_data = rs2v;
        instr_valid = 1'b1;
        @(negedge clk);
        instr_valid = 1'b0;
    endtask

    task automatic wait_done;
        int t = 0;
        while (busy !== 1'b1 && t < 300) begin @(posedge clk); t++; end
        t = 0;
        while (busy !== 1'b0 && t < 5000) begin @(posedge clk); t++; end
        if (t >= 5000) $display("  *** TIMEOUT ***");
    endtask

    task automatic check(input string tag, input [31:0] got, exp);
        if (got === exp) begin
            pass_cnt++;
            $display("[PASS] %s", tag);
        end else begin
            fail_cnt++;
            $display("[FAIL] %s | got=%08h exp=%08h", tag, got, exp);
        end
    endtask

    // ── Run one grayscale scenario ────────────────────────────────────────────
    // pix8 = 8-bit uniform pixel value for R=G=B
    // Loads 16 identical pixels, computes Y, checks against expected_y8.
    task automatic run_gray(input [7:0] pix8, input [7:0] exp_y8);
        automatic logic [31:0] px32   = {pix8, pix8, pix8, pix8};  // 4 pixels/word
        automatic logic [31:0] e_yr32;  // expected R contribution × 4
        automatic logic [31:0] e_yg32;  // G contribution
        automatic logic [31:0] e_yb32;  // B contribution
        automatic logic [31:0] e_y32;   // final Y
        automatic logic [7:0]  yr8, yg8, yb8;

        // Expected intermediate results
        yr8   = (pix8 * 8'd77) >> 8;    // floor(pix×77/256)
        yg8   = (pix8 * 8'd150) >> 8;
        yb8   = (pix8 * 8'd29) >> 8;
        e_yr32 = {yr8, yr8, yr8, yr8};
        e_yg32 = {yg8, yg8, yg8, yg8};
        e_yb32 = {yb8, yb8, yb8, yb8};
        e_y32  = {exp_y8, exp_y8, exp_y8, exp_y8};

        $display("--- gray test: pix=0x%02X exp_Y=0x%02X (dec %0d) ---", pix8, exp_y8, exp_y8);

        // Write R, G, B to v1, v2, v3 (16 identical pixels each)
        vrf_wr(1, px32, px32, px32, px32);
        vrf_wr(2, px32, px32, px32, px32);
        vrf_wr(3, px32, px32, px32, px32);

        // vsetvli e8 m1 ta ma   (rd=x1, rs1=x1 → vl=16)
        issue(build_vsetvli(ZIMM_E8_M1, 5'd1, 5'd1), 32'd16, 32'd0);
        wait_done();

        // vmulhu.vx v4, v1, {77}   → v4 = floor(R×77/256)
        issue(build_opv(VMULHU, 1'b1, 3'b110, 5'd1, 5'd1, 5'd4), 32'd77, 32'd0);
        wait_done();
        check($sformatf("vmulhu R×77  [pix=%0d]", pix8), vrf_rd(0,4), e_yr32);

        // vmulhu.vx v5, v2, {150}  → v5 = floor(G×150/256)
        issue(build_opv(VMULHU, 1'b1, 3'b110, 5'd1, 5'd2, 5'd5), 32'd150, 32'd0);
        wait_done();
        check($sformatf("vmulhu G×150 [pix=%0d]", pix8), vrf_rd(0,5), e_yg32);

        // vmulhu.vx v6, v3, {29}   → v6 = floor(B×29/256)
        issue(build_opv(VMULHU, 1'b1, 3'b110, 5'd1, 5'd3, 5'd6), 32'd29, 32'd0);
        wait_done();
        check($sformatf("vmulhu B×29  [pix=%0d]", pix8), vrf_rd(0,6), e_yb32);

        // vadd.vv v7, v4, v5
        issue(build_opv(VADD, 1'b1, 3'b000, 5'd4, 5'd5, 5'd7), 32'd0, 32'd0);
        wait_done();

        // vadd.vv v7, v7, v6  →  v7 = Y
        issue(build_opv(VADD, 1'b1, 3'b000, 5'd7, 5'd6, 5'd7), 32'd0, 32'd0);
        wait_done();

        check($sformatf("Y=R+G+B      [pix=%0d]", pix8), vrf_rd(0,7), e_y32);
    endtask

    // ── Main ──────────────────────────────────────────────────────────────────
    initial begin
        clk = 0; rst_n = 0; instr_valid = 0; vrf_commit_en = 1;
        instruction = 0; rs1_scalar_data = 0; rs2_scalar_data = 0;

        repeat (20) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // ── Scenario 1: uniform pixel = 100 ─────────────────────────────────
        // floor(100×77/256)=30, floor(100×150/256)=58, floor(100×29/256)=11 → Y=99
        run_gray(8'd100, 8'd99);

        // ── Scenario 2: uniform pixel = 255 (max Lena) ──────────────────────
        // floor(255×77/256)=76, floor(255×150/256)=149, floor(255×29/256)=28 → Y=253
        // NOTE: 253 ≠ 255. If VPU gives 0xFF here → vmulhu uses LOW half (bug).
        run_gray(8'd255, 8'd253);

        // ── Scenario 3: uniform pixel = 0 ───────────────────────────────────
        run_gray(8'd0, 8'd0);

        $display("");
        $display("=== GRAY SEW=8 RESULT: %0d PASS / %0d FAIL ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("[PASS] Computation correct — white screen is in a DIFFERENT path.");
        else
            $display("[FAIL] Computation BUG found — this explains the white screen.");

        $finish;
    end

endmodule
