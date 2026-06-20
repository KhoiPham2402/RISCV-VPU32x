`timescale 1ns / 1ps
// =============================================================================
// tb_wave_vpu_debug.sv — "Embedded Engineer" waveform debug testbench
//
// Mục đích: Debug VPU bằng cách nhìn waveform trực tiếp, không cần kiến thức
//           sâu về nội bộ. Mỗi transaction hiện rõ:
//
//   [OP_NAME] vs2[lane0..3] OP vs1[lane0..3] → vd[lane0..3]   (VRF writeback)
//
// Sequence test:
//   1. vsetvli e32 m1 vl=4   — 4 phần tử, SEW=32-bit
//   2. vadd.vv v2, v7, v9    — v2[i] = v7[i] + v9[i]
//   3. vsub.vv v3, v7, v9    — v3[i] = v7[i] - v9[i]
//   4. vmul.vv v4, v7, v9    — v4[i] = v7[i] * v9[i]
//   5. vadd.vx v5, v7, rs1   — v5[i] = v7[i] + scalar
//   6. vsetvli e8 m1 vl=16   — chuyển sang SEW=8-bit (multi-cycle)
//   7. vadd.vv v2, v7, v9    — cùng lệnh, SEW=8 → 4 execution cycles
//
// Chạy: vsim -do run_wave_vpu_debug.do
// =============================================================================

module tb_wave_vpu_debug;

    // ── Opcode / funct6 constants ──────────────────────────────────────────────
    localparam [6:0] OPCODE_OPV  = 7'b101_0111;
    localparam [5:0] F6_VADD     = 6'h00;
    localparam [5:0] F6_VSUB     = 6'h02;
    localparam [5:0] F6_VMUL     = 6'h25;
    localparam [5:0] F6_VAND     = 6'h09;
    localparam [5:0] F6_VOR      = 6'h0A;
    localparam [5:0] F6_VXOR     = 6'h0B;
    localparam [5:0] F6_VSLL     = 6'h15;
    localparam [5:0] F6_VSRL     = 6'h10;
    localparam [5:0] F6_VSRA     = 6'h12;
    localparam [5:0] F6_VREDSUM  = 6'h00;  // RVV 1.0: funct6=000000, funct3=010 (OPMVV)

    // vsetvli zimm: e32m1 ta ma = 11'h0D0, e8m1 ta ma = 11'h040
    localparam [10:0] ZIMM_E32_M1 = 11'h0D0;
    localparam [10:0] ZIMM_E8_M1  = 11'h040;

    // ── Signals ────────────────────────────────────────────────────────────────
    reg         clk, rst_n, instr_valid, vrf_commit_en;
    reg [31:0]  instruction, rs1_scalar_data, rs2_scalar_data;

    wire [3:0]  cycles, fsm_state;
    wire [15:0] vmask16;
    wire        fifo_full, busy, vpu_ready, vpu_cfg_done;
    wire [31:0] wb_result_lane0, wb_result_lane1, wb_result_lane2, wb_result_lane3;
    wire [31:0] vpu_vl_remain, csr_vl_o, csr_vtype_o, csr_vlenb_o;
    wire [31:0] scalar_csr_rdata;
    wire        vlsu_mem_req, vlsu_mem_we, vlsu_busy_o;
    wire [31:0] vlsu_mem_addr, vlsu_mem_wdata;
    wire [3:0]  vlsu_mem_be;

    wire [11:0] scalar_csr_addr_tie;
    assign scalar_csr_addr_tie = 12'h000;

    // ── "Instruction label" register — hiện rõ trên waveform ──────────────────
    // 10 ký tự ASCII (80 bit) — ModelSim hiển thị như chuỗi text trong wave.
    reg [79:0] instr_label;

    // ── DUT ───────────────────────────────────────────────────────────────────
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
        .scalar_csr_addr  (scalar_csr_addr_tie),
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

    // ── Build helpers ──────────────────────────────────────────────────────────
    function automatic [31:0] build_opv_vv(
        input [5:0] f6,
        input [4:0] vd, vs2, vs1
    );
        // OPIVV: vm=1 (unmasked), funct3=000
        build_opv_vv        = 32'd0;
        build_opv_vv[6:0]   = OPCODE_OPV;
        build_opv_vv[11:7]  = vd;
        build_opv_vv[14:12] = 3'b000;   // OPIVV
        build_opv_vv[19:15] = vs1;
        build_opv_vv[24:20] = vs2;
        build_opv_vv[25]    = 1'b1;     // vm=1: unmasked
        build_opv_vv[31:26] = f6;
    endfunction

    // OPMVV builder for instructions using funct3=010 (reductions, vmul.vv, etc.)
    function automatic [31:0] build_opv_mvv(
        input [5:0] f6,
        input [4:0] vd, vs2, vs1
    );
        build_opv_mvv        = 32'd0;
        build_opv_mvv[6:0]   = OPCODE_OPV;
        build_opv_mvv[11:7]  = vd;
        build_opv_mvv[14:12] = 3'b010;   // OPMVV — distinguishes reductions from vadd/vsub
        build_opv_mvv[19:15] = vs1;
        build_opv_mvv[24:20] = vs2;
        build_opv_mvv[25]    = 1'b1;     // vm=1: unmasked
        build_opv_mvv[31:26] = f6;
    endfunction

    function automatic [31:0] build_opv_vx(
        input [5:0] f6,
        input [4:0] vd, vs2, rs1_idx
    );
        // OPIVX: vm=1, funct3=100
        build_opv_vx        = 32'd0;
        build_opv_vx[6:0]   = OPCODE_OPV;
        build_opv_vx[11:7]  = vd;
        build_opv_vx[14:12] = 3'b100;   // OPIVX
        build_opv_vx[19:15] = rs1_idx;
        build_opv_vx[24:20] = vs2;
        build_opv_vx[25]    = 1'b1;
        build_opv_vx[31:26] = f6;
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

    // ── Direct VRF access (bypass instruction pipeline) ───────────────────────
    // Đọc full 128-bit của một vector register (4 lanes × 32-bit)
    function automatic [31:0] vrf_read(input int lane, input int vreg);
        case (lane)
            0: vrf_read = {dut.vrf_lane0.bank3[vreg], dut.vrf_lane0.bank2[vreg],
                           dut.vrf_lane0.bank1[vreg], dut.vrf_lane0.bank0[vreg]};
            1: vrf_read = {dut.vrf_lane1.bank3[vreg], dut.vrf_lane1.bank2[vreg],
                           dut.vrf_lane1.bank1[vreg], dut.vrf_lane1.bank0[vreg]};
            2: vrf_read = {dut.vrf_lane2.bank3[vreg], dut.vrf_lane2.bank2[vreg],
                           dut.vrf_lane2.bank1[vreg], dut.vrf_lane2.bank0[vreg]};
            3: vrf_read = {dut.vrf_lane3.bank3[vreg], dut.vrf_lane3.bank2[vreg],
                           dut.vrf_lane3.bank1[vreg], dut.vrf_lane3.bank0[vreg]};
            default: vrf_read = 32'hDEAD_BEEF;
        endcase
    endfunction

    // Ghi trực tiếp vào VRF (dùng để preload data)
    task automatic vrf_preload(
        input int vreg,
        input [31:0] e0, e1, e2, e3  // e0=lane0, e1=lane1, e2=lane2, e3=lane3
    );
        {dut.vrf_lane0.bank3[vreg], dut.vrf_lane0.bank2[vreg],
         dut.vrf_lane0.bank1[vreg], dut.vrf_lane0.bank0[vreg]} = e0;
        {dut.vrf_lane1.bank3[vreg], dut.vrf_lane1.bank2[vreg],
         dut.vrf_lane1.bank1[vreg], dut.vrf_lane1.bank0[vreg]} = e1;
        {dut.vrf_lane2.bank3[vreg], dut.vrf_lane2.bank2[vreg],
         dut.vrf_lane2.bank1[vreg], dut.vrf_lane2.bank0[vreg]} = e2;
        {dut.vrf_lane3.bank3[vreg], dut.vrf_lane3.bank2[vreg],
         dut.vrf_lane3.bank1[vreg], dut.vrf_lane3.bank0[vreg]} = e3;
    endtask

    // Issue một instruction (giữ valid 1 cycle)
    task automatic issue_instr(input [31:0] inst, input [31:0] rs1v, rs2v);
        @(negedge clk);
        instruction     = inst;
        rs1_scalar_data = rs1v;
        rs2_scalar_data = rs2v;
        instr_valid     = 1'b1;
        @(negedge clk);
        instr_valid     = 1'b0;
    endtask

    // Chờ VPU xử lý xong (busy pulse hoàn tất)
    task automatic wait_done;
        int timeout;
        timeout = 0;
        // Chờ busy lên (có thể đã lên rồi)
        while ((dut.busy !== 1'b1) && (timeout < 100)) begin
            @(posedge clk); timeout++;
        end
        // Chờ busy xuống
        timeout = 0;
        while ((dut.busy !== 1'b0) && (timeout < 5000)) begin
            @(posedge clk); timeout++;
        end
        @(posedge clk);  // thêm 1 cycle buffer
    endtask

    // ── Print VRF contents ─────────────────────────────────────────────────────
    // Hiển thị toàn bộ 128-bit của một vector register (4 phần tử e32)
    task automatic print_vreg_e32(input int vreg, input string name);
        $display("  %s[v%0d] = {e0=0x%08X, e1=0x%08X, e2=0x%08X, e3=0x%08X}",
                 name, vreg,
                 vrf_read(0, vreg), vrf_read(1, vreg),
                 vrf_read(2, vreg), vrf_read(3, vreg));
    endtask

    // Hiển thị 16 phần tử e8 (4 bytes mỗi lane)
    task automatic print_vreg_e8(input int vreg, input string name);
        logic [31:0] l0, l1, l2, l3;
        l0 = vrf_read(0, vreg);
        l1 = vrf_read(1, vreg);
        l2 = vrf_read(2, vreg);
        l3 = vrf_read(3, vreg);
        $display("  %s[v%0d] e8 = {%02X %02X %02X %02X | %02X %02X %02X %02X | %02X %02X %02X %02X | %02X %02X %02X %02X}",
                 name, vreg,
                 l0[7:0],  l0[15:8],  l0[23:16], l0[31:24],
                 l1[7:0],  l1[15:8],  l1[23:16], l1[31:24],
                 l2[7:0],  l2[15:8],  l2[23:16], l2[31:24],
                 l3[7:0],  l3[15:8],  l3[23:16], l3[31:24]);
    endtask

    // ── Check helper ───────────────────────────────────────────────────────────
    integer pass_cnt, fail_cnt;

    task automatic check_e32(
        input int vd_reg,
        input [31:0] exp_e0, exp_e1, exp_e2, exp_e3,
        input string op_name
    );
        logic [31:0] got0, got1, got2, got3;
        got0 = vrf_read(0, vd_reg);
        got1 = vrf_read(1, vd_reg);
        got2 = vrf_read(2, vd_reg);
        got3 = vrf_read(3, vd_reg);
        if (got0 === exp_e0 && got1 === exp_e1 && got2 === exp_e2 && got3 === exp_e3) begin
            $display("  ✓ PASS  %s  vd=v%0d {0x%08X 0x%08X 0x%08X 0x%08X}",
                     op_name, vd_reg, got0, got1, got2, got3);
            pass_cnt++;
        end else begin
            $display("  ✗ FAIL  %s  vd=v%0d", op_name, vd_reg);
            $display("         got : {0x%08X 0x%08X 0x%08X 0x%08X}", got0, got1, got2, got3);
            $display("         exp : {0x%08X 0x%08X 0x%08X 0x%08X}", exp_e0, exp_e1, exp_e2, exp_e3);
            fail_cnt++;
        end
    endtask

    // ==========================================================================
    // MAIN TEST
    // ==========================================================================
    initial begin
        // Khởi tạo
        clk           = 0;
        rst_n         = 0;
        instr_valid   = 0;
        instruction   = 0;
        rs1_scalar_data = 0;
        rs2_scalar_data = 0;
        vrf_commit_en = 1;
        instr_label   = "RESET     ";  // 10 ký tự
        pass_cnt      = 0;
        fail_cnt      = 0;

        repeat(4) @(negedge clk);
        rst_n = 1;
        repeat(2) @(negedge clk);

        // ======================================================================
        // PHASE 1: SEW=32, vl=4 — 4 phần tử 32-bit, 1 cycle/instruction
        // ======================================================================
        $display("\n============================================================");
        $display(" PHASE 1: SEW=e32, LMUL=m1, vl=4");
        $display("============================================================");

        // ── Cấu hình: vsetvli t0, t0, e32, m1, ta, ma (avl=4) ────────────────
        instr_label = "vsetvli   ";
        $display("\n[STEP 1] vsetvli e32 m1 avl=4");
        issue_instr(build_vsetvli(ZIMM_E32_M1, 5'd1, 5'd1), 32'd4, 32'd0);
        wait_done;
        $display("  CSR vl=%0d  vtype=0x%08X", csr_vl_o, csr_vtype_o);

        // ── Preload vector registers ───────────────────────────────────────────
        // v7 = {10, 20, 30, 40}  (element 0..3)
        // v9 = { 1,  2,  3,  4}
        vrf_preload(7,  32'd10, 32'd20, 32'd30, 32'd40);
        vrf_preload(9,  32'd1,  32'd2,  32'd3,  32'd4);
        $display("\n[PRELOAD]");
        print_vreg_e32(7, "v7 (operand A)");
        print_vreg_e32(9, "v9 (operand B)");

        // ── vadd.vv v2, v7, v9 ────────────────────────────────────────────────
        // v2[i] = v7[i] + v9[i]  →  {11, 22, 33, 44}
        instr_label = "vadd.vv   ";
        $display("\n[STEP 2] vadd.vv v2, v7, v9");
        $display("  → Kỳ vọng v2 = {11, 22, 33, 44}");
        issue_instr(build_opv_vv(F6_VADD, 5'd2, 5'd7, 5'd9), 32'd0, 32'd0);
        wait_done;
        print_vreg_e32(2, "v2 (result)");
        check_e32(2, 32'd11, 32'd22, 32'd33, 32'd44, "vadd.vv v2,v7,v9");

        // ── vsub.vv v3, v7, v9 ────────────────────────────────────────────────
        // v3[i] = v7[i] - v9[i]  →  {9, 18, 27, 36}
        instr_label = "vsub.vv   ";
        $display("\n[STEP 3] vsub.vv v3, v7, v9");
        $display("  → Kỳ vọng v3 = {9, 18, 27, 36}");
        issue_instr(build_opv_vv(F6_VSUB, 5'd3, 5'd7, 5'd9), 32'd0, 32'd0);
        wait_done;
        print_vreg_e32(3, "v3 (result)");
        check_e32(3, 32'd9, 32'd18, 32'd27, 32'd36, "vsub.vv v3,v7,v9");

        // ── vmul.vv v4, v7, v9 ────────────────────────────────────────────────
        // v4[i] = v7[i] * v9[i]  →  {10, 40, 90, 160}
        instr_label = "vmul.vv   ";
        $display("\n[STEP 4] vmul.vv v4, v7, v9");
        $display("  → Kỳ vọng v4 = {10, 40, 90, 160}");
        issue_instr(build_opv_vv(F6_VMUL, 5'd4, 5'd7, 5'd9), 32'd0, 32'd0);
        wait_done;
        print_vreg_e32(4, "v4 (result)");
        check_e32(4, 32'd10, 32'd40, 32'd90, 32'd160, "vmul.vv v4,v7,v9");

        // ── vadd.vx v5, v7, rs1=100 ───────────────────────────────────────────
        // v5[i] = v7[i] + 100  →  {110, 120, 130, 140}
        instr_label = "vadd.vx   ";
        $display("\n[STEP 5] vadd.vx v5, v7, rs1=100 (scalar)");
        $display("  → Kỳ vọng v5 = {110, 120, 130, 140}");
        issue_instr(build_opv_vx(F6_VADD, 5'd5, 5'd7, 5'd1), 32'd100, 32'd0);
        wait_done;
        print_vreg_e32(5, "v5 (result)");
        check_e32(5, 32'd110, 32'd120, 32'd130, 32'd140, "vadd.vx v5,v7,rs1=100");

        // ── vxor.vv v6, v7, v9 ───────────────────────────────────────────────
        // v6[i] = v7[i] ^ v9[i]  →  {10^1, 20^2, 30^3, 40^4} = {11, 22, 29, 44}
        instr_label = "vxor.vv   ";
        $display("\n[STEP 6] vxor.vv v6, v7, v9");
        $display("  → Kỳ vọng v6 = {0x0B, 0x16, 0x1D, 0x2C}");
        issue_instr(build_opv_vv(F6_VXOR, 5'd6, 5'd7, 5'd9), 32'd0, 32'd0);
        wait_done;
        print_vreg_e32(6, "v6 (result)");
        check_e32(6, 32'h0B, 32'h16, 32'h1D, 32'h2C, "vxor.vv v6,v7,v9");

        // ======================================================================
        // PHASE 2: SEW=8, vl=16 — 16 phần tử 8-bit, 4 cycles/instruction
        // ======================================================================
        $display("\n============================================================");
        $display(" PHASE 2: SEW=e8, LMUL=m1, vl=16 — xem multi-cycle execution");
        $display("============================================================");

        // ── Cấu hình: vsetvli e8 m1 avl=16 ───────────────────────────────────
        instr_label = "vsetvli   ";
        $display("\n[STEP 7] vsetvli e8 m1 avl=16");
        issue_instr(build_vsetvli(ZIMM_E8_M1, 5'd1, 5'd1), 32'd16, 32'd0);
        wait_done;
        $display("  CSR vl=%0d  vtype=0x%08X", csr_vl_o, csr_vtype_o);

        // Preload v7, v9 với 16 phần tử 8-bit
        // Mỗi lane chứa 4 bytes (4 phần tử)
        // v7 = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        //       0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10]
        // v9 = [0x10, 0x10, 0x10, 0x10, ...]  (tất cả = 0x10)
        vrf_preload(7, 32'h04030201, 32'h08070605, 32'h0C0B0A09, 32'h100F0E0D);
        vrf_preload(9, 32'h10101010, 32'h10101010, 32'h10101010, 32'h10101010);
        $display("\n[PRELOAD e8]");
        print_vreg_e8(7, "v7");
        print_vreg_e8(9, "v9");

        // ── vadd.vv v2, v7, v9 (SEW=8) ───────────────────────────────────────
        // v2[i] = v7[i] + 0x10  →  [0x11,0x12,...,0x20]
        instr_label = "vadd.vv e8";
        $display("\n[STEP 8] vadd.vv v2, v7, v9  (SEW=8, 16 elements, 4 cycles)");
        $display("  → Kỳ vọng v2 = [0x11, 0x12, 0x13, ..., 0x20]");
        issue_instr(build_opv_vv(F6_VADD, 5'd2, 5'd7, 5'd9), 32'd0, 32'd0);
        wait_done;
        print_vreg_e8(2, "v2");

        // ======================================================================
        // PHASE 3: Reduction (vredsum)
        // ======================================================================
        $display("\n============================================================");
        $display(" PHASE 3: VREDSUM — sum reduction");
        $display("============================================================");

        // Reset về e32, vl=4
        instr_label = "vsetvli   ";
        issue_instr(build_vsetvli(ZIMM_E32_M1, 5'd1, 5'd1), 32'd4, 32'd0);
        wait_done;

        // v8 = {10, 20, 30, 40}  → sum = 100
        // v10 = {0, 0, 0, 0}     → initial value (vs1 = v[0] của vs1)
        vrf_preload(8,  32'd10, 32'd20, 32'd30, 32'd40);
        vrf_preload(10, 32'd0,  32'd0,  32'd0,  32'd0);
        $display("\n[PRELOAD]");
        print_vreg_e32(8,  "v8  (input)");
        print_vreg_e32(10, "v10 (init)");

        // vredsum.vs v11, v8, v10
        // RVV 1.0: OPMVV (funct3=010), funct6=0x00, vd=v11, vs2=v8, vs1=v10
        // Result = vs1[0] + sum(vs2) = v10[0] + (10+20+30+40) = 0 + 100 = 100
        instr_label = "vredsum   ";
        $display("\n[STEP 9] vredsum.vs v11, v8, v10");
        $display("  → Kỳ vọng v11[e0] = v10[0] + sum(v8) = 0 + 100 = 100");
        issue_instr(build_opv_mvv(F6_VREDSUM, 5'd11, 5'd8, 5'd10), 32'd0, 32'd0);
        wait_done;
        print_vreg_e32(11, "v11 (result)");
        check_e32(11, 32'd100, 32'd0, 32'd0, 32'd0, "vredsum.vs v11,v8,v10");

        // ======================================================================
        // SUMMARY
        // ======================================================================
        repeat(10) @(posedge clk);
        instr_label = "DONE      ";
        $display("\n============================================================");
        $display(" TEST SUMMARY: PASS=%0d  FAIL=%0d  TOTAL=%0d",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0)
            $display(" → ALL PASS ✓");
        else
            $display(" → SOME FAILED — kiểm tra waveform các signal bên dưới");
        $display("============================================================\n");
        $finish;
    end

    // ── Cycle-by-cycle monitor (in-sim printout cho debug) ────────────────────
    // Mỗi khi VRF writeback xảy ra, in ra trên console
    always @(posedge clk) begin
        if (dut.fsm_vrf_wren && vrf_commit_en && !dut.final_masking_commit) begin
            $display("  [WB @%0t] vd=v%0d  lane0=0x%08X  lane1=0x%08X  lane2=0x%08X  lane3=0x%08X  we={%b%b%b%b}",
                     $time,
                     dut.vd_addr_eff,
                     dut.vrf_wdata0_eff, dut.vrf_wdata1_eff,
                     dut.vrf_wdata2_eff, dut.vrf_wdata3_eff,
                     dut.vrf_we3_eff[0], dut.vrf_we2_eff[0],
                     dut.vrf_we1_eff[0], dut.vrf_we0_eff[0]);
        end
    end

endmodule
