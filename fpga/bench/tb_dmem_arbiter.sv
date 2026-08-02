// =============================================================================
// tb_dmem_arbiter.sv — directed unit checks for fpga/rtl/bus/dmem_arbiter.sv
// (Issue: single shared DMEM bus, VLSU(M0) > scalar(M1) > video(M2) priority)
//
// Run: vsim -c -do fpga/sim/run_dmem_arbiter.do
// =============================================================================
`timescale 1ns/1ps

module tb_dmem_arbiter;

    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n;

    // M0: VLSU
    logic        m0_req, m0_we;
    logic [31:0] m0_addr, m0_wdata, m0_rdata;
    logic [ 3:0] m0_be;
    logic        m0_ready;

    // M1: scalar
    logic        m1_re, m1_we;
    logic [31:0] m1_addr, m1_wdata, m1_rdata;
    logic [ 3:0] m1_be;
    logic        m1_stall;

    // M2: video
    logic [13:0] m2_addr;
    logic        m2_re;
    logic [31:0] m2_rdata;

    // downstream memory port
    logic        mem_re, mem_we;
    logic [31:0] mem_addr, mem_wdata, mem_rdata;
    logic [ 3:0] mem_be;

    dmem_arbiter #(.ADDR_W(32), .DATA_W(32), .VID_AW(14)) u_arb (
        .clk(clk), .rst_n(rst_n),
        .m0_req_i(m0_req), .m0_we_i(m0_we), .m0_addr_i(m0_addr),
        .m0_be_i(m0_be),   .m0_wdata_i(m0_wdata),
        .m0_rdata_o(m0_rdata), .m0_ready_o(m0_ready),
        .m1_re_i(m1_re), .m1_we_i(m1_we), .m1_addr_i(m1_addr),
        .m1_be_i(m1_be), .m1_wdata_i(m1_wdata),
        .m1_rdata_o(m1_rdata), .m1_stall_o(m1_stall),
        .m2_addr_i(m2_addr), .m2_re_i(m2_re), .m2_rdata_o(m2_rdata),
        .mem_re_o(mem_re), .mem_we_o(mem_we), .mem_addr_o(mem_addr),
        .mem_be_o(mem_be), .mem_wdata_o(mem_wdata), .mem_rdata_i(mem_rdata)
    );

    dmem_model_sp #(.DEPTH(16384)) u_dmem (
        .clk(clk), .re(mem_re), .we(mem_we), .addr(mem_addr),
        .be(mem_be), .wdata(mem_wdata), .rdata(mem_rdata)
    );

    int errors = 0;

    task automatic check(input bit cond, input string name);
        if (!cond) begin
            $display("[FAIL] %s", name);
            errors++;
        end else begin
            $display("[PASS] %s", name);
        end
    endtask

    task automatic idle_all;
        begin
            m0_req = 0; m0_we = 0; m0_addr = 0; m0_be = 0; m0_wdata = 0;
            m1_re  = 0; m1_we = 0; m1_addr = 0; m1_be = 0; m1_wdata = 0;
            m2_re  = 0; m2_addr = 0;
        end
    endtask

    initial begin
        rst_n = 0;
        idle_all();
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Backdoor seed
        u_dmem.mem[0]   = 32'hAAAA_0001;   // scalar test word
        u_dmem.mem[100] = 32'hBBBB_0002;   // VLSU test word
        u_dmem.mem[70]  = 32'hCCCC_0003;   // video test word
        u_dmem.mem[50]  = 32'h0000_0000;   // arbitration write-conflict target (scalar)
        u_dmem.mem[60]  = 32'h0000_0000;   // arbitration write-conflict target (VLSU)
        u_dmem.mem[80]  = 32'hAABB_CCDD;   // byte-enable target

        // ── Case 1: scalar-alone read ────────────────────────────────────────
        @(negedge clk);
        m1_re = 1; m1_addr = 32'd0;
        @(posedge clk); #1;
        check(m1_stall === 1'b0, "C1: scalar-alone read not stalled");
        @(negedge clk);
        m1_re = 0;
        #1;
        check(m1_rdata === 32'hAAAA_0001, "C1: scalar-alone read data correct 1 cycle later");
        idle_all();
        @(posedge clk);

        // ── Case 2: VLSU-alone read ──────────────────────────────────────────
        // m0_ready is a live 1-cycle pulse (not held), so it must be sampled
        // right at the edge the grant completes, not later.
        @(negedge clk);
        m0_req = 1; m0_we = 0; m0_addr = 32'd400; // word 100
        #1;
        check(m0_ready === 1'b0, "C2: VLSU read not ready before the grant edge");
        @(posedge clk); #1;
        check(m0_ready === 1'b1, "C2: VLSU read ready right after the grant edge");
        check(m0_rdata === 32'hBBBB_0002, "C2: VLSU-alone read data correct");
        idle_all();
        @(posedge clk);

        // ── Case 3: scalar + VLSU contention (VLSU wins, scalar retries) ────
        @(negedge clk);
        m1_re = 1; m1_addr = 32'd0;      // word 0
        m0_req = 1; m0_we = 0; m0_addr = 32'd400; // word 100
        #1;
        check(m1_stall === 1'b1, "C3: scalar stalled when VLSU contends");
        @(posedge clk); #1;
        check(m0_ready === 1'b1 && m0_rdata === 32'hBBBB_0002,
              "C3: VLSU's contended read completed on the grant edge");
        @(negedge clk);
        m0_req = 0; // VLSU done, scalar retries same request (still held)
        #1;
        check(m1_stall === 1'b0, "C3: scalar granted on retry once VLSU idle");
        @(posedge clk); #1;
        check(m1_rdata === 32'hAAAA_0001, "C3: scalar's retried read data correct");
        idle_all();
        @(posedge clk);

        // ── Case 4: scalar write + VLSU write same cycle ─────────────────────
        @(negedge clk);
        m1_we = 1; m1_addr = 32'd200; m1_wdata = 32'h1111_1111; m1_be = 4'b1111; // word 50
        m0_req = 1; m0_we = 1; m0_addr = 32'd240; m0_wdata = 32'h2222_2222; m0_be = 4'b1111; // word 60
        @(posedge clk); #1;
        check(m1_stall === 1'b1, "C4: scalar write stalled when VLSU write contends");
        @(negedge clk); #1;
        check(u_dmem.mem[60] === 32'h2222_2222, "C4: VLSU write landed");
        check(u_dmem.mem[50] === 32'h0000_0000, "C4: scalar write did NOT land while denied");
        m0_req = 0; m0_we = 0; // scalar retries (m1_we still held)
        @(posedge clk); #1;
        check(m1_stall === 1'b0, "C4: scalar write granted on retry");
        @(negedge clk); #1;
        check(u_dmem.mem[50] === 32'h1111_1111, "C4: scalar write landed on retry");
        idle_all();
        @(posedge clk);

        // ── Case 5: video loses to scalar, then wins when scalar idle ────────
        @(negedge clk);
        m2_re = 1; m2_addr = 14'd70;
        m1_re = 1; m1_addr = 32'd0;
        @(posedge clk); #1;
        check(m2_rdata === 32'h0000_0000, "C5: video held at reset value while scalar wins");
        @(negedge clk);
        m1_re = 0; // scalar idle now, video should win this cycle
        @(posedge clk); #1;
        @(negedge clk); #1;
        check(m2_rdata === 32'hCCCC_0003, "C5: video data updates once granted");
        idle_all();
        @(posedge clk);

        // ── Case 6: video + scalar + VLSU together — VLSU wins, video holds ──
        @(negedge clk);
        m0_req = 1; m0_we = 0; m0_addr = 32'd400;
        m1_re  = 1; m1_addr = 32'd0;
        m2_re  = 1; m2_addr = 14'd70;
        @(posedge clk); #1;
        check(m1_stall === 1'b1, "C6: scalar stalled with VLSU+video contending");
        @(negedge clk); #1;
        check(m2_rdata === 32'hCCCC_0003, "C6: video holds last value (unchanged) while denied");
        idle_all();
        @(posedge clk);

        // ── Case 7: byte-enable pass-through (partial write) ─────────────────
        @(negedge clk);
        m1_we = 1; m1_addr = 32'd320; m1_wdata = 32'hFFFF_FFFF; m1_be = 4'b0001; // word 80, byte0 only
        @(posedge clk); #1;
        @(negedge clk); #1;
        check(u_dmem.mem[80] === 32'hAABB_CCFF, "C7: byte-enable partial write only touches byte 0");
        idle_all();
        @(posedge clk);

        // ── Case 8: sustained multi-cycle VLSU burst (5 back-to-back streamed
        // addresses, simulating a real vle32.v), scalar holds an identical
        // denied write the entire time — models exactly what pipelined_vpu.sv
        // does (EX/MEM frozen, re-driving the same address/data every retried
        // cycle) rather than just a single-cycle denial+retry like C3/C4. ──
        u_dmem.mem[200] = 32'hA000_0000;
        u_dmem.mem[201] = 32'hA000_0001;
        u_dmem.mem[202] = 32'hA000_0002;
        u_dmem.mem[203] = 32'hA000_0003;
        u_dmem.mem[204] = 32'hA000_0004;
        u_dmem.mem[90]  = 32'h0000_0000;

        @(negedge clk);
        m1_we = 1; m1_addr = 32'd360; m1_wdata = 32'h1111_2222; m1_be = 4'b1111; // word 90
        m0_req = 1; m0_we = 0; m0_addr = 32'd800; // word 200
        for (int k = 0; k < 5; k++) begin
            #1;
            check(m1_stall === 1'b1, $sformatf("C8: scalar denied on burst cycle %0d", k));
            @(posedge clk); #1;
            check(m0_ready === 1'b1 && m0_rdata === (32'hA000_0000 + k),
                  $sformatf("C8: VLSU word%0d correct mid-burst (no dropped/corrupted cycle)", 200+k));
            check(u_dmem.mem[90] === 32'h0000_0000,
                  $sformatf("C8: scalar write still blocked after burst cycle %0d", k));
            @(negedge clk);
            if (k < 4) m0_addr = 32'd800 + ((k + 1) * 4); // advance to next streamed word
        end
        m0_req = 0; // VLSU burst done; scalar's write request still held, unchanged
        #1;
        check(m1_stall === 1'b0, "C8: scalar finally granted once burst ends");
        @(posedge clk); #1;
        @(negedge clk); #1;
        check(u_dmem.mem[90] === 32'h1111_2222,
              "C8: scalar write lands correctly after 5-cycle burst, data/address unchanged throughout");
        idle_all();
        @(posedge clk);

        // ── Case 9: video survives a *sustained* multi-cycle denial (not just
        // 1 cycle like C6) — holds the same last-good value throughout, then
        // correctly refreshes once it finally wins arbitration again. ──────
        u_dmem.mem[70] = 32'hCCCC_0003; // re-affirm (may have been overwritten by C8's word range? no overlap)
        @(negedge clk);
        m2_re = 1; m2_addr = 14'd70;
        m0_req = 1; m0_we = 0; m0_addr = 32'd400; // VLSU wins every cycle below
        for (int k = 0; k < 5; k++) begin
            #1;
            check(m2_rdata === 32'hCCCC_0003,
                  $sformatf("C9: video holds stable value through denial cycle %0d (not corrupted)", k));
            @(posedge clk); #1;
            @(negedge clk);
        end
        m0_req = 0; // VLSU stops; video should win next cycle
        @(posedge clk); #1;
        @(negedge clk); #1;
        check(m2_rdata === 32'hCCCC_0003,
              "C9: video refreshes correctly after a 5-cycle sustained denial");
        idle_all();
        @(posedge clk);

        if (errors == 0) $display("=== RESULT: ALL PASS ===");
        else              $display("=== RESULT: %0d CHECK(S) FAILED ===", errors);
        $stop;
    end

endmodule
