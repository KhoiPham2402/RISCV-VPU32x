`timescale 1ns / 1ps
// =============================================================================
// tb_vproc_vlsu.sv  —  VLSU Integration Testbench
//
// Tests (all word-index based internally; byte addresses only at issue() calls):
//   1. e32 unmasked  — 50 randomised iterations (VL=1..32, LMUL=8)
//   2. e8  unmasked  — VL sweep 1..16 (LMUL=1, vlmax=16)
//   3. e16 unmasked  — VL sweep 1..8  (LMUL=1, vlmax=8)
//   4. e32 masked    — VSE vm=0: inactive elements must not be written
//
// Results written to: $display AND bench/vlsu_test_report.rpt
// =============================================================================

module tb_vproc_vlsu;

    // =========================================================================
    // DUT interface
    // =========================================================================
    reg         clk;
    reg         rst_n;
    reg         instr_valid;
    reg  [31:0] instruction;
    reg  [31:0] rs1_scalar_data;
    reg  [31:0] rs2_scalar_data;
    reg         vrf_commit_en;

    wire [3:0]  cycles;
    wire [15:0] vmask16;
    wire        fifo_full;
    wire        busy;
    wire [3:0]  fsm_state;
    wire [31:0] wb_result_lane0, wb_result_lane1, wb_result_lane2, wb_result_lane3;
    wire        vpu_ready;
    wire        vpu_cfg_done;
    wire [31:0] vpu_vl_remain;
    wire [31:0] csr_vl_o;
    wire [31:0] csr_vtype_o;
    wire [31:0] csr_vlenb_o;
    wire [11:0] scalar_csr_addr_w;
    wire [31:0] scalar_csr_rdata;

    wire        vlsu_mem_req;
    wire        vlsu_mem_we;
    wire [31:0] vlsu_mem_addr;
    wire [ 3:0] vlsu_mem_be;
    wire [31:0] vlsu_mem_wdata;
    reg  [31:0] vlsu_mem_rdata;
    wire        vlsu_busy_o;

    vproc_system_wrapper dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .instr_valid     (instr_valid),
        .instruction     (instruction),
        .rs1_scalar_data (rs1_scalar_data),
        .rs2_scalar_data (rs2_scalar_data),
        .vrf_commit_en   (vrf_commit_en),
        .cycles          (cycles),
        .vmask16         (vmask16),
        .fifo_full       (fifo_full),
        .busy            (busy),
        .fsm_state       (fsm_state),
        .wb_result_lane0 (wb_result_lane0),
        .wb_result_lane1 (wb_result_lane1),
        .wb_result_lane2 (wb_result_lane2),
        .wb_result_lane3 (wb_result_lane3),
        .vpu_ready       (vpu_ready),
        .vpu_cfg_done    (vpu_cfg_done),
        .vpu_vl_remain   (vpu_vl_remain),
        .csr_vl_o        (csr_vl_o),
        .csr_vtype_o     (csr_vtype_o),
        .csr_vlenb_o     (csr_vlenb_o),
        .scalar_csr_addr (scalar_csr_addr_w),
        .scalar_csr_rdata(scalar_csr_rdata),
        .vlsu_mem_req    (vlsu_mem_req),
        .vlsu_mem_we     (vlsu_mem_we),
        .vlsu_mem_addr   (vlsu_mem_addr),
        .vlsu_mem_be     (vlsu_mem_be),
        .vlsu_mem_wdata  (vlsu_mem_wdata),
        .vlsu_mem_rdata  (vlsu_mem_rdata),
        .vlsu_busy_o     (vlsu_busy_o)
    );

    assign scalar_csr_addr_w = 12'h000;

    // =========================================================================
    // Mock DMEM — 4 KB (1024 × 32-bit), byte-enable aware writes
    // =========================================================================
    reg [31:0] dmem [0:1023];

    always @(posedge clk) begin
        if (vlsu_mem_req && vlsu_mem_we) begin
            if (vlsu_mem_be[0]) dmem[vlsu_mem_addr[11:2]][ 7: 0] <= vlsu_mem_wdata[ 7: 0];
            if (vlsu_mem_be[1]) dmem[vlsu_mem_addr[11:2]][15: 8] <= vlsu_mem_wdata[15: 8];
            if (vlsu_mem_be[2]) dmem[vlsu_mem_addr[11:2]][23:16] <= vlsu_mem_wdata[23:16];
            if (vlsu_mem_be[3]) dmem[vlsu_mem_addr[11:2]][31:24] <= vlsu_mem_wdata[31:24];
        end
    end
    always @(*) vlsu_mem_rdata = dmem[vlsu_mem_addr[11:2]];

    always #5 clk = ~clk;

    // =========================================================================
    // Instruction-encoding helpers
    //   ZIMM11: [10:8]=000 [7]=ma [6]=ta [5:3]=vsew [2:0]=vlmul
    // =========================================================================
    localparam [6:0]  OPCODE_OPV  = 7'b101_0111;
    localparam [10:0] ZIMM_E8_M1  = 11'h0C0; // e8,  m1, ta, ma
    localparam [10:0] ZIMM_E16_M1 = 11'h0C8; // e16, m1, ta, ma
    localparam [10:0] ZIMM_E32_M1 = 11'h0D0; // e32, m1, ta, ma
    localparam [10:0] ZIMM_E32_M8 = 11'h0D3; // e32, m8, ta, ma

    function automatic [31:0] build_vsetvli(
        input [10:0] zimm11,
        input [4:0]  vd,
        input [4:0]  rs1_idx
    );
        // [31]=0, [30:20]=zimm11, [19:15]=rs1, [14:12]=111, [11:7]=vd, [6:0]=opcode
        build_vsetvli = {1'b0, zimm11, rs1_idx, 3'b111, vd, OPCODE_OPV};
    endfunction

    // vm=1 (unmasked) variants — bit[25]=1
    function automatic [31:0] build_vle8(input [4:0] vd);
        build_vle8 = 32'd0;
        build_vle8[6:0]   = 7'b0000111;
        build_vle8[11:7]  = vd;
        build_vle8[14:12] = 3'b000; // e8
        build_vle8[25]    = 1'b1;   // vm=1 unmasked
    endfunction

    function automatic [31:0] build_vle16(input [4:0] vd);
        build_vle16 = 32'd0;
        build_vle16[6:0]   = 7'b0000111;
        build_vle16[11:7]  = vd;
        build_vle16[14:12] = 3'b101; // e16
        build_vle16[25]    = 1'b1;
    endfunction

    function automatic [31:0] build_vle32(input [4:0] vd);
        build_vle32 = 32'd0;
        build_vle32[6:0]   = 7'b0000111;
        build_vle32[11:7]  = vd;
        build_vle32[14:12] = 3'b110; // e32
        build_vle32[25]    = 1'b1;
    endfunction

    function automatic [31:0] build_vse8(input [4:0] vs3);
        build_vse8 = 32'd0;
        build_vse8[6:0]   = 7'b0100111;
        build_vse8[11:7]  = vs3;
        build_vse8[14:12] = 3'b000; // e8
        build_vse8[25]    = 1'b1;
    endfunction

    function automatic [31:0] build_vse16(input [4:0] vs3);
        build_vse16 = 32'd0;
        build_vse16[6:0]   = 7'b0100111;
        build_vse16[11:7]  = vs3;
        build_vse16[14:12] = 3'b101; // e16
        build_vse16[25]    = 1'b1;
    endfunction

    function automatic [31:0] build_vse32(input [4:0] vs3);
        build_vse32 = 32'd0;
        build_vse32[6:0]   = 7'b0100111;
        build_vse32[11:7]  = vs3;
        build_vse32[14:12] = 3'b110; // e32
        build_vse32[25]    = 1'b1;
    endfunction

    // Masked VSE32: bit[25] = 0 (vm=0)
    function automatic [31:0] build_vse32_masked(input [4:0] vs3);
        build_vse32_masked = 32'd0;
        build_vse32_masked[6:0]   = 7'b0100111;
        build_vse32_masked[11:7]  = vs3;
        build_vse32_masked[14:12] = 3'b110;
        // bit[25] = 0 → masked
    endfunction

    // =========================================================================
    // Control tasks
    // =========================================================================
    task automatic issue(input [31:0] inst, input [31:0] rs1v, input [31:0] rs2v);
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
        while ((vpu_ready === 1'b1 && busy === 1'b0) && t < 50) begin
            @(posedge clk); t++;
        end
        t = 0;
        while ((vpu_ready === 1'b0 || busy === 1'b1) && t < 5000) begin
            @(posedge clk); t++;
        end
        if (t >= 5000) $display("*** wait_done TIMEOUT ***");
    endtask

    // =========================================================================
    // Byte-level verification (handles partial last word for e8/e16)
    //   dst_wi, src_wi : DMEM word indices
    //   vl_test        : number of active elements
    //   sew_b          : bytes per element (1=e8, 2=e16, 4=e32)
    //   Returns 1 on any failure, 0 on pass
    // =========================================================================
    function automatic bit check_result(
        input int  dst_wi,
        input int  src_wi,
        input int  vl_test,
        input int  sew_b,
        input integer rfd
    );
        int       num_words, elem;
        logic [7:0] got_b, exp_b, dead_b;
        bit       fail;
        fail      = 0;
        num_words = (vl_test * sew_b + 3) / 4; // ceil(vl * sew_b / 4)

        for (int w = 0; w < num_words; w++) begin
            for (int b = 0; b < 4; b++) begin
                elem = (w * 4 + b) / sew_b;
                exp_b  = (dmem[src_wi + w] >> (b * 8)) & 8'hFF;
                got_b  = (dmem[dst_wi + w] >> (b * 8)) & 8'hFF;
                if (elem < vl_test) begin
                    if (got_b !== exp_b) begin
                        $display("    FAIL elem[%0d] word[%0d] byte[%0d]: exp=0x%h got=0x%h",
                                 elem, w, b, exp_b, got_b);
                        $fdisplay(rfd, "    FAIL elem[%0d] word[%0d] byte[%0d]: exp=0x%h got=0x%h",
                                  elem, w, b, exp_b, got_b);
                        fail = 1;
                    end
                end else begin
                    // Tail: must remain DEADBEEF
                    dead_b = (32'hDEADBEEF >> (b * 8)) & 8'hFF;
                    if (got_b !== dead_b) begin
                        $display("    FAIL TAIL elem[%0d] word[%0d] byte[%0d]: exp=0x%h got=0x%h",
                                 elem, w, b, dead_b, got_b);
                        $fdisplay(rfd, "    FAIL TAIL elem[%0d] word[%0d] byte[%0d]: exp=0x%h got=0x%h",
                                  elem, w, b, dead_b, got_b);
                        fail = 1;
                    end
                end
            end
        end
        // Word immediately after the last active word must be untouched
        if (dmem[dst_wi + num_words] !== 32'hDEADBEEF) begin
            $display("    FAIL OOB: dmem[%0d]=0x%h (exp DEADBEEF)", dst_wi + num_words,
                     dmem[dst_wi + num_words]);
            $fdisplay(rfd, "    FAIL OOB: dmem[%0d]=0x%h (exp DEADBEEF)", dst_wi + num_words,
                      dmem[dst_wi + num_words]);
            fail = 1;
        end
        return fail;
    endfunction

    // =========================================================================
    // Test counters and report file
    // =========================================================================
    integer rpt_fd;
    int     total_pass;
    int     total_fail;

    // =========================================================================
    // Main testbench
    // =========================================================================
    initial begin
        // Declare all local variables at top of block
        int vl_rand, src_wi, dst_wi, mask_wi;
        int pass_cnt, fail_cnt;
        bit failed;
        int bv;  // scratch for byte-value patterns

        clk             = 0;
        rst_n           = 0;
        instr_valid     = 0;
        instruction     = 0;
        rs1_scalar_data = 0;
        rs2_scalar_data = 0;
        vrf_commit_en   = 1;
        total_pass      = 0;
        total_fail      = 0;

        for (int i = 0; i < 1024; i++) dmem[i] = 32'd0;

        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        rpt_fd = $fopen("vlsu_test_report.rpt", "w");
        if (rpt_fd == 0) $display("WARNING: cannot open vlsu_test_report.rpt");

        $display ("============================================================");
        $fdisplay(rpt_fd, "============================================================");
        $display ("  VLSU Test Report — vproc_vec_lsu + vproc_system_wrapper");
        $fdisplay(rpt_fd, "  VLSU Test Report — vproc_vec_lsu + vproc_system_wrapper");
        $display ("============================================================");
        $fdisplay(rpt_fd, "============================================================");

        // =====================================================================
        // TEST 1: e32 unmasked — 50 randomised iterations, VL=1..32, LMUL=8
        // =====================================================================
        pass_cnt = 0; fail_cnt = 0;
        $display("\n[TEST 1] e32 unmasked — 50 randomised iterations");
        $fdisplay(rpt_fd, "\n[TEST 1] e32 unmasked — 50 randomised iterations (VL=1..32, LMUL=8)");

        for (int iter = 1; iter <= 50; iter++) begin
            failed  = 0;
            vl_rand = ($urandom % 32) + 1;  // 1..32
            src_wi  = $urandom % 400;        // word index 0..399
            dst_wi  = 512 + ($urandom % 400); // word index 512..911

            for (int i = 0; i < vl_rand + 4; i++) begin
                dmem[src_wi + i] = $urandom;
                dmem[dst_wi + i] = 32'hDEADBEEF;
            end

            // vsetvli, VLE32, VSE32 (all unmasked)
            issue(build_vsetvli(ZIMM_E32_M8, 5'd0, 5'd0), vl_rand, 32'd0);
            wait_done();
            if (csr_vl_o !== vl_rand) begin
                $display("  [Iter %0d] VL mismatch: exp=%0d got=%0d", iter, vl_rand, csr_vl_o);
                failed = 1;
            end

            issue(build_vle32(5'd8), src_wi * 4, 32'd0);
            wait_done();
            issue(build_vse32(5'd8), dst_wi * 4, 32'd0);
            wait_done();

            if (check_result(dst_wi, src_wi, vl_rand, 4, rpt_fd)) failed = 1;

            if (failed) begin
                fail_cnt++; total_fail++;
                $fdisplay(rpt_fd, "  [Iter %2d] FAIL  VL=%0d", iter, vl_rand);
            end else begin
                pass_cnt++; total_pass++;
                if (iter % 10 == 0)
                    $fdisplay(rpt_fd, "  [Iter %2d] PASS  VL=%0d", iter, vl_rand);
            end
        end
        $display("  PASS=%0d  FAIL=%0d / 50", pass_cnt, fail_cnt);
        $fdisplay(rpt_fd, "  Summary: PASS=%0d  FAIL=%0d / 50", pass_cnt, fail_cnt);

        // =====================================================================
        // TEST 2: e8 unmasked — VL sweep 1..16 (LMUL=1, vlmax=16)
        //   src pattern: byte i = i & 0xFF (packed 4 per word)
        // =====================================================================
        pass_cnt = 0; fail_cnt = 0;
        $display("\n[TEST 2] e8 unmasked — VL sweep 1..16");
        $fdisplay(rpt_fd, "\n[TEST 2] e8 unmasked — VL sweep 1..16 (LMUL=1, vlmax=16)");

        src_wi = 800; dst_wi = 820;

        for (int vl = 1; vl <= 16; vl++) begin
            failed = 0;

            // Pack bytes into words: word w = {byte(4w+3), byte(4w+2), byte(4w+1), byte(4w)}
            for (int w = 0; w < 5; w++) begin
                bv = 4 * w;
                dmem[src_wi + w] = ((bv+3) & 8'hFF) << 24 |
                                   ((bv+2) & 8'hFF) << 16 |
                                   ((bv+1) & 8'hFF) << 8  |
                                   ((bv+0) & 8'hFF);
                dmem[dst_wi + w] = 32'hDEADBEEF;
            end

            issue(build_vsetvli(ZIMM_E8_M1, 5'd0, 5'd0), vl, 32'd0);
            wait_done();
            issue(build_vle8(5'd8), src_wi * 4, 32'd0);
            wait_done();
            issue(build_vse8(5'd8), dst_wi * 4, 32'd0);
            wait_done();

            if (check_result(dst_wi, src_wi, vl, 1, rpt_fd)) failed = 1;

            if (failed) begin
                fail_cnt++; total_fail++;
                $fdisplay(rpt_fd, "  VL=%2d  FAIL", vl);
            end else begin
                pass_cnt++; total_pass++;
                $fdisplay(rpt_fd, "  VL=%2d  PASS", vl);
            end
        end
        $display("  PASS=%0d  FAIL=%0d / 16", pass_cnt, fail_cnt);
        $fdisplay(rpt_fd, "  Summary: PASS=%0d  FAIL=%0d / 16", pass_cnt, fail_cnt);

        // =====================================================================
        // TEST 3: e16 unmasked — VL sweep 1..8 (LMUL=1, vlmax=8)
        //   src pattern: halfword i = i (packed 2 per word)
        // =====================================================================
        pass_cnt = 0; fail_cnt = 0;
        $display("\n[TEST 3] e16 unmasked — VL sweep 1..8");
        $fdisplay(rpt_fd, "\n[TEST 3] e16 unmasked — VL sweep 1..8 (LMUL=1, vlmax=8)");

        src_wi = 900; dst_wi = 920;

        for (int vl = 1; vl <= 8; vl++) begin
            failed = 0;

            // Pack halfwords: word w = {hword(2w+1), hword(2w)}
            for (int w = 0; w < 5; w++) begin
                bv = 2 * w;
                dmem[src_wi + w] = ((bv+1) & 16'hFFFF) << 16 |
                                   ((bv+0) & 16'hFFFF);
                dmem[dst_wi + w] = 32'hDEADBEEF;
            end

            issue(build_vsetvli(ZIMM_E16_M1, 5'd0, 5'd0), vl, 32'd0);
            wait_done();
            issue(build_vle16(5'd8), src_wi * 4, 32'd0);
            wait_done();
            issue(build_vse16(5'd8), dst_wi * 4, 32'd0);
            wait_done();

            if (check_result(dst_wi, src_wi, vl, 2, rpt_fd)) failed = 1;

            if (failed) begin
                fail_cnt++; total_fail++;
                $fdisplay(rpt_fd, "  VL=%2d  FAIL", vl);
            end else begin
                pass_cnt++; total_pass++;
                $fdisplay(rpt_fd, "  VL=%2d  PASS", vl);
            end
        end
        $display("  PASS=%0d  FAIL=%0d / 8", pass_cnt, fail_cnt);
        $fdisplay(rpt_fd, "  Summary: PASS=%0d  FAIL=%0d / 8", pass_cnt, fail_cnt);

        // =====================================================================
        // TEST 4: e32 masked store (vm=0)
        //   v0 mask: bit0=1, bit1=0, bit2=1, bit3=0 (elements 0,2 active)
        //   src:  [10, 20, 30, 40]
        //   expect after VSE32 masked: dst = [10, DEADBEEF, 30, DEADBEEF]
        // =====================================================================
        pass_cnt = 0; fail_cnt = 0;
        $display("\n[TEST 4] e32 masked store (vm=0, alternating mask)");
        $fdisplay(rpt_fd, "\n[TEST 4] e32 masked store (vm=0, alternating mask, VL=4)");

        src_wi  = 100;
        dst_wi  = 110;
        mask_wi = 120;

        dmem[src_wi+0] = 32'd10;
        dmem[src_wi+1] = 32'd20;
        dmem[src_wi+2] = 32'd30;
        dmem[src_wi+3] = 32'd40;

        // v0[3:0] = 4'b0101 → elems 0,2 active → v0_flat lane0 = 32'h00000005
        dmem[mask_wi+0] = 32'h00000005;
        dmem[mask_wi+1] = 32'h00000000;
        dmem[mask_wi+2] = 32'h00000000;
        dmem[mask_wi+3] = 32'h00000000;

        for (int i = 0; i < 5; i++) dmem[dst_wi+i] = 32'hDEADBEEF;

        // vsetvli e32 m1 vl=4
        issue(build_vsetvli(ZIMM_E32_M1, 5'd0, 5'd0), 32'd4, 32'd0);
        wait_done();

        // Load v0 (mask register), unmasked
        issue(build_vle32(5'd0), mask_wi * 4, 32'd0);
        wait_done();

        // Load v8 with src data, unmasked
        issue(build_vle32(5'd8), src_wi * 4, 32'd0);
        wait_done();

        // Masked store
        issue(build_vse32_masked(5'd8), dst_wi * 4, 32'd0);
        wait_done();

        failed = 0;
        if (dmem[dst_wi+0] !== 32'd10) begin
            $display("  FAIL elem0: exp=10 got=%0d", dmem[dst_wi+0]);
            $fdisplay(rpt_fd, "  FAIL elem0: exp=10 got=%0d", dmem[dst_wi+0]);
            failed = 1;
        end
        if (dmem[dst_wi+1] !== 32'hDEADBEEF) begin
            $display("  FAIL elem1: should be DEADBEEF (masked), got=0x%h", dmem[dst_wi+1]);
            $fdisplay(rpt_fd, "  FAIL elem1: should be DEADBEEF (masked), got=0x%h", dmem[dst_wi+1]);
            failed = 1;
        end
        if (dmem[dst_wi+2] !== 32'd30) begin
            $display("  FAIL elem2: exp=30 got=%0d", dmem[dst_wi+2]);
            $fdisplay(rpt_fd, "  FAIL elem2: exp=30 got=%0d", dmem[dst_wi+2]);
            failed = 1;
        end
        if (dmem[dst_wi+3] !== 32'hDEADBEEF) begin
            $display("  FAIL elem3: should be DEADBEEF (masked), got=0x%h", dmem[dst_wi+3]);
            $fdisplay(rpt_fd, "  FAIL elem3: should be DEADBEEF (masked), got=0x%h", dmem[dst_wi+3]);
            failed = 1;
        end

        if (failed) begin
            fail_cnt++; total_fail++;
            $fdisplay(rpt_fd, "  Masked e32 store: FAIL");
            $fdisplay(rpt_fd, "    dst[0..3] = 0x%h  0x%h  0x%h  0x%h",
                     dmem[dst_wi+0], dmem[dst_wi+1], dmem[dst_wi+2], dmem[dst_wi+3]);
        end else begin
            pass_cnt++; total_pass++;
            $fdisplay(rpt_fd, "  Masked e32 store: PASS");
            $fdisplay(rpt_fd, "    dst[0]=%0d  dst[1]=DEADBEEF  dst[2]=%0d  dst[3]=DEADBEEF",
                     dmem[dst_wi+0], dmem[dst_wi+2]);
        end
        $display("  PASS=%0d  FAIL=%0d / 1", pass_cnt, fail_cnt);
        $fdisplay(rpt_fd, "  Summary: PASS=%0d  FAIL=%0d / 1", pass_cnt, fail_cnt);

        // =====================================================================
        // Final summary
        // =====================================================================
        $display ("\n============================================================");
        $fdisplay(rpt_fd, "\n============================================================");
        $display (" FINAL SUMMARY");
        $fdisplay(rpt_fd, " FINAL SUMMARY");
        $display (" Total PASS : %0d", total_pass);
        $fdisplay(rpt_fd, " Total PASS : %0d", total_pass);
        $display (" Total FAIL : %0d", total_fail);
        $fdisplay(rpt_fd, " Total FAIL : %0d", total_fail);
        $display (" Total tests: %0d", total_pass + total_fail);
        $fdisplay(rpt_fd, " Total tests: %0d", total_pass + total_fail);
        if (total_fail == 0) begin
            $display (" RESULT: ALL PASS");
            $fdisplay(rpt_fd, " RESULT: ALL PASS");
        end else begin
            $display (" RESULT: %0d FAILURES", total_fail);
            $fdisplay(rpt_fd, " RESULT: %0d FAILURES", total_fail);
        end
        $display ("============================================================");
        $fdisplay(rpt_fd, "============================================================");

        $fclose(rpt_fd);
        #50;
        $finish;
    end

endmodule
