`timescale 1ns / 1ps

// VMERGE end-to-end test trên vproc_system_wrapper.
// - Cấu hình lần lượt e8/e16/e32 (m1, vl=4)
// - Nạp v0 (reg v0), v1 (vs1), v2 (vs2)
// - Issue VMERGE vv: vd=v3, vs2=v2, vs1=v1
// - So sánh kết quả ở VRF từng lane.

module tb_vproc_vmerge;
    localparam [6:0] OPCODE_OPV = 7'b101_0111;
    localparam [5:0] VMERGE     = 6'b010111;

    // zimm[7:0] = {vma,vta,vsew[2:0],vlmul[2:0]}, chọn m1.
    localparam [10:0] ZIMM_E8_M1  = 11'h0C0; // vsew=000, vlmul=000
    localparam [10:0] ZIMM_E16_M1 = 11'h0C8; // vsew=001, vlmul=000
    localparam [10:0] ZIMM_E32_M1 = 11'h0D0; // vsew=010, vlmul=000

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
    wire [31:0] wb_result_lane0, wb_result_lane1, wb_result_lane2, wb_result_lane3;
    wire        vpu_ready;
    wire        vpu_cfg_done;
    wire [31:0] vpu_vl_remain;
    wire [31:0] csr_vl_o;
    wire [31:0] csr_vtype_o;
    wire [31:0] csr_vlenb_o;
    wire [31:0] scalar_csr_rdata;

    integer pass_count;
    integer fail_count;

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
        .scalar_csr_addr (12'h000),
        .scalar_csr_rdata(scalar_csr_rdata)
    );

    always #5 clk = ~clk;

    function automatic [31:0] build_opv(
        input [5:0] funct6,
        input       vm,
        input [2:0] funct3,
        input [4:0] vs1,
        input [4:0] vs2,
        input [4:0] vd
    );
        begin
            build_opv = 32'd0;
            build_opv[6:0]   = OPCODE_OPV;
            build_opv[11:7]  = vd;
            build_opv[14:12] = funct3;
            build_opv[19:15] = vs1;
            build_opv[24:20] = vs2;
            build_opv[25]    = vm;
            build_opv[31:26] = funct6;
        end
    endfunction

    function automatic [31:0] build_vsetvli(
        input [10:0] zimm11,
        input [4:0]  vd,
        input [4:0]  rs1_idx
    );
        begin
            build_vsetvli = 32'd0;
            build_vsetvli[6:0]   = OPCODE_OPV;
            build_vsetvli[14:12] = 3'b111;
            build_vsetvli[19:15] = rs1_idx;
            build_vsetvli[11:7]  = vd;
            build_vsetvli[30:20] = zimm11;
            build_vsetvli[31]    = 1'b0;
        end
    endfunction

    function automatic [31:0] vrf_word(input integer lane, input integer v);
        begin
            case (lane)
                0: vrf_word = {dut.vrf_lane0.bank3[v], dut.vrf_lane0.bank2[v], dut.vrf_lane0.bank1[v], dut.vrf_lane0.bank0[v]};
                1: vrf_word = {dut.vrf_lane1.bank3[v], dut.vrf_lane1.bank2[v], dut.vrf_lane1.bank1[v], dut.vrf_lane1.bank0[v]};
                2: vrf_word = {dut.vrf_lane2.bank3[v], dut.vrf_lane2.bank2[v], dut.vrf_lane2.bank1[v], dut.vrf_lane2.bank0[v]};
                3: vrf_word = {dut.vrf_lane3.bank3[v], dut.vrf_lane3.bank2[v], dut.vrf_lane3.bank1[v], dut.vrf_lane3.bank0[v]};
                default: vrf_word = 32'h0;
            endcase
        end
    endfunction

    task automatic vrf_write4(input integer v, input [31:0] w0, w1, w2, w3);
        begin
            {dut.vrf_lane0.bank3[v], dut.vrf_lane0.bank2[v], dut.vrf_lane0.bank1[v], dut.vrf_lane0.bank0[v]} = w0;
            {dut.vrf_lane1.bank3[v], dut.vrf_lane1.bank2[v], dut.vrf_lane1.bank1[v], dut.vrf_lane1.bank0[v]} = w1;
            {dut.vrf_lane2.bank3[v], dut.vrf_lane2.bank2[v], dut.vrf_lane2.bank1[v], dut.vrf_lane2.bank0[v]} = w2;
            {dut.vrf_lane3.bank3[v], dut.vrf_lane3.bank2[v], dut.vrf_lane3.bank1[v], dut.vrf_lane3.bank0[v]} = w3;
        end
    endtask

    task automatic issue(input [31:0] inst, input [31:0] rs1v, input [31:0] rs2v);
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

    task automatic wait_done;
        integer t;
        begin
            t = 0;
            while ((busy !== 1'b1) && (t < 200)) begin
                @(posedge clk);
                t = t + 1;
            end
            t = 0;
            while ((busy !== 1'b0) && (t < 2000)) begin
                @(posedge clk);
                t = t + 1;
            end
            if (t >= 2000) begin
                fail_count = fail_count + 1;
                $display("[FAIL] wait_done timeout");
            end
        end
    endtask

    task automatic check_lane4(
        input [255:0] tag,
        input [31:0] e0, e1, e2, e3
    );
        reg [31:0] g0, g1, g2, g3;
        begin
            g0 = vrf_word(0, 3);
            g1 = vrf_word(1, 3);
            g2 = vrf_word(2, 3);
            g3 = vrf_word(3, 3);
            if (g0 === e0 && g1 === e1 && g2 === e2 && g3 === e3) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s", tag);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s", tag);
                $display("       got L0=%08h L1=%08h L2=%08h L3=%08h", g0, g1, g2, g3);
                $display("       exp L0=%08h L1=%08h L2=%08h L3=%08h", e0, e1, e2, e3);
            end
        end
    endtask

    task automatic dump_operands(input [255:0] tag);
        begin
            $display("---- %0s operands ----", tag);
            $display("v0 (mask): L0=%08h L1=%08h L2=%08h L3=%08h",
                vrf_word(0, 0), vrf_word(1, 0), vrf_word(2, 0), vrf_word(3, 0));
            $display("vs1 (v1):  L0=%08h L1=%08h L2=%08h L3=%08h",
                vrf_word(0, 1), vrf_word(1, 1), vrf_word(2, 1), vrf_word(3, 1));
            $display("vs2 (v2):  L0=%08h L1=%08h L2=%08h L3=%08h",
                vrf_word(0, 2), vrf_word(1, 2), vrf_word(2, 2), vrf_word(3, 2));
        end
    endtask

    task automatic dump_inst_and_regs(
        input [255:0] tag,
        input [31:0]  inst,
        input integer vd_idx,
        input integer vs1_idx,
        input integer vs2_idx
    );
        begin
            $display("==== %0s ====", tag);
            $display("inst = %08h | opcode=%02h funct3=%0h funct6=%02h vm=%0b vd=v%0d vs1=v%0d vs2=v%0d",
                inst, inst[6:0], inst[14:12], inst[31:26], inst[25], inst[11:7], inst[19:15], inst[24:20]);
            $display("v0  : L0=%08h L1=%08h L2=%08h L3=%08h",
                vrf_word(0, 0), vrf_word(1, 0), vrf_word(2, 0), vrf_word(3, 0));
            $display("vs1 : L0=%08h L1=%08h L2=%08h L3=%08h",
                vrf_word(0, vs1_idx), vrf_word(1, vs1_idx), vrf_word(2, vs1_idx), vrf_word(3, vs1_idx));
            $display("vs2 : L0=%08h L1=%08h L2=%08h L3=%08h",
                vrf_word(0, vs2_idx), vrf_word(1, vs2_idx), vrf_word(2, vs2_idx), vrf_word(3, vs2_idx));
            $display("vd(before): L0=%08h L1=%08h L2=%08h L3=%08h",
                vrf_word(0, vd_idx), vrf_word(1, vd_idx), vrf_word(2, vd_idx), vrf_word(3, vd_idx));
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

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // v1 = nguồn chọn khi bit v0 = 1, v2 = nguồn khi bit v0 = 0
        vrf_write4(1, 32'hA1A2A3A4, 32'hB1B2B3B4, 32'hC1C2C3C4, 32'hD1D2D3D4);
        vrf_write4(2, 32'h11121314, 32'h21222324, 32'h31323334, 32'h41424344);

        // v0 (mask register) - dùng lane0 để tạo pattern bit cho split logic hiện tại.
        vrf_write4(0, 32'h0000_00A5, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000);

        // --- Case e8 ---
        issue(build_vsetvli(ZIMM_E8_M1, 5'd0, 5'd0), 32'd16, 32'd0);
        wait_done();
        dump_inst_and_regs("VMERGE e8",
            build_opv(VMERGE, 1'b0, 3'b000, 5'd1, 5'd2, 5'd3), 3, 1, 2);
        issue(build_opv(VMERGE, 1'b0, 3'b000, 5'd1, 5'd2, 5'd3), 32'd0, 32'd0);
        wait_done();
        $display("vd(after):  L0=%08h L1=%08h L2=%08h L3=%08h",
            vrf_word(0, 3), vrf_word(1, 3), vrf_word(2, 3), vrf_word(3, 3));
        // v0 low bits = 4'b0101 -> byte0/2 from vs1, byte1/3 from vs2
        check_lane4("VMERGE e8",
            32'h11A213A4, 32'h21B223B4, 32'h31C233C4, 32'h41D243D4);

        // --- Case e16 ---
        issue(build_vsetvli(ZIMM_E16_M1, 5'd0, 5'd0), 32'd8, 32'd0);
        wait_done();
        dump_inst_and_regs("VMERGE e16",
            build_opv(VMERGE, 1'b0, 3'b000, 5'd1, 5'd2, 5'd3), 3, 1, 2);
        issue(build_opv(VMERGE, 1'b0, 3'b000, 5'd1, 5'd2, 5'd3), 32'd0, 32'd0);
        wait_done();
        $display("vd(after):  L0=%08h L1=%08h L2=%08h L3=%08h",
            vrf_word(0, 3), vrf_word(1, 3), vrf_word(2, 3), vrf_word(3, 3));
        // v0 bits [1:0] = 2'b01 -> low16 from vs1, high16 from vs2
        check_lane4("VMERGE e16",
            32'h1112A3A4, 32'h2122B3B4, 32'h3132C3C4, 32'h4142D3D4);

        // --- Case e32 ---
        issue(build_vsetvli(ZIMM_E32_M1, 5'd0, 5'd0), 32'd4, 32'd0);
        wait_done();
        dump_inst_and_regs("VMERGE e32",
            build_opv(VMERGE, 1'b0, 3'b000, 5'd1, 5'd2, 5'd3), 3, 1, 2);
        issue(build_opv(VMERGE, 1'b0, 3'b000, 5'd1, 5'd2, 5'd3), 32'd0, 32'd0);
        wait_done();
        $display("vd(after):  L0=%08h L1=%08h L2=%08h L3=%08h",
            vrf_word(0, 3), vrf_word(1, 3), vrf_word(2, 3), vrf_word(3, 3));
        // lane0..lane3 dùng lần lượt v0 bits [0..3] = 1,0,1,0
        check_lane4("VMERGE e32",
            32'hA1A2A3A4, 32'h21222324, 32'hC1C2C3C4, 32'h41424344);

        $display("=== TB VMERGE summary: PASS=%0d FAIL=%0d ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("=== RESULT: ALL PASS ===");
        else
            $display("=== RESULT: SOME FAIL ===");

        #20;
        $finish;
    end

endmodule

