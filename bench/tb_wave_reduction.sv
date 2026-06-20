`timescale 1ns / 1ps
// Waveform testbench for vproc_reduction unit.
// Runs vredsum, vredmax, vredminu to generate clean waveforms showing:
//   start, valid, busy, elem_cnt, acc_r, wb_valid, result_out
//
// See run_wave_reduction_sim.do for wave setup.
//
// Run: vsim -do run_wave_reduction_sim.do

module tb_wave_reduction;

    localparam [6:0] OPCODE_OPV = 7'b101_0111;
    localparam [5:0] VREDSUM  = 6'h00;
    localparam [5:0] VREDMAX  = 6'h07;
    localparam [5:0] VREDMAXU = 6'h06;
    localparam [5:0] VREDMIN  = 6'h05;
    localparam [5:0] VREDMINU = 6'h04;

    localparam [10:0] ZIMM_E32_M1 = 11'h0D0;
    localparam [10:0] ZIMM_E8_M1  = 11'h0C0;

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
        if (t >= 5000) $display("*** wait_done TIMEOUT ***");
    endtask

    integer pass_cnt = 0, fail_cnt = 0;

    task automatic check32(input string tag, input [31:0] got, exp);
        if (got === exp) begin
            pass_cnt++;
            $display("[PASS] %s: 0x%08X", tag, got);
        end else begin
            fail_cnt++;
            $error("[FAIL] %s: got=0x%08X exp=0x%08X", tag, got, exp);
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; instr_valid = 0;
        instruction = 0; rs1_scalar_data = 0; rs2_scalar_data = 0;
        vrf_commit_en = 1'b1;

        repeat(4) @(negedge clk);
        rst_n = 1;
        repeat(2) @(negedge clk);

        // ═══════════════════════════════════════════════════════════════════
        // CASE 1: vredsum.vs e32 m1 — sum of {10,20,30,40} + init 0 = 100
        // ═══════════════════════════════════════════════════════════════════
        $display("\n[WAVE_RED] === Case 1: vredsum.vs e32 m1 ===");
        $display("[WAVE_RED] v3={10,20,30,40}  v4={0,...}  expect result=100");

        issue(build_vsetvli(ZIMM_E32_M1, 5'd0, 5'd1), 32'd4, 32'd0);
        wait_done;

        vrf_write4(3, 32'd10, 32'd20, 32'd30, 32'd40);
        vrf_write4(4, 32'd0,  32'd0,  32'd0,  32'd0);

        // vredsum.vs v5, v3, v4  (OPMVV funct3=010, vs1=v4 initial, vs2=v3 source)
        issue(build_opv(VREDSUM, 1'b1, 3'b010, 5'd4, 5'd3, 5'd5), 32'd0, 32'd0);
        wait_done;
        check32("vredsum result", {dut.vrf_lane0.bank3[5], dut.vrf_lane0.bank2[5],
                                   dut.vrf_lane0.bank1[5], dut.vrf_lane0.bank0[5]}, 32'd100);

        // ═══════════════════════════════════════════════════════════════════
        // CASE 2: vredsum with non-zero initial accumulator
        // ═══════════════════════════════════════════════════════════════════
        $display("\n[WAVE_RED] === Case 2: vredsum + initial=50, elements={5,5,5,5} ===");
        $display("[WAVE_RED] expect result = 50+5+5+5+5 = 70");

        vrf_write4(3, 32'd5,  32'd5,  32'd5,  32'd5);
        vrf_write4(4, 32'd50, 32'd0,  32'd0,  32'd0);  // v4[lane0]=50 initial

        issue(build_opv(VREDSUM, 1'b1, 3'b010, 5'd4, 5'd3, 5'd5), 32'd0, 32'd0);
        wait_done;
        check32("vredsum+init result",
                {dut.vrf_lane0.bank3[5],dut.vrf_lane0.bank2[5],
                 dut.vrf_lane0.bank1[5],dut.vrf_lane0.bank0[5]}, 32'd70);

        // ═══════════════════════════════════════════════════════════════════
        // CASE 3: vredmax.vs — max of {10, 99, 3, 50} + init 0
        // ═══════════════════════════════════════════════════════════════════
        $display("\n[WAVE_RED] === Case 3: vredmax.vs e32 m1 ===");
        $display("[WAVE_RED] v3={10,99,3,50}  expect max=99");

        vrf_write4(3, 32'd10, 32'd99, 32'd3,  32'd50);
        vrf_write4(4, 32'd0,  32'd0,  32'd0,  32'd0);

        issue(build_opv(VREDMAX, 1'b1, 3'b010, 5'd4, 5'd3, 5'd5), 32'd0, 32'd0);
        wait_done;
        check32("vredmax result",
                {dut.vrf_lane0.bank3[5],dut.vrf_lane0.bank2[5],
                 dut.vrf_lane0.bank1[5],dut.vrf_lane0.bank0[5]}, 32'd99);

        // ═══════════════════════════════════════════════════════════════════
        // CASE 4: vredmin.vs with signed values — min includes negative
        // ═══════════════════════════════════════════════════════════════════
        $display("\n[WAVE_RED] === Case 4: vredmin.vs signed {10,-1,3,50} ===");
        $display("[WAVE_RED] expect min=-1 (0xFFFFFFFF)");

        vrf_write4(3, 32'd10, 32'hFFFF_FFFF, 32'd3, 32'd50);
        vrf_write4(4, 32'd0,  32'd0,          32'd0, 32'd0);

        issue(build_opv(VREDMIN, 1'b1, 3'b010, 5'd4, 5'd3, 5'd5), 32'd0, 32'd0);
        wait_done;
        check32("vredmin signed result",
                {dut.vrf_lane0.bank3[5],dut.vrf_lane0.bank2[5],
                 dut.vrf_lane0.bank1[5],dut.vrf_lane0.bank0[5]}, 32'hFFFF_FFFF);

        // ═══════════════════════════════════════════════════════════════════
        // CASE 5: vredmaxu — unsigned max (0xFF > all signed comparisons)
        // ═══════════════════════════════════════════════════════════════════
        $display("\n[WAVE_RED] === Case 5: vredmaxu.vs unsigned {0xFF,1,2,3} ===");
        $display("[WAVE_RED] expect max_u=0xFF=255");

        vrf_write4(3, 32'hFF, 32'h01, 32'h02, 32'h03);
        vrf_write4(4, 32'd0,  32'd0,  32'd0,  32'd0);

        issue(build_opv(VREDMAXU, 1'b1, 3'b010, 5'd4, 5'd3, 5'd5), 32'd0, 32'd0);
        wait_done;
        check32("vredmaxu result",
                {dut.vrf_lane0.bank3[5],dut.vrf_lane0.bank2[5],
                 dut.vrf_lane0.bank1[5],dut.vrf_lane0.bank0[5]}, 32'hFF);

        // ═══════════════════════════════════════════════════════════════════
        // CASE 6: vredsum e8 m1 — SEW=8, 16 elements across 4 lanes×4bytes
        // ═══════════════════════════════════════════════════════════════════
        $display("\n[WAVE_RED] === Case 6: vredsum e8 m1, 16 elements all=1 ===");
        $display("[WAVE_RED] expect sum=16");

        issue(build_vsetvli(ZIMM_E8_M1, 5'd0, 5'd1), 32'd16, 32'd0);
        wait_done;

        // Each lane holds 4 bytes; 4 lanes = 16 bytes (elements)
        // All elements = 1: packed as 0x01010101 per lane
        vrf_write4(3, 32'h01010101, 32'h01010101, 32'h01010101, 32'h01010101);
        vrf_write4(4, 32'd0,        32'd0,        32'd0,        32'd0);

        issue(build_opv(VREDSUM, 1'b1, 3'b010, 5'd4, 5'd3, 5'd5), 32'd0, 32'd0);
        wait_done;
        check32("vredsum e8 16elem",
                {dut.vrf_lane0.bank3[5],dut.vrf_lane0.bank2[5],
                 dut.vrf_lane0.bank1[5],dut.vrf_lane0.bank0[5]}, 32'd16);

        // ──────────────────────────────────────────────────────────────────
        repeat(10) @(posedge clk);
        $display("\n[WAVE_RED] ===== SUMMARY: PASS=%0d  FAIL=%0d =====", pass_cnt, fail_cnt);
        $finish;
    end

endmodule
