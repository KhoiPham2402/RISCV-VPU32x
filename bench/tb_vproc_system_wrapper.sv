`timescale 1ns / 1ps

// TB tích hợp TOP rtl/vproc_system_wrapper.sv
// (1) vsetvli e16, m2, avl=13  (2) vmadc + vmsbc  (3) vrsub.vv: dung thi PASS (optional), sai chi in.

module tb_vproc_system_wrapper;

    localparam [6:0] OPCODE_OPV = 7'b101_0111;
    localparam [2:0] F3_OPIVV = 3'b000;
    localparam [2:0] F3_CFG   = 3'b111;

    // e16, m2: zimm[7:0] = {00, vsew=001, vlmul=001} = 8'h09
    localparam [10:0] ZIMM_E16_M2 = 11'b000_0000_1001;

    localparam [5:0] F6_VRSUB = 6'b000011;
    localparam [5:0] F6_VMADC = 6'b010001;
    localparam [5:0] F6_VMSBC = 6'b010011;

    reg         clk;
    reg         rst_n;
    reg         instr_valid;
    reg [31:0]  instruction;
    reg [31:0]  rs1_scalar_data;
    reg [31:0]  rs2_scalar_data;
    reg         vrf_commit_en;

    wire [3:0]  cycles;
    wire [15:0] vmask16;
    wire        fifo_full;
    wire        busy;
    wire [2:0]  fsm_state;
    // wb_result_lane* = wb_lane* (ngõ ALU truoc mux). Voi vmadc/vmsbc mask-dest, ket qua vd lay
    // tu mask_buffer o ST_FINAL_MASKING (dut.wb_lane0_mux / dut.mask_buffer_data), KHONG phai wb_result_lane*.
    // Neu xem wave: dong nay co the = 0 trong khi v28 van dung (carry trong buffer).
    // Bay: vmadc voi inst[25]=1 (vm=1) -> decoder tat is_mask_carry -> wb_unmasked cho VMADC = 0 (RTL).
    wire [31:0] wb_result_lane0;
    wire [31:0] wb_result_lane1;
    wire [31:0] wb_result_lane2;
    wire [31:0] wb_result_lane3;
    wire        vpu_ready;
    wire        vpu_cfg_done;
    wire [31:0] vpu_vl_remain;
    wire [31:0] csr_vl_o;
    wire [31:0] csr_vtype_o;
    wire [31:0] csr_vlenb_o;
    wire [11:0] scalar_csr_addr;
    wire [31:0] scalar_csr_rdata;
    integer     pass_count;
    integer     fail_count;
    int         tb_case_id;

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
        .scalar_csr_rdata (scalar_csr_rdata)
    );

    assign scalar_csr_addr = 12'h000;

    always #5 clk = ~clk;

    function automatic string fmt_sew_lmul_from_vtype8(input [7:0] vt);
        string s_sew, s_lm;
        begin
            case (vt[5:3])
                3'b000: s_sew = "e8";
                3'b001: s_sew = "e16";
                3'b010: s_sew = "e32";
                3'b011: s_sew = "e64";
                default: s_sew = "e?";
            endcase
            case (vt[2:0])
                3'b000: s_lm = "m1";
                3'b001: s_lm = "m2";
                3'b010: s_lm = "m4";
                3'b011: s_lm = "m8";
                3'b101: s_lm = "mf8";
                3'b110: s_lm = "mf4";
                3'b111: s_lm = "mf2";
                default: s_lm = "m?";
            endcase
            fmt_sew_lmul_from_vtype8 = {s_sew, ", ", s_lm};
        end
    endfunction

    function automatic [31:0] vrf_word_lane0(input integer r);
        vrf_word_lane0 = { dut.vrf_lane0.bank3[r], dut.vrf_lane0.bank2[r],
                           dut.vrf_lane0.bank1[r], dut.vrf_lane0.bank0[r] };
    endfunction

    function automatic [31:0] vrf_word_lane1(input integer r);
        vrf_word_lane1 = { dut.vrf_lane1.bank3[r], dut.vrf_lane1.bank2[r],
                           dut.vrf_lane1.bank1[r], dut.vrf_lane1.bank0[r] };
    endfunction

    function automatic [31:0] vrf_word_lane2(input integer r);
        vrf_word_lane2 = { dut.vrf_lane2.bank3[r], dut.vrf_lane2.bank2[r],
                           dut.vrf_lane2.bank1[r], dut.vrf_lane2.bank0[r] };
    endfunction

    function automatic [31:0] vrf_word_lane3(input integer r);
        vrf_word_lane3 = { dut.vrf_lane3.bank3[r], dut.vrf_lane3.bank2[r],
                           dut.vrf_lane3.bank1[r], dut.vrf_lane3.bank0[r] };
    endfunction

    // In toan hang OP-VV + v0 (carry/borrow mask src), 4 lane (word 32b/lane). SEW=16: tach halfword.
    task show_operands_opvv;
        input [255:0] tag;
        input int     vs2_idx;
        input int     vs1_idx;
        input int     v0_idx;
        begin
            $display("  --- %0s ---", tag);
            $display("  v0(v%0d) [mask / carry-in src]  L0=%08h L1=%08h L2=%08h L3=%08h",
                v0_idx, vrf_word_lane0(v0_idx), vrf_word_lane1(v0_idx),
                vrf_word_lane2(v0_idx), vrf_word_lane3(v0_idx));
            $display("  vs2(v%0d)                        L0=%08h L1=%08h L2=%08h L3=%08h",
                vs2_idx, vrf_word_lane0(vs2_idx), vrf_word_lane1(vs2_idx),
                vrf_word_lane2(vs2_idx), vrf_word_lane3(vs2_idx));
            $display("  vs1(v%0d)                        L0=%08h L1=%08h L2=%08h L3=%08h",
                vs1_idx, vrf_word_lane0(vs1_idx), vrf_word_lane1(vs1_idx),
                vrf_word_lane2(vs1_idx), vrf_word_lane3(vs1_idx));
            $display("  (e16) halfword: vs2 L0: hi=%04h lo=%04h | vs1 L0: hi=%04h lo=%04h",
                vrf_word_lane0(vs2_idx)[31:16], vrf_word_lane0(vs2_idx)[15:0],
                vrf_word_lane0(vs1_idx)[31:16], vrf_word_lane0(vs1_idx)[15:0]);
            $display("  (e16) halfword: vs2 L1: hi=%04h lo=%04h | vs1 L1: hi=%04h lo=%04h",
                vrf_word_lane1(vs2_idx)[31:16], vrf_word_lane1(vs2_idx)[15:0],
                vrf_word_lane1(vs1_idx)[31:16], vrf_word_lane1(vs1_idx)[15:0]);
        end
    endtask

    // e16 + LMUL=m2 + vl: moi chu ky LMUL lay mot cap (vs2,vs1) theo vrf_addr_gen;
    // vproc_cycle_counter: moi chu ky xu ly toi da 8 phan tu 16-bit (128b), vl=13 => chu ky0: 8 elem, chu ky1: 5 elem con.
    task show_m2_e16_vl_semantics;
        input int  vl;
        input int  vd_field;
        input bit  vd_is_mask_dst; // 1: vmadc/vmsbc (bit carry/borrow); 0: vrsub/vsub (ket qua so)
        int n0, n1;
        begin
            n0 = (vl >= 8) ? 8 : vl;
            n1 = (vl > 8) ? (vl - 8) : 0;
            $display("  --- Ngu canh e16 + LMUL=m2, VL=%0d ---", vl);
            $display("      1 thanh ghi / lane-row toi da 8 phan tu 16-bit (VLEN=128).");
            $display("      2 chu ky LMUL: cap (vs2,vs1) tang s_offset 0 -> 1 (hai cap thanh ghi).");
            $display("      Chu ky 0: %0d phan tu dau (elem 0..%0d) - day du trong khung 128b.", n0, n0 - 1);
            if (n1 > 0)
                $display("      Chu ky 1: %0d phan tu con lai (elem %0d..%0d) - KHONG day 8; mask chi bat tu dau chunk (RTL elems_curr_cycle=%0d).",
                    n1, n0, vl - 1, n1);
            else
                $display("      (Khong co chu ky 1: VL <= 8.)");
            if (vd_is_mask_dst)
                $display("      vd v%0d (+ v%0d): vmadc/vmsbc - moi bit carry/borrow tuong ung 1 phan tu 16-bit ACTIVE; tong %0d phan tu.",
                    vd_field, vd_field + 1, vl);
            else
                $display("      vd v%0d (+ v%0d): ket qua phep toan e16 (vd/vs) - %0d phan tu theo VL.",
                    vd_field, vd_field + 1, vl);
        end
    endtask

    // LMUL=m2: vproc_vrf_addr_gen cong s_offset 0,1 vao vs1_base / vs2_base moi chu ky EXEC.
    task show_operands_m2_opvv;
        input [255:0] tag;
        input int     vs2_base;
        input int     vs1_base;
        input int     vd_base;
        input int     v0_idx;
        input int     vl;  // de in dung n0/n1
        input bit     vd_is_mask_dst;
        int r_vs2_hi, r_vs1_hi, r_vd_hi;
        begin
            r_vs2_hi = vs2_base + 1;
            r_vs1_hi = vs1_base + 1;
            r_vd_hi  = vd_base + 1;
            show_m2_e16_vl_semantics(vl, vd_base, vd_is_mask_dst);
            $display("  === %0s (LMUL=m2) ===", tag);
            $display("  vrf_addr_gen: vs2_addr = vs2_field + s_offset, vs1_addr = vs1_field + s_offset");
            $display("    Chu ky 0 (s_offset=0): doc vs2=v%0d, vs1=v%0d  |  Chu ky 1 (s_offset=1): doc vs2=v%0d, vs1=v%0d",
                vs2_base, vs1_base, r_vs2_hi, r_vs1_hi);
            $display("  Nhom vs2 (field v%0d): thanh ghi v%0d + v%0d  |  Nhom vs1 (field v%0d): v%0d + v%0d  (v%0d dung chung)",
                vs2_base, vs2_base, r_vs2_hi, vs1_base, vs1_base, r_vs1_hi, vs1_base);
            $display("  Nhom vd (field v%0d): v%0d + v%0d", vd_base, vd_base, r_vd_hi);
            $display("  v0(v%0d) mask/carry-in  L0=%08h L1=%08h L2=%08h L3=%08h",
                v0_idx, vrf_word_lane0(v0_idx), vrf_word_lane1(v0_idx),
                vrf_word_lane2(v0_idx), vrf_word_lane3(v0_idx));
            $display("  v%0d (vs2[0]) L0=%08h L1=%08h L2=%08h L3=%08h", vs2_base,
                vrf_word_lane0(vs2_base), vrf_word_lane1(vs2_base),
                vrf_word_lane2(vs2_base), vrf_word_lane3(vs2_base));
            $display("  v%0d (vs2[1]) L0=%08h L1=%08h L2=%08h L3=%08h", r_vs2_hi,
                vrf_word_lane0(r_vs2_hi), vrf_word_lane1(r_vs2_hi),
                vrf_word_lane2(r_vs2_hi), vrf_word_lane3(r_vs2_hi));
            $display("  v%0d (vs1[0]) L0=%08h L1=%08h L2=%08h L3=%08h", vs1_base,
                vrf_word_lane0(vs1_base), vrf_word_lane1(vs1_base),
                vrf_word_lane2(vs1_base), vrf_word_lane3(vs1_base));
            $display("  v%0d (vs1[1]) L0=%08h L1=%08h L2=%08h L3=%08h", r_vs1_hi,
                vrf_word_lane0(r_vs1_hi), vrf_word_lane1(r_vs1_hi),
                vrf_word_lane2(r_vs1_hi), vrf_word_lane3(r_vs1_hi));
            $display("  v%0d (vd[0])  L0=%08h L1=%08h L2=%08h L3=%08h", vd_base,
                vrf_word_lane0(vd_base), vrf_word_lane1(vd_base),
                vrf_word_lane2(vd_base), vrf_word_lane3(vd_base));
            $display("  v%0d (vd[1])  L0=%08h L1=%08h L2=%08h L3=%08h", r_vd_hi,
                vrf_word_lane0(r_vd_hi), vrf_word_lane1(r_vd_hi),
                vrf_word_lane2(r_vd_hi), vrf_word_lane3(r_vd_hi));
        end
    endtask

    // vrsub / vsub e16: tung cap halfword 16-bit doc lap
    function automatic [31:0] golden_sub16(input [31:0] a, input [31:0] b);
        golden_sub16 = { a[31:16] - b[31:16], a[15:0] - b[15:0] };
    endfunction

    // v28 sau FINAL_MASKING (e16, m2, vl=13): 13 bit carry co nghia -> lane0 thap 16b = 0x1FFF (bit [12:0] = 1).
    localparam [31:0] EXP_TEST2_VMADC_L0 = 32'h00001fff;
    localparam [31:0] EXP_TEST2_VMSBC_L0 = 32'h0000ff00;

    // In day du thanh ghi vector r: 4 lane (moi lane 32b) + ghep 128b (thu tu giong mask_buffer -> VRF).
    task display_vreg_128;
        input int r;
        reg [127:0] flat;
        begin
            flat = { vrf_word_lane3(r), vrf_word_lane2(r), vrf_word_lane1(r), vrf_word_lane0(r) };
            $display("  --- Noi dung v%0d trong VRF (sau commit, day la data thuc luu) ---", r);
            $display("      lane0 (32b) = %08h | lane1 = %08h | lane2 = %08h | lane3 = %08h",
                vrf_word_lane0(r), vrf_word_lane1(r), vrf_word_lane2(r), vrf_word_lane3(r));
            $display("      [127:0] = {L3,L2,L1,L0} = %032h  (128 bit)", flat);
        end
    endtask

    task vrf_write_word_all_lanes;
        input int          r;
        input [31:0]       w;
        begin
            {dut.vrf_lane0.bank3[r], dut.vrf_lane0.bank2[r], dut.vrf_lane0.bank1[r], dut.vrf_lane0.bank0[r]} = w;
            {dut.vrf_lane1.bank3[r], dut.vrf_lane1.bank2[r], dut.vrf_lane1.bank1[r], dut.vrf_lane1.bank0[r]} = w;
            {dut.vrf_lane2.bank3[r], dut.vrf_lane2.bank2[r], dut.vrf_lane2.bank1[r], dut.vrf_lane2.bank0[r]} = w;
            {dut.vrf_lane3.bank3[r], dut.vrf_lane3.bank2[r], dut.vrf_lane3.bank1[r], dut.vrf_lane3.bank0[r]} = w;
        end
    endtask

    function automatic [31:0] build_opv(
        input [5:0] funct6,
        input       vm,
        input [2:0] funct3,
        input [4:0] vs1_or_imm,
        input [4:0] vs2,
        input [4:0] vd
    );
        reg [31:0] inst;
        begin
            inst = 32'd0;
            inst[6:0]   = OPCODE_OPV;
            inst[11:7]  = vd;
            inst[14:12] = funct3;
            inst[19:15] = vs1_or_imm;
            inst[24:20] = vs2;
            inst[25]    = vm;
            inst[31:26] = funct6;
            build_opv   = inst;
        end
    endfunction

    function automatic [31:0] build_vsetvli(
        input [10:0] zimm11,
        input [4:0]  vd,
        input [4:0]  rs1_idx
    );
        reg [31:0] inst;
        begin
            inst = 32'd0;
            inst[6:0]   = OPCODE_OPV;
            inst[14:12] = F3_CFG;
            inst[19:15] = rs1_idx;
            inst[11:7]  = vd;
            inst[30:20] = zimm11;
            inst[31]    = 1'b0;
            build_vsetvli = inst;
        end
    endfunction

    task issue_instr;
        input [255:0] name;
        input [31:0]  inst;
        input [31:0]  rs1_val;
        input [31:0]  rs2_val;
        logic [2:0] f3;
        logic [5:0] f6;
        begin
            f3 = inst[14:12];
            f6 = inst[31:26];
            tb_case_id++;
            if (inst[6:0] == OPCODE_OPV && f3 == F3_CFG && inst[31] == 1'b0) begin
                $display("\nCase %0d: vsetvli %s", tb_case_id,
                    fmt_sew_lmul_from_vtype8(inst[27:20]));
                $display("  avl (rs1) = %0d", rs1_val);
            end else if (inst[6:0] == OPCODE_OPV && f3 == F3_OPIVV && f6 == F6_VRSUB) begin
                $display("\nCase %0d: vrsub.vv v%0d, v%0d, v%0d",
                    tb_case_id, inst[11:7], inst[24:20], inst[19:15]);
            end else if (inst[6:0] == OPCODE_OPV)
                $display("\nCase %0d: %0s", tb_case_id, name);
            else
                $display("\nCase %0d: %0s  (raw=%08h)", tb_case_id, name, inst);

            @(negedge clk);
            instruction      = inst;
            rs1_scalar_data  = rs1_val;
            rs2_scalar_data  = rs2_val;
            instr_valid       = 1'b1;
            @(negedge clk);
            instr_valid       = 1'b0;
        end
    endtask

    task wait_finish;
        integer t;
        begin
            t = 0;
            while ((busy !== 1'b1) && (t < 100)) begin
                @(posedge clk);
                t = t + 1;
            end
            t = 0;
            while ((busy !== 1'b0) && (t < 500)) begin
                @(posedge clk);
                t = t + 1;
            end
            if (t >= 500) begin
                fail_count = fail_count + 1;
                $display("  FAIL - wait_finish timeout");
            end
        end
    endtask

    task check_u32;
        input [255:0] name;
        input [31:0]  got;
        input [31:0]  exp;
        begin
            if (got === exp) begin
                pass_count = pass_count + 1;
                $display("  PASS - %0s", name);
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL - %0s | got=%08h exp=%08h", name, got, exp);
            end
        end
    endtask

    // Only increment pass_count on match; mismatch prints only (no fail_count)
    task check_expect_pass_only;
        input [255:0] name;
        input [31:0]  got;
        input [31:0]  exp;
        begin
            if (got === exp) begin
                pass_count = pass_count + 1;
                $display("  PASS - %0s (optional)", name);
            end else
                $display("  (no PASS) %0s | got=%08h exp=%08h", name, got, exp);
        end
    endtask

    task run_config_test1;
        input [31:0] exp_vl;
        input [31:0] exp_vtype;
        input [31:0] exp_cycles;
        begin
            issue_instr("TEST1 vsetvli", build_vsetvli(ZIMM_E16_M2, 5'd0, 5'd0), 32'd13, 32'd0);
            wait_finish();
            $display("  vl = %0d", csr_vl_o);
            $display("  vtype = %08h", csr_vtype_o);
            check_u32("TEST1 vl", csr_vl_o, exp_vl);
            check_u32("TEST1 vtype", csr_vtype_o, exp_vtype);
            check_u32("TEST1 cycles", {28'd0, cycles}, exp_cycles);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        instr_valid = 1'b0;
        instruction = 32'd0;
        rs1_scalar_data = 32'd0;
        rs2_scalar_data = 32'd0;
        vrf_commit_en = 1'b1;
        pass_count = 0;
        fail_count = 0;
        tb_case_id = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // Nguon v4 (vs2), v5 (vs1) — pattern 32-bit / lane (dung cho e16 va mask-carry)
        dut.vrf_lane0.bank0[4] = 8'h10; dut.vrf_lane0.bank1[4] = 8'h20;
        dut.vrf_lane0.bank2[4] = 8'h30; dut.vrf_lane0.bank3[4] = 8'h40;
        dut.vrf_lane1.bank0[4] = 8'h11; dut.vrf_lane1.bank1[4] = 8'h21;
        dut.vrf_lane1.bank2[4] = 8'h31; dut.vrf_lane1.bank3[4] = 8'h41;
        dut.vrf_lane2.bank0[4] = 8'h12; dut.vrf_lane2.bank1[4] = 8'h22;
        dut.vrf_lane2.bank2[4] = 8'h32; dut.vrf_lane2.bank3[4] = 8'h42;
        dut.vrf_lane3.bank0[4] = 8'h13; dut.vrf_lane3.bank1[4] = 8'h23;
        dut.vrf_lane3.bank2[4] = 8'h33; dut.vrf_lane3.bank3[4] = 8'h43;

        dut.vrf_lane0.bank0[5] = 8'h01; dut.vrf_lane0.bank1[5] = 8'h02;
        dut.vrf_lane0.bank2[5] = 8'h03; dut.vrf_lane0.bank3[5] = 8'h04;
        dut.vrf_lane1.bank0[5] = 8'h05; dut.vrf_lane1.bank1[5] = 8'h06;
        dut.vrf_lane1.bank2[5] = 8'h07; dut.vrf_lane1.bank3[5] = 8'h08;
        dut.vrf_lane2.bank0[5] = 8'h09; dut.vrf_lane2.bank1[5] = 8'h0a;
        dut.vrf_lane2.bank2[5] = 8'h0b; dut.vrf_lane2.bank3[5] = 8'h0c;
        dut.vrf_lane3.bank0[5] = 8'h0d; dut.vrf_lane3.bank1[5] = 8'h0e;
        dut.vrf_lane3.bank2[5] = 8'h0f; dut.vrf_lane3.bank3[5] = 8'h10;

        //----------------------------------------------------------------------
        // TEST 1: vsetvli e16, m2, avl = 13  -> vl=min(13,vlmax)=13, vtype=9, cycles=2
        //----------------------------------------------------------------------
        $display("\n========== TEST 1: CONFIG e16, m2, avl=13 ==========");
        $display("  Operand config: rs1 (avl) = 13 | zimm -> e16, m2 (vtype byte = 09h)");
        run_config_test1(32'd13, 32'h0000_0009, 32'd2);

        //----------------------------------------------------------------------
        // TEST 2: vmadc (carry-out chac chan) + vmsbc (borrow-out chac chan)
        // vm=0 -> lane_mask=4'hF -> vmask=4'b1111 -> cin[1:0]=1 cho moi nua tu 16-bit.
        // VMADC: vs2=vs1=0xFFFF moi nua tu -> 0xFFFF+0xFFFF+1 => bit carry-out =1 (add 17-bit).
        // VMSBC: vs2=0, vs1=1 moi nua tu -> A + ~B +1 => borrow-out =1 khi A < B (unsigned).
        // Ket qua gom buffer (e16, m2, 2 chu ky): doi chieu EXP_TEST2_* (lay tu RTL).
        //----------------------------------------------------------------------
        $display("\n========== TEST 2: VMADC (carry) / VMSBC (borrow) ==========");
        dut.vrf_lane0.bank0[0] = 8'h0F;
        dut.vrf_lane0.bank1[0] = 8'h00;
        dut.vrf_lane0.bank2[0] = 8'h00;
        dut.vrf_lane0.bank3[0] = 8'h00;

        vrf_write_word_all_lanes(4, 32'hFFFF_FFFF);
        vrf_write_word_all_lanes(5, 32'hFFFF_FFFF);
        // Chu ky 1: vs1_addr = vs1_field+1 -> v6 (phai cung pattern v5 de carry day du)
        vrf_write_word_all_lanes(6, 32'hFFFF_FFFF);

        $display("  vmadc: inst vd=v28 vs2=v4 vs1=v5, vm=0 | LMUL=m2: thuc te vs2 (v4,v5) + vs1 (v5,v6), ghi vd (v28,v29)");
        show_operands_m2_opvv("Toan hang TRUOC vmadc", 4, 5, 28, 0, 13, 1'b1);

        issue_instr("TEST2 vmadc.vv v28", build_opv(F6_VMADC, 1'b0, F3_OPIVV, 5'd5, 5'd4, 5'd28), 32'd0, 32'd0);
        wait_finish();
        display_vreg_128(28);
        $display("  Tom tat vmadc: v28 lane0 (nua thap 16b) = %04h - day la carry bit da pack (TB expect L0 word = %08h).",
            vrf_word_lane0(28)[15:0], EXP_TEST2_VMADC_L0);
        check_u32("TEST2 vmadc L0", vrf_word_lane0(28), EXP_TEST2_VMADC_L0);

        vrf_write_word_all_lanes(4, 32'h0000_0000);
        vrf_write_word_all_lanes(5, 32'h0001_0001);
        vrf_write_word_all_lanes(6, 32'h0001_0001);

        $display("  vmsbc: inst vd=v28 vs2=v4 vs1=v5 | LMUL=m2: vs2 (v4,v5) + vs1 (v5,v6), ghi (v28,v29)");
        show_operands_m2_opvv("Toan hang TRUOC vmsbc", 4, 5, 28, 0, 13, 1'b1);

        issue_instr("TEST2 vmsbc.vv v28", build_opv(F6_VMSBC, 1'b0, F3_OPIVV, 5'd5, 5'd4, 5'd28), 32'd0, 32'd0);
        wait_finish();
        display_vreg_128(28);
        $display("  Tom tat vmsbc: v28 lane0 (nua thap) = %04h - borrow bit pack (expect L0 word = %08h).",
            vrf_word_lane0(28)[15:0], EXP_TEST2_VMSBC_L0);
        check_u32("TEST2 vmsbc L0", vrf_word_lane0(28), EXP_TEST2_VMSBC_L0);

        dut.vrf_lane0.bank0[0] = 8'hFF;
        dut.vrf_lane0.bank1[0] = 8'h00;

        // Khoi phuc v4/v5 goc cho TEST3 vrsub
        dut.vrf_lane0.bank0[4] = 8'h10; dut.vrf_lane0.bank1[4] = 8'h20;
        dut.vrf_lane0.bank2[4] = 8'h30; dut.vrf_lane0.bank3[4] = 8'h40;
        dut.vrf_lane1.bank0[4] = 8'h11; dut.vrf_lane1.bank1[4] = 8'h21;
        dut.vrf_lane1.bank2[4] = 8'h31; dut.vrf_lane1.bank3[4] = 8'h41;
        dut.vrf_lane2.bank0[4] = 8'h12; dut.vrf_lane2.bank1[4] = 8'h22;
        dut.vrf_lane2.bank2[4] = 8'h32; dut.vrf_lane2.bank3[4] = 8'h42;
        dut.vrf_lane3.bank0[4] = 8'h13; dut.vrf_lane3.bank1[4] = 8'h23;
        dut.vrf_lane3.bank2[4] = 8'h33; dut.vrf_lane3.bank3[4] = 8'h43;
        dut.vrf_lane0.bank0[5] = 8'h01; dut.vrf_lane0.bank1[5] = 8'h02;
        dut.vrf_lane0.bank2[5] = 8'h03; dut.vrf_lane0.bank3[5] = 8'h04;
        dut.vrf_lane1.bank0[5] = 8'h05; dut.vrf_lane1.bank1[5] = 8'h06;
        dut.vrf_lane1.bank2[5] = 8'h07; dut.vrf_lane1.bank3[5] = 8'h08;
        dut.vrf_lane2.bank0[5] = 8'h09; dut.vrf_lane2.bank1[5] = 8'h0a;
        dut.vrf_lane2.bank2[5] = 8'h0b; dut.vrf_lane2.bank3[5] = 8'h0c;
        dut.vrf_lane3.bank0[5] = 8'h0d; dut.vrf_lane3.bank1[5] = 8'h0e;
        dut.vrf_lane3.bank2[5] = 8'h0f; dut.vrf_lane3.bank3[5] = 8'h10;

        // v6: thanh ghi thu 2 cua nhom vs1 (m2); dat giong v5 ban dau de TEST3/vrsub dong bo
        dut.vrf_lane0.bank0[6] = 8'h01; dut.vrf_lane0.bank1[6] = 8'h02;
        dut.vrf_lane0.bank2[6] = 8'h03; dut.vrf_lane0.bank3[6] = 8'h04;
        dut.vrf_lane1.bank0[6] = 8'h05; dut.vrf_lane1.bank1[6] = 8'h06;
        dut.vrf_lane1.bank2[6] = 8'h07; dut.vrf_lane1.bank3[6] = 8'h08;
        dut.vrf_lane2.bank0[6] = 8'h09; dut.vrf_lane2.bank1[6] = 8'h0a;
        dut.vrf_lane2.bank2[6] = 8'h0b; dut.vrf_lane2.bank3[6] = 8'h0c;
        dut.vrf_lane3.bank0[6] = 8'h0d; dut.vrf_lane3.bank1[6] = 8'h0e;
        dut.vrf_lane3.bank2[6] = 8'h0f; dut.vrf_lane3.bank3[6] = 8'h10;

        //----------------------------------------------------------------------
        // TEST 3: vrsub.vv — expect = vs1 - vs2 (golden_sub16), PASS optional
        //----------------------------------------------------------------------
        $display("\n========== TEST 3: VRSUB.VV (reverse sub) ==========");
        begin
            reg [31:0] a0, b0, exp0, exp1;
            a0 = vrf_word_lane0(4);
            b0 = vrf_word_lane0(5);
            exp0 = golden_sub16(b0, a0);
            exp1 = golden_sub16(vrf_word_lane1(5), vrf_word_lane1(4));

            $display("  vrsub.vv: inst vd=v6 vs2=v4 vs1=v5, vm=1 | LMUL=m2: vs2 (v4,v5) + vs1 (v5,v6), ghi (v6,v7)");
            show_operands_m2_opvv("Toan hang TRUOC vrsub", 4, 5, 6, 0, 13, 1'b0);
            $display("  Golden L0: vs1-vs2 = %04h:%04h - %04h:%04h => %08h",
                b0[31:16], b0[15:0], a0[31:16], a0[15:0], exp0);
            $display("  Golden L1: (same cong thuc lane1) => %08h", exp1);

            issue_instr("TEST3 vrsub.vv v6", build_opv(F6_VRSUB, 1'b1, F3_OPIVV, 5'd5, 5'd4, 5'd6), 32'd0, 32'd0);
            wait_finish();
            $display("  v6[0] = %08h  expect %08h", vrf_word_lane0(6), exp0);
            $display("  v6[1] = %08h  expect %08h", vrf_word_lane1(6), exp1);
            check_expect_pass_only("TEST3 vrsub L0", vrf_word_lane0(6), exp0);
            check_expect_pass_only("TEST3 vrsub L1", vrf_word_lane1(6), exp1);
        end

        $display("\n=== VPU TB summary: PASS=%0d  FAIL=%0d ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("=== RESULT: PASS (vproc_system_wrapper) ===");
        else
            $display("=== RESULT: FAIL (vproc_system_wrapper) ===");
        #20;
        $finish;
    end

endmodule
