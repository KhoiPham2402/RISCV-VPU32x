`timescale 1ns / 1ps

// Pipelined VPU regression testbench.
// Identical test suite as tb_vproc_all_instr but DUT = vproc_system_wrapper_p.
// wait_done() waits for busy=0, which correctly includes the new ST_DRAIN cycle.
//
// Run: vsim -do run_pipeline_sim.do

module tb_pipeline_regression;

    // ─── Opcodes / funct6 ───────────────────────────────────────────────────
    localparam [6:0] OPCODE_OPV = 7'b101_0111;

    localparam [10:0] ZIMM_E32_M1 = 11'h0D0;
    localparam [10:0] ZIMM_E32_M2 = 11'h0D1;

    localparam [5:0] VADD    = 6'h00;
    localparam [5:0] VSUB    = 6'h02;
    localparam [5:0] VRSUB   = 6'h03;
    localparam [5:0] VMINU   = 6'h04;
    localparam [5:0] VMIN    = 6'h05;
    localparam [5:0] VMAXU   = 6'h06;
    localparam [5:0] VMAX    = 6'h07;
    localparam [5:0] VAND    = 6'h09;
    localparam [5:0] VOR     = 6'h0A;
    localparam [5:0] VXOR    = 6'h0B;
    localparam [5:0] VREDSUM = 6'h0C;
    localparam [5:0] VREDMAX = 6'h0D;
    localparam [5:0] VREDMAXU= 6'h0E;
    localparam [5:0] VREDMIN = 6'h0F;
    localparam [5:0] VSRL    = 6'h10;
    localparam [5:0] VSRA    = 6'h12;
    localparam [5:0] VREDMINU= 6'h14;
    localparam [5:0] VSLL    = 6'h15;
    localparam [5:0] VCMPEQ  = 6'h18;
    localparam [5:0] VCMPLTU = 6'h1A;
    localparam [5:0] VCMPLT  = 6'h1B;
    localparam [5:0] VMULHU  = 6'h24;
    localparam [5:0] VMUL    = 6'h25;
    localparam [5:0] VMULHSU = 6'h26;
    localparam [5:0] VMULH   = 6'h27;
    localparam [5:0] VADDWU  = 6'h30;
    localparam [5:0] VADDW   = 6'h31;
    localparam [5:0] VSUBWU  = 6'h32;
    localparam [5:0] VSUBW   = 6'h33;
    localparam [5:0] VMULWU  = 6'h38;
    localparam [5:0] VMULWSU = 6'h3A;
    localparam [5:0] VMULW   = 6'h3B;

    // ─── Signals ────────────────────────────────────────────────────────────
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
    wire [3:0]  fsm_state;
    wire [31:0] wb_result_lane0, wb_result_lane1, wb_result_lane2, wb_result_lane3;
    wire        vpu_ready;
    wire        vpu_cfg_done;
    wire [31:0] vpu_vl_remain;
    wire [31:0] csr_vl_o;
    wire [31:0] csr_vtype_o;
    wire [31:0] csr_vlenb_o;
    wire [11:0] scalar_csr_addr;
    wire [31:0] scalar_csr_rdata;

    wire        vlsu_mem_req;
    wire        vlsu_mem_we;
    wire [31:0] vlsu_mem_addr;
    wire [3:0]  vlsu_mem_be;
    wire [31:0] vlsu_mem_wdata;
    wire        vlsu_busy_o;

    integer pass_count, fail_count;

    // ─── DUT: pipelined VPU wrapper ─────────────────────────────────────────
    vproc_system_wrapper_p dut (
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
        .vlsu_mem_ready   (1'b1),         // synchronous DMEM model: always ready
        .vlsu_busy_o      (vlsu_busy_o)
    );

    assign scalar_csr_addr = 12'h000;

    always #5 clk = ~clk;

    // ─── Instruction helpers ────────────────────────────────────────────────
    function automatic [31:0] build_opv(
        input [5:0] funct6, input vm,
        input [2:0] funct3, input [4:0] vs1, vs2, vd
    );
        build_opv          = 32'd0;
        build_opv[6:0]     = OPCODE_OPV;
        build_opv[11:7]    = vd;
        build_opv[14:12]   = funct3;
        build_opv[19:15]   = vs1;
        build_opv[24:20]   = vs2;
        build_opv[25]      = vm;
        build_opv[31:26]   = funct6;
    endfunction

    function automatic [31:0] build_vsetvli(
        input [10:0] zimm11, input [4:0] vd, rs1_idx
    );
        build_vsetvli          = 32'd0;
        build_vsetvli[6:0]     = OPCODE_OPV;
        build_vsetvli[14:12]   = 3'b111;
        build_vsetvli[19:15]   = rs1_idx;
        build_vsetvli[11:7]    = vd;
        build_vsetvli[30:20]   = zimm11;
        build_vsetvli[31]      = 1'b0;
    endfunction

    // Direct VRF read (for result checking)
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
            default: vrf_word = 32'h0;
        endcase
    endfunction

    // Direct VRF write
    task automatic vrf_write4(input int v, input [31:0] w0, w1, w2, w3);
        begin
            {dut.vrf_lane0.bank3[v],dut.vrf_lane0.bank2[v],
             dut.vrf_lane0.bank1[v],dut.vrf_lane0.bank0[v]} = w0;
            {dut.vrf_lane1.bank3[v],dut.vrf_lane1.bank2[v],
             dut.vrf_lane1.bank1[v],dut.vrf_lane1.bank0[v]} = w1;
            {dut.vrf_lane2.bank3[v],dut.vrf_lane2.bank2[v],
             dut.vrf_lane2.bank1[v],dut.vrf_lane2.bank0[v]} = w2;
            {dut.vrf_lane3.bank3[v],dut.vrf_lane3.bank2[v],
             dut.vrf_lane3.bank1[v],dut.vrf_lane3.bank0[v]} = w3;
        end
    endtask

    // Issue one instruction
    task automatic issue(input [31:0] inst, input [31:0] rs1v, rs2v);
        begin
            @(negedge clk);
            instruction     = inst;
            rs1_scalar_data = rs1v;
            rs2_scalar_data = rs2v;
            instr_valid     = 1'b1;
            @(negedge clk);
            instr_valid     = 1'b0;
        end
    endtask

    // Wait for FSM idle — correctly handles ST_DRAIN (still busy=1) + ST_IDLE
    task automatic wait_done;
        int t;
        begin
            t = 0;
            while ((busy !== 1'b1) && (t < 300)) begin @(posedge clk); t++; end
            t = 0;
            while ((busy !== 1'b0) && (t < 5000)) begin @(posedge clk); t++; end
            if (t >= 5000) $display("*** wait_done TIMEOUT ***");
        end
    endtask

    // ─── Check helpers ──────────────────────────────────────────────────────
    task automatic check_u32(input string tag, input [31:0] got, exp);
        begin
            if (got === exp) begin
                pass_count++;
                $display("[PASS] %s", tag);
            end else begin
                fail_count++;
                $display("[FAIL] %s | got=%08h exp=%08h", tag, got, exp);
            end
        end
    endtask

    task automatic check_vd4(input string tag, input int vd,
                              input [31:0] e0, e1, e2, e3);
        begin
            check_u32({tag," L0"}, vrf_word(0,vd), e0);
            check_u32({tag," L1"}, vrf_word(1,vd), e1);
            check_u32({tag," L2"}, vrf_word(2,vd), e2);
            check_u32({tag," L3"}, vrf_word(3,vd), e3);
        end
    endtask

    // ─── Instruction runners ────────────────────────────────────────────────
    task automatic run_vv(input [5:0] f6, input int vd, vs2, vs1,
                          input [31:0] e0, e1, e2, e3);
        begin
            issue(build_opv(f6,1'b1,3'b000,vs1[4:0],vs2[4:0],vd[4:0]),32'd0,32'd0);
            wait_done();
            check_vd4($sformatf("VV f6=%02h vd=v%0d",f6,vd), vd, e0,e1,e2,e3);
        end
    endtask

    task automatic run_vx(input [5:0] f6, input int vd, vs2,
                          input [31:0] rs1, input [31:0] e0, e1, e2, e3);
        begin
            issue(build_opv(f6,1'b1,3'b100,5'd0,vs2[4:0],vd[4:0]),rs1,32'd0);
            wait_done();
            check_vd4($sformatf("VX f6=%02h vd=v%0d rs1=%08h",f6,vd,rs1), vd, e0,e1,e2,e3);
        end
    endtask

    task automatic run_vi(input [5:0] f6, input int vd, vs2, input int imm5,
                          input [31:0] e0, e1, e2, e3);
        begin
            issue(build_opv(f6,1'b1,3'b011,imm5[4:0],vs2[4:0],vd[4:0]),32'd0,32'd0);
            wait_done();
            check_vd4($sformatf("VI f6=%02h vd=v%0d imm=%0d",f6,vd,imm5), vd, e0,e1,e2,e3);
        end
    endtask

    task automatic run_cmp(input [5:0] f6, input int vd, vs2, vs1,
                           input [31:0] mask_exp);
        begin
            issue(build_opv(f6,1'b1,3'b000,vs1[4:0],vs2[4:0],vd[4:0]),32'd0,32'd0);
            wait_done();
            check_u32($sformatf("CMP VV f6=%02h vd=v%0d L0",f6,vd), vrf_word(0,vd), mask_exp);
            check_u32($sformatf("CMP VV f6=%02h vd=v%0d L1",f6,vd), vrf_word(1,vd), 32'h0);
            check_u32($sformatf("CMP VV f6=%02h vd=v%0d L2",f6,vd), vrf_word(2,vd), 32'h0);
            check_u32($sformatf("CMP VV f6=%02h vd=v%0d L3",f6,vd), vrf_word(3,vd), 32'h0);
        end
    endtask

    task automatic run_cmp_vx(input [5:0] f6, input int vd, vs2,
                               input [31:0] rs1, input [31:0] mask_exp);
        begin
            issue(build_opv(f6,1'b1,3'b100,5'd0,vs2[4:0],vd[4:0]),rs1,32'd0);
            wait_done();
            check_u32($sformatf("CMP VX f6=%02h vd=v%0d L0",f6,vd), vrf_word(0,vd), mask_exp);
            check_u32($sformatf("CMP VX f6=%02h vd=v%0d L1",f6,vd), vrf_word(1,vd), 32'h0);
            check_u32($sformatf("CMP VX f6=%02h vd=v%0d L2",f6,vd), vrf_word(2,vd), 32'h0);
            check_u32($sformatf("CMP VX f6=%02h vd=v%0d L3",f6,vd), vrf_word(3,vd), 32'h0);
        end
    endtask

    task automatic run_red(input [5:0] f6, input int vd, vs2, vs1,
                           input [31:0] exp_l0);
        begin
            issue(build_opv(f6,1'b1,3'b000,vs1[4:0],vs2[4:0],vd[4:0]),32'd0,32'd0);
            wait_done();
            check_u32($sformatf("RED f6=%02h vd=v%0d L0",f6,vd), vrf_word(0,vd), exp_l0);
        end
    endtask

    task automatic run_mvv(input [5:0] f6, input int vd, vs2, vs1,
                           input [31:0] e0, e1, e2, e3);
        begin
            issue(build_opv(f6,1'b1,3'b010,vs1[4:0],vs2[4:0],vd[4:0]),32'd0,32'd0);
            wait_done();
            check_vd4($sformatf("MVV f6=%02h vd=v%0d",f6,vd), vd, e0,e1,e2,e3);
        end
    endtask

    task automatic run_mvx(input [5:0] f6, input int vd, vs2,
                            input [31:0] rs1, input [31:0] e0, e1, e2, e3);
        begin
            issue(build_opv(f6,1'b1,3'b110,5'd0,vs2[4:0],vd[4:0]),rs1,32'd0);
            wait_done();
            check_vd4($sformatf("MVX f6=%02h vd=v%0d rs1=%08h",f6,vd,rs1), vd, e0,e1,e2,e3);
        end
    endtask

    // ─── Main test body ─────────────────────────────────────────────────────
    initial begin
        clk             = 0;
        rst_n           = 0;
        instr_valid     = 0;
        instruction     = 0;
        rs1_scalar_data = 0;
        rs2_scalar_data = 0;
        vrf_commit_en   = 1;
        pass_count      = 0;
        fail_count      = 0;

        $display("=== tb_pipeline_regression: pipelined VPU regression ===");

        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // ── §1 CONFIG ────────────────────────────────────────────────────
        $display("--- CONFIG ---");
        issue(build_vsetvli(ZIMM_E32_M1, 5'd0, 5'd0), 32'd4, 32'd0);
        wait_done();
        check_u32("CONFIG csr_vl",        csr_vl_o,         32'd4);
        check_u32("CONFIG csr_vtype[7:0]", csr_vtype_o[7:0], 8'hD0);

        // ── §2 Integer ALU VV ────────────────────────────────────────────
        $display("--- ALU VV ---");
        vrf_write4(1, 32'd100, 32'd200, 32'd300, 32'd400);
        vrf_write4(2, 32'd10,  32'd20,  32'd30,  32'd40);

        run_vv(VADD, 20, 1, 2, 32'd110,  32'd220,  32'd330,  32'd440);
        run_vv(VSUB, 20, 1, 2, 32'd90,   32'd180,  32'd270,  32'd360);
        run_vv(VMUL, 20, 1, 2, 32'd1000, 32'd4000, 32'd9000, 32'd16000);

        // ── §3 ALU VX / VI ───────────────────────────────────────────────
        $display("--- ALU VX/VI ---");
        run_vx(VADD, 20, 1, 32'd5,  32'd105, 32'd205, 32'd305, 32'd405);
        run_vx(VSUB, 20, 1, 32'd50, 32'd50,  32'd150, 32'd250, 32'd350);
        run_vi(VADD, 20, 2, 5'd7,   32'd17,  32'd27,  32'd37,  32'd47);

        // ── §4 VRSUB ─────────────────────────────────────────────────────
        $display("--- VRSUB ---");
        vrf_write4(3, 32'd1, 32'd2, 32'd3, 32'd4);
        run_vx(VRSUB, 20, 3, 32'd10, 32'd9,  32'd8,  32'd7,  32'd6);
        run_vi(VRSUB, 20, 3, 5'd15,  32'd14, 32'd13, 32'd12, 32'd11);

        // ── §5 Logic ─────────────────────────────────────────────────────
        $display("--- Logic ---");
        vrf_write4(4, 32'hAAAA_AAAA, 32'hAAAA_AAAA, 32'hAAAA_AAAA, 32'hAAAA_AAAA);
        vrf_write4(5, 32'h5555_5555, 32'h5555_5555, 32'h5555_5555, 32'h5555_5555);
        run_vv(VAND, 20, 4, 5, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000);
        run_vv(VOR,  20, 4, 5, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF);
        run_vv(VXOR, 20, 4, 5, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF);

        // ── §6 Shifts ─────────────────────────────────────────────────────
        $display("--- Shifts ---");
        run_vi(VSLL, 20, 2, 5'd2, 32'd40,  32'd80,  32'd120, 32'd160);
        run_vi(VSRL, 20, 1, 5'd2, 32'd25,  32'd50,  32'd75,  32'd100);
        vrf_write4(6, 32'hFFFF_FF9C, 32'hFFFF_FF38, 32'hFFFF_FED4, 32'hFFFF_FE70);
        run_vi(VSRA, 20, 6, 5'd2,
               32'hFFFF_FFE7, 32'hFFFF_FFCE, 32'hFFFF_FFB5, 32'hFFFF_FF9C);

        // ── §7 VMIN / VMAX ────────────────────────────────────────────────
        $display("--- VMIN/VMAX (positive) ---");
        run_vv(VMIN,  20, 1, 2, 32'd10,  32'd20,  32'd30,  32'd40);
        run_vv(VMAX,  20, 1, 2, 32'd100, 32'd200, 32'd300, 32'd400);
        run_vv(VMINU, 20, 1, 2, 32'd10,  32'd20,  32'd30,  32'd40);
        run_vv(VMAXU, 20, 1, 2, 32'd100, 32'd200, 32'd300, 32'd400);

        $display("--- VMIN/VMAX (mixed sign) ---");
        run_vv(VMIN,  20, 6, 2,
               32'hFFFF_FF9C, 32'hFFFF_FF38, 32'hFFFF_FED4, 32'hFFFF_FE70);
        run_vv(VMAX,  20, 6, 2, 32'd10, 32'd20, 32'd30, 32'd40);
        run_vv(VMINU, 20, 6, 2, 32'd10, 32'd20, 32'd30, 32'd40);
        run_vv(VMAXU, 20, 6, 2,
               32'hFFFF_FF9C, 32'hFFFF_FF38, 32'hFFFF_FED4, 32'hFFFF_FE70);

        // ── §8 Compare ────────────────────────────────────────────────────
        $display("--- Compare ---");
        vrf_write4(7,  32'd5,  32'd5,  32'd5,  32'd5);
        vrf_write4(8,  32'd5,  32'd5,  32'd5,  32'd5);
        run_cmp(VCMPEQ, 27, 7, 8, 32'h0000_000F);

        vrf_write4(9,  32'd1, 32'd2, 32'd3, 32'd4);
        run_cmp(VCMPEQ, 27, 7, 9, 32'h0000_0000);

        vrf_write4(10, 32'd5, 32'd99, 32'd5, 32'd99);
        run_cmp(VCMPEQ, 27, 10, 7, 32'h0000_0005);

        vrf_write4(11, 32'd10, 32'd10, 32'd10, 32'd10);
        run_cmp(VCMPLT, 27, 9, 11, 32'h0000_000F);

        vrf_write4(12, 32'd5, 32'd15, 32'd5, 32'd15);
        run_cmp(VCMPLT, 27, 12, 11, 32'h0000_0005);

        run_cmp_vx(VCMPLTU, 27, 9, 32'd10, 32'h0000_000F);

        // ── §9 VMULH family ───────────────────────────────────────────────
        $display("--- VMULH family ---");
        vrf_write4(13, 32'h0001_0000, 32'h0001_0000, 32'h0001_0000, 32'h0001_0000);
        vrf_write4(14, 32'h0001_0000, 32'h0001_0000, 32'h0001_0000, 32'h0001_0000);
        run_vv(VMULH,   20, 13, 14, 32'h0000_0001, 32'h0000_0001, 32'h0000_0001, 32'h0000_0001);

        vrf_write4(13, 32'h8000_0000, 32'h8000_0000, 32'h8000_0000, 32'h8000_0000);
        run_vv(VMULHU,  20, 13, 13, 32'h4000_0000, 32'h4000_0000, 32'h4000_0000, 32'h4000_0000);

        vrf_write4(14, 32'h0000_0002, 32'h0000_0002, 32'h0000_0002, 32'h0000_0002);
        run_vv(VMULHSU, 20, 13, 14, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF);

        // ── §10 Widening ──────────────────────────────────────────────────
        $display("--- Widening ---");
        vrf_write4(15, 32'd50, 32'd50, 32'd50, 32'd50);
        vrf_write4(16, 32'd7,  32'd8,  32'd9,  32'd10);
        issue(build_opv(VADDW,1'b1,3'b000,5'd16,5'd15,5'd18), 32'd0, 32'd0);
        wait_done();
        check_vd4("VWADD lo v18", 18, 32'd57, 32'd58, 32'd59, 32'd60);
        check_vd4("VWADD hi v19", 19, 32'd0,  32'd0,  32'd0,  32'd0);

        vrf_write4(15, 32'd100, 32'd100, 32'd100, 32'd100);
        vrf_write4(16, 32'd5,   32'd5,   32'd5,   32'd5);
        issue(build_opv(VSUBW,1'b1,3'b000,5'd16,5'd15,5'd18), 32'd0, 32'd0);
        wait_done();
        check_vd4("VSUBW lo v18", 18, 32'd95, 32'd95, 32'd95, 32'd95);

        vrf_write4(15, 32'd50, 32'd50, 32'd50, 32'd50);
        vrf_write4(16, 32'd7,  32'd8,  32'd9,  32'd10);
        issue(build_opv(VADDWU,1'b1,3'b000,5'd16,5'd15,5'd18), 32'd0, 32'd0);
        wait_done();
        check_vd4("VADDWU lo v18", 18, 32'd57, 32'd58, 32'd59, 32'd60);

        vrf_write4(15, 32'd3, 32'd3, 32'd3, 32'd3);
        vrf_write4(16, 32'd4, 32'd4, 32'd4, 32'd4);
        issue(build_opv(VMULW,1'b1,3'b000,5'd16,5'd15,5'd18), 32'd0, 32'd0);
        wait_done();
        check_vd4("VMULW lo v18", 18, 32'd12, 32'd12, 32'd12, 32'd12);

        issue(build_opv(VMULWU,1'b1,3'b000,5'd16,5'd15,5'd18), 32'd0, 32'd0);
        wait_done();
        check_vd4("VMULWU lo v18", 18, 32'd12, 32'd12, 32'd12, 32'd12);

        vrf_write4(15, 32'd200, 32'd200, 32'd200, 32'd200);
        vrf_write4(16, 32'd30,  32'd30,  32'd30,  32'd30);
        issue(build_opv(VSUBWU,1'b1,3'b000,5'd16,5'd15,5'd18), 32'd0, 32'd0);
        wait_done();
        check_vd4("VSUBWU lo v18", 18, 32'd170, 32'd170, 32'd170, 32'd170);

        issue(build_opv(VMULWSU,1'b1,3'b000,5'd16,5'd15,5'd18), 32'd0, 32'd0);
        wait_done();
        check_vd4("VMULWSU lo v18", 18, 32'd6000, 32'd6000, 32'd6000, 32'd6000);

        // ── §11 LMUL=2 ───────────────────────────────────────────────────
        $display("--- LMUL=2 ---");
        issue(build_vsetvli(ZIMM_E32_M2, 5'd0, 5'd0), 32'd8, 32'd0);
        wait_done();
        check_u32("LMUL=2 csr_vl", csr_vl_o, 32'd8);

        vrf_write4(4, 32'd1, 32'd2, 32'd3, 32'd4);
        vrf_write4(5, 32'd5, 32'd6, 32'd7, 32'd8);
        vrf_write4(8, 32'd10, 32'd10, 32'd10, 32'd10);
        vrf_write4(9, 32'd20, 32'd20, 32'd20, 32'd20);

        issue(build_opv(VADD,1'b1,3'b000,5'd4,5'd8,5'd21), 32'd0, 32'd0);
        wait_done();
        check_vd4("LMUL=2 VADD v21", 21, 32'd11, 32'd12, 32'd13, 32'd14);
        check_vd4("LMUL=2 VADD v22", 22, 32'd25, 32'd26, 32'd27, 32'd28);

        issue(build_vsetvli(ZIMM_E32_M1, 5'd0, 5'd0), 32'd4, 32'd0);
        wait_done();

        // ── §12 Reductions ────────────────────────────────────────────────
        $display("--- Reductions ---");
        vrf_write4(20, 32'd5,  32'd12, 32'd3,  32'd8);
        vrf_write4(24, 32'd0,  32'd0,  32'd0,  32'd0);
        run_red(VREDSUM,  30, 20, 24, 32'd28);
        run_red(VREDMAX,  30, 20, 24, 32'd12);

        vrf_write4(21, 32'hFFFF_FFFB, 32'hFFFF_FFF4, 32'hFFFF_FFFD, 32'hFFFF_FFF8);
        run_red(VREDMIN,  30, 21, 24, 32'hFFFF_FFF4);

        vrf_write4(22, 32'hFFFF_FFF0, 32'd1, 32'd2, 32'd3);
        run_red(VREDMAXU, 30, 22, 24, 32'hFFFF_FFF0);

        vrf_write4(23, 32'd0, 32'd5, 32'd3, 32'd2);
        run_red(VREDMINU, 30, 23, 24, 32'd0);

        // ── §13 OPMVV / OPMVX ────────────────────────────────────────────
        $display("--- OPMVV (funct3=010) ---");
        vrf_write4(1, 32'd2,  32'd3,  32'd4,  32'd5);
        vrf_write4(2, 32'd10, 32'd10, 32'd10, 32'd10);
        run_mvv(VMUL,    20, 1, 2, 32'd20, 32'd30, 32'd40, 32'd50);

        vrf_write4(1, 32'h4000_0000, 32'h4000_0000, 32'h4000_0000, 32'h4000_0000);
        vrf_write4(2, 32'd4,         32'd4,         32'd4,         32'd4);
        run_mvv(VMULH,   20, 1, 2, 32'd1, 32'd1, 32'd1, 32'd1);

        vrf_write4(1, 32'h8000_0000, 32'h8000_0000, 32'h8000_0000, 32'h8000_0000);
        vrf_write4(2, 32'd2,         32'd2,         32'd2,         32'd2);
        run_mvv(VMULHU,  20, 1, 2, 32'd1, 32'd1, 32'd1, 32'd1);

        vrf_write4(1, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF);
        run_mvv(VMULHSU, 20, 1, 2, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF);

        $display("--- OPMVX (funct3=110) ---");
        vrf_write4(3, 32'd2, 32'd4, 32'd6, 32'd8);
        run_mvx(VMUL,    20, 3, 32'd3, 32'd6, 32'd12, 32'd18, 32'd24);

        vrf_write4(4, 32'h4000_0000, 32'h4000_0000, 32'h4000_0000, 32'h4000_0000);
        run_mvx(VMULH,   20, 4, 32'd4, 32'd1, 32'd1, 32'd1, 32'd1);

        vrf_write4(4, 32'h8000_0000, 32'h8000_0000, 32'h8000_0000, 32'h8000_0000);
        run_mvx(VMULHU,  20, 4, 32'd2, 32'd1, 32'd1, 32'd1, 32'd1);

        run_mvx(VMULHSU, 20, 4, 32'd2, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFF);

        // ── Summary ──────────────────────────────────────────────────────
        $display("=== Summary: PASS=%0d  FAIL=%0d ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("=== RESULT: ALL PASS ===");
        else
            $display("=== RESULT: %0d FAIL ===", fail_count);
        #20;
        $finish;
    end

endmodule
