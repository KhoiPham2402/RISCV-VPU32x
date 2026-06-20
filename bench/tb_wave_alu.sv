`timescale 1ns / 1ps
// Waveform testbench for ALU (vproc_processor_lane) + VRF writeback.
// Runs a short ALU sequence to generate clean waveforms for the report.
//
// Key signals visible in the wave window (see run_wave_alu_sim.do):
//   FSM:       fsm_state, busy, fsm_vrf_wren, fsm_s_offset_en
//   Decode:    funct6_r, cfg_sew, vs1_addr_eff, vs2_addr_eff, vd_addr_eff
//   Lane data: rs1_data_lane0, rs2_data_lane0, wb_lane0
//   VRF wb:    vrf_waddr_eff, vrf_we0_eff, wb_result_lane0..3
//
// Run: vsim -do run_wave_alu_sim.do

module tb_wave_alu;

    localparam [6:0] OPCODE_OPV = 7'b101_0111;
    localparam [5:0] VADD  = 6'h00, VSUB  = 6'h02;
    localparam [5:0] VMUL  = 6'h25, VMULH = 6'h27;
    localparam [5:0] VAND  = 6'h09, VOR   = 6'h0A, VXOR = 6'h0B;
    localparam [5:0] VSLL  = 6'h15, VSRL  = 6'h10, VSRA = 6'h12;
    localparam [5:0] VMINU = 6'h04, VMAX  = 6'h07;

    localparam [10:0] ZIMM_E32_M1 = 11'h0D0;

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
        t = 0; while ((busy !== 1'b1) && (t < 200)) begin @(posedge clk); t++; end
        t = 0; while ((busy !== 1'b0) && (t < 2000)) begin @(posedge clk); t++; end
    endtask

    initial begin
        clk = 0; rst_n = 0; instr_valid = 0;
        instruction = 0; rs1_scalar_data = 0; rs2_scalar_data = 0;
        vrf_commit_en = 1'b1;

        repeat(4) @(negedge clk);
        rst_n = 1;
        repeat(2) @(negedge clk);

        // ── vsetvli e32, m1, avl=4 ──────────────────────────────────────────
        $display("\n[WAVE_ALU] Step 1: vsetvli e32 m1 avl=4");
        issue(build_vsetvli(ZIMM_E32_M1, 5'd0, 5'd1), 32'd4, 32'd0);
        wait_done;

        // ── Load operands into VRF ───────────────────────────────────────────
        // v1 = {0x00000001, 0x00000002, 0x00000003, 0x00000004} per lane
        // v2 = {0x0000000A, 0x00000014, 0x0000001E, 0x00000028} per lane
        vrf_write4(1, 32'h0000_0001, 32'h0000_0002, 32'h0000_0003, 32'h0000_0004);
        vrf_write4(2, 32'h0000_000A, 32'h0000_0014, 32'h0000_001E, 32'h0000_0028);

        // ── vadd.vv v4 = v1 + v2 ────────────────────────────────────────────
        $display("[WAVE_ALU] Step 2: vadd.vv v4, v2, v1");
        issue(build_opv(VADD, 1'b1, 3'b000, 5'd1, 5'd2, 5'd4), 32'd0, 32'd0);
        wait_done;
        $display("[WAVE_ALU]  v4[lane0]=0x%08X (exp=0x0000000B)", dut.vrf_lane0.bank0[4]);

        // ── vsub.vv v5 = v2 - v1 ────────────────────────────────────────────
        $display("[WAVE_ALU] Step 3: vsub.vv v5, v1, v2");
        issue(build_opv(VSUB, 1'b1, 3'b000, 5'd1, 5'd2, 5'd5), 32'd0, 32'd0);
        wait_done;
        $display("[WAVE_ALU]  v5[lane0]=0x%08X (exp=0x00000009)", dut.vrf_lane0.bank0[5]);

        // ── vmul.vv v6 = v1 * v2 ────────────────────────────────────────────
        $display("[WAVE_ALU] Step 4: vmul.vv v6, v2, v1");
        issue(build_opv(VMUL, 1'b1, 3'b000, 5'd1, 5'd2, 5'd6), 32'd0, 32'd0);
        wait_done;
        $display("[WAVE_ALU]  v6[lane0]=0x%08X (exp=0x0000000A)", dut.vrf_lane0.bank0[6]);

        // ── vand.vv v7 = v1 & v2 ────────────────────────────────────────────
        $display("[WAVE_ALU] Step 5: vand.vv v7, v2, v1");
        issue(build_opv(VAND, 1'b1, 3'b000, 5'd1, 5'd2, 5'd7), 32'd0, 32'd0);
        wait_done;

        // ── vsll.vx v8 = v1 << rs1=3 ────────────────────────────────────────
        $display("[WAVE_ALU] Step 6: vsll.vx v8, v1, rs1=3");
        issue(build_opv(VSLL, 1'b1, 3'b100, 5'd1, 5'd0, 5'd8), 32'd3, 32'd0);
        wait_done;
        $display("[WAVE_ALU]  v8[lane0]=0x%08X (exp=0x00000008)", dut.vrf_lane0.bank0[8]); // 1<<3=8

        // ── vsra.vx v9 = v2 >> rs1=2 (arithmetic) ───────────────────────────
        $display("[WAVE_ALU] Step 7: vsra.vx v9, v2, rs1=2");
        issue(build_opv(VSRA, 1'b1, 3'b100, 5'd2, 5'd0, 5'd9), 32'd2, 32'd0);
        wait_done;
        $display("[WAVE_ALU]  v9[lane0]=0x%08X (exp=0x00000002)", dut.vrf_lane0.bank0[9]); // 0xA>>2=2

        // ── vmulh.vv v10 = mulh(v1, v2) ─────────────────────────────────────
        $display("[WAVE_ALU] Step 8: vmulh.vv v10, v2, v1");
        issue(build_opv(VMULH, 1'b1, 3'b000, 5'd1, 5'd2, 5'd10), 32'd0, 32'd0);
        wait_done;
        $display("[WAVE_ALU]  v10[lane0]=0x%08X (exp=0x00000000 for small vals)",
                 dut.vrf_lane0.bank0[10]);

        repeat(10) @(posedge clk);
        $display("[WAVE_ALU] Done. Capture waveform now.");
        $finish;
    end

endmodule
