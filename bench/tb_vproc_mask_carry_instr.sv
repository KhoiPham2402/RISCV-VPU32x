`timescale 1ns / 1ps

module tb_vproc_mask_carry_instr;

    localparam [6:0] OPCODE_OPV = 7'b101_0111;
    localparam [5:0] VADC       = 6'b010000;
    localparam [5:0] VSBC       = 6'b010010;
    localparam [5:0] VMADC      = 6'b010001;
    localparam [5:0] VMSBC      = 6'b010011;
    localparam [10:0] ZIMM_E16_M4 = 11'b000_0000_1010; // vsew=001(16b), vlmul=010(m4)
    localparam [10:0] ZIMM_E16_M2 = 11'b000_0000_1001; // vsew=001(16b), vlmul=001(m2)
    localparam [10:0] ZIMM_E8_M1  = 11'b000_0000_0000; // vsew=000(8b),  vlmul=000(m1)

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
    wire [11:0] scalar_csr_addr;
    wire [31:0] scalar_csr_rdata;

    integer pass_count, fail_count;

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
        .scalar_csr_addr (scalar_csr_addr),
        .scalar_csr_rdata(scalar_csr_rdata)
    );

    assign scalar_csr_addr = 12'h000;
    always #5 clk = ~clk;

    function [31:0] build_opv;
        input [5:0] funct6;
        input       vm;
        input [2:0] funct3;
        input [4:0] vs1_or_imm;
        input [4:0] vs2;
        input [4:0] vd;
        begin
            build_opv = 32'd0;
            build_opv[6:0]   = OPCODE_OPV;
            build_opv[11:7]  = vd;
            build_opv[14:12] = funct3;
            build_opv[19:15] = vs1_or_imm;
            build_opv[24:20] = vs2;
            build_opv[25]    = vm;
            build_opv[31:26] = funct6;
        end
    endfunction

    function [31:0] build_vsetvli;
        input [10:0] zimm11;
        input [4:0]  vd;
        input [4:0]  rs1_idx;
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

    function [31:0] vrf_word;
        input integer lane;
        input integer reg_idx;
        begin
            case (lane)
                0: vrf_word = {dut.vrf_lane0.bank3[reg_idx], dut.vrf_lane0.bank2[reg_idx], dut.vrf_lane0.bank1[reg_idx], dut.vrf_lane0.bank0[reg_idx]};
                1: vrf_word = {dut.vrf_lane1.bank3[reg_idx], dut.vrf_lane1.bank2[reg_idx], dut.vrf_lane1.bank1[reg_idx], dut.vrf_lane1.bank0[reg_idx]};
                2: vrf_word = {dut.vrf_lane2.bank3[reg_idx], dut.vrf_lane2.bank2[reg_idx], dut.vrf_lane2.bank1[reg_idx], dut.vrf_lane2.bank0[reg_idx]};
                3: vrf_word = {dut.vrf_lane3.bank3[reg_idx], dut.vrf_lane3.bank2[reg_idx], dut.vrf_lane3.bank1[reg_idx], dut.vrf_lane3.bank0[reg_idx]};
                default: vrf_word = 32'h0;
            endcase
        end
    endfunction

    task issue_instr;
        input [255:0] name;
        input [31:0]  inst;
        begin
            $display("[ISSUE] %0s inst=%08h", name, inst);
            @(negedge clk);
            instruction = inst;
            instr_valid = 1'b1;
            @(negedge clk);
            instr_valid = 1'b0;
        end
    endtask

    task wait_finish;
        integer timeout;
        begin
            timeout = 0;
            while ((busy !== 1'b1) && (timeout < 100)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            timeout = 0;
            while ((busy !== 1'b0) && (timeout < 400)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
        end
    endtask

    // Chờ lệnh xong; trong lúc busy lấy mẫu mỗi chu kỳ (sau NBA) để quan sát EXEC/MASKING đa chu kỳ.
    task wait_finish_trace;
        input [255:0] tag;
        integer timeout;
        begin
            timeout = 0;
            while ((busy !== 1'b1) && (timeout < 100)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            timeout = 0;
            $display("[MCYC] %0s — trace each cycle while busy", tag);
            while ((busy !== 1'b0) && (timeout < 400)) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
                if (busy) begin
                    $display("  cyc=%0d FSM=%0d wren=%b vd=%0d vs2=%0d vs1=%0d mask16=%04h cleft=%0d elems=%0d",
                        timeout,
                        fsm_state,
                        dut.fsm_vrf_wren,
                        dut.vd_addr_eff,
                        dut.vs2_addr_eff,
                        dut.vs1_addr_eff,
                        vmask16,
                        dut.cycle_counter_inst.cycles_left,
                        dut.cycle_counter_inst.elems_curr_cycle);
                    if (fsm_state == 3'd5) begin
                        $display("    MASKING: wr_ptr=%0d buf[31:0]=%08h lane_mres0=%04h",
                            dut.mask_wr_ptr_dbg,
                            dut.mask_buffer_data[31:0],
                            dut.lane_mask_result0);
                    end
                    if (fsm_state == 3'd6)
                        $display("    FINAL_MASKING commit buf[31:0]=%08h", dut.mask_buffer_data[31:0]);
                end
            end
            $display("[MCYC] %0s — done (timeout=%0d)", tag, timeout);
        end
    endtask

    task check_u32;
        input [255:0] name;
        input [31:0] got;
        input [31:0] exp;
        begin
            if (got === exp) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s got=%08h", name, got);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s got=%08h exp=%08h", name, got, exp);
            end
        end
    endtask

    task dump_lane_inputs;
        input integer vs2_idx;
        input integer vs1_idx;
        begin
            $display("  VS2(v%0d): L0=%08h L1=%08h L2=%08h L3=%08h",
                vs2_idx, vrf_word(0,vs2_idx), vrf_word(1,vs2_idx), vrf_word(2,vs2_idx), vrf_word(3,vs2_idx));
            $display("  VS1(v%0d): L0=%08h L1=%08h L2=%08h L3=%08h",
                vs1_idx, vrf_word(0,vs1_idx), vrf_word(1,vs1_idx), vrf_word(2,vs1_idx), vrf_word(3,vs1_idx));
            $display("  mask16(v0 lane0 bank0+1)=%04h  lane_mask0=%b lane_mask1=%b lane_mask2=%b lane_mask3=%b",
                vmask16,
                dut.lane_mask0, dut.lane_mask1, dut.lane_mask2, dut.lane_mask3);
        end
    endtask

    task dump_mask_pipeline;
        begin
            $display("  FSM state=%0d is_masking=%0b is_mask_carry=%0b is_compare=%0b",
                fsm_state, dut.is_masking_r, dut.is_mask_carry_r, dut.is_compare_r);
            $display("  lane_mask_result: L0=%b L1=%b L2=%b L3=%b",
                dut.lane_mask_result0, dut.lane_mask_result1, dut.lane_mask_result2, dut.lane_mask_result3);
            $display("  mask_buffer wr_ptr=%0d low128=%032h",
                dut.mask_wr_ptr_dbg, dut.mask_buffer_data);
        end
    endtask

    task show_addsub_equations;
        input [255:0] tag;
        input integer vd_idx;
        input integer is_sub;
        integer l;
        reg [31:0] a, b, r;
        begin
            $display("[MATH] %0s (SEW=16: hai phép độc lập / lane, cin theo mask từng phần tử)", tag);
            for (l = 0; l < 4; l = l + 1) begin
                a = vrf_word(l, 2);
                b = vrf_word(l, 3);
                r = vrf_word(l, vd_idx);
                if (!is_sub)
                    $display("  L%0d: word=%08h | lo16 %04h+%04h+cin | hi16 %04h+%04h+cin",
                        l, r, a[15:0], b[15:0], a[31:16], b[31:16]);
                else
                    $display("  L%0d: word=%08h | lo16 %04h-%04h-bin | hi16 %04h-%04h-bin",
                        l, r, a[15:0], b[15:0], a[31:16], b[31:16]);
            end
        end
    endtask

    task show_mask_equations;
        input [255:0] tag;
        input integer vd_idx;
        integer l;
        reg [31:0] a, b;
        reg [32:0] tmp;
        reg carry_out;
        begin
            $display("[MATH] %0s", tag);
            for (l = 0; l < 4; l = l + 1) begin
                a = vrf_word(l, 6);
                b = vrf_word(l, 7);
                if (tag == "VMADC carry-out per lane") begin
                    tmp = {1'b0, a} + {1'b0, b} + 33'd1;
                    carry_out = tmp[32];
                    $display("  L%0d: %08h + %08h + cin(1) => carry_out=%0d", l, a, b, carry_out);
                end else begin
                    // vmsbc dùng phép trừ: a + ~b + 1
                    tmp = {1'b0, a} + {1'b0, ~b} + 33'd1;
                    carry_out = tmp[32];
                    $display("  L%0d: %08h - %08h (a + ~b + 1) => no_borrow(bit)=%0d", l, a, b, carry_out);
                end
            end
            $display("  Packed VD(v%0d) lane0 = %08h", vd_idx, vrf_word(0, vd_idx));
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

        // Cấu hình e16,m4 avl=18
        rs1_scalar_data = 32'd18;
        issue_instr("vsetvli e16,m4 avl=18", build_vsetvli(ZIMM_E16_M4, 5'd0, 5'd0));
        wait_finish();
        check_u32("CONFIG csr_vtype[7:0]", csr_vtype_o[7:0], 8'h0A);

        // Preload v2, v3 cho VADC/VSBC
        // vm=0 trong thiết kế hiện tại => vmask lane = 4'hF => carry_in = 1 (sew=32 dùng bit0)
        {dut.vrf_lane0.bank3[2], dut.vrf_lane0.bank2[2], dut.vrf_lane0.bank1[2], dut.vrf_lane0.bank0[2]} = 32'd1;
        {dut.vrf_lane1.bank3[2], dut.vrf_lane1.bank2[2], dut.vrf_lane1.bank1[2], dut.vrf_lane1.bank0[2]} = 32'd2;
        {dut.vrf_lane2.bank3[2], dut.vrf_lane2.bank2[2], dut.vrf_lane2.bank1[2], dut.vrf_lane2.bank0[2]} = 32'd3;
        {dut.vrf_lane3.bank3[2], dut.vrf_lane3.bank2[2], dut.vrf_lane3.bank1[2], dut.vrf_lane3.bank0[2]} = 32'd4;

        {dut.vrf_lane0.bank3[3], dut.vrf_lane0.bank2[3], dut.vrf_lane0.bank1[3], dut.vrf_lane0.bank0[3]} = 32'd10;
        {dut.vrf_lane1.bank3[3], dut.vrf_lane1.bank2[3], dut.vrf_lane1.bank1[3], dut.vrf_lane1.bank0[3]} = 32'd20;
        {dut.vrf_lane2.bank3[3], dut.vrf_lane2.bank2[3], dut.vrf_lane2.bank1[3], dut.vrf_lane2.bank0[3]} = 32'd30;
        {dut.vrf_lane3.bank3[3], dut.vrf_lane3.bank2[3], dut.vrf_lane3.bank1[3], dut.vrf_lane3.bank0[3]} = 32'd40;

        issue_instr("vadc.vv v4,v2,v3 vm=0", build_opv(VADC, 1'b0, 3'b000, 5'd3, 5'd2, 5'd4));
        $display("[DATA] VADC inputs");
        dump_lane_inputs(2, 3);
        wait_finish();
        $display("[DATA] VADC outputs (vd group v4..v7 for m4)");
        $display("  v4: L0=%08h L1=%08h L2=%08h L3=%08h", vrf_word(0,4), vrf_word(1,4), vrf_word(2,4), vrf_word(3,4));
        $display("  v5: L0=%08h L1=%08h L2=%08h L3=%08h", vrf_word(0,5), vrf_word(1,5), vrf_word(2,5), vrf_word(3,5));
        $display("  v6: L0=%08h L1=%08h L2=%08h L3=%08h", vrf_word(0,6), vrf_word(1,6), vrf_word(2,6), vrf_word(3,6));
        $display("  v7: L0=%08h L1=%08h L2=%08h L3=%08h", vrf_word(0,7), vrf_word(1,7), vrf_word(2,7), vrf_word(3,7));
        show_addsub_equations("VADC arithmetic", 4, 0);
        check_u32("VADC lane0", vrf_word(0,4), 32'd12);
        check_u32("VADC lane1", vrf_word(1,4), 32'd23);
        check_u32("VADC lane2", vrf_word(2,4), 32'd34);
        check_u32("VADC lane3", vrf_word(3,4), 32'd45);

        issue_instr("vsbc.vv v5,v2,v3 vm=0", build_opv(VSBC, 1'b0, 3'b000, 5'd3, 5'd2, 5'd5));
        $display("[DATA] VSBC inputs");
        dump_lane_inputs(2, 3);
        wait_finish();
        $display("[DATA] VSBC outputs (vd group v5..v8 for m4)");
        $display("  v5: L0=%08h L1=%08h L2=%08h L3=%08h", vrf_word(0,5), vrf_word(1,5), vrf_word(2,5), vrf_word(3,5));
        $display("  v6: L0=%08h L1=%08h L2=%08h L3=%08h", vrf_word(0,6), vrf_word(1,6), vrf_word(2,6), vrf_word(3,6));
        $display("  v7: L0=%08h L1=%08h L2=%08h L3=%08h", vrf_word(0,7), vrf_word(1,7), vrf_word(2,7), vrf_word(3,7));
        $display("  v8: L0=%08h L1=%08h L2=%08h L3=%08h", vrf_word(0,8), vrf_word(1,8), vrf_word(2,8), vrf_word(3,8));
        show_addsub_equations("VSBC arithmetic", 5, 1);
        check_u32("VSBC lane0", vrf_word(0,5), 32'hFFFF_FFF7); // 1-10
        check_u32("VSBC lane1", vrf_word(1,5), 32'hFFFF_FFEE); // 2-20
        check_u32("VSBC lane2", vrf_word(2,5), 32'hFFFF_FFE5); // 3-30
        check_u32("VSBC lane3", vrf_word(3,5), 32'hFFFF_FFDC); // 4-40

        // Preload cho VMADC/VMSBC (nhánh masking)
        {dut.vrf_lane0.bank3[6], dut.vrf_lane0.bank2[6], dut.vrf_lane0.bank1[6], dut.vrf_lane0.bank0[6]} = 32'hFFFF_FFFF;
        {dut.vrf_lane1.bank3[6], dut.vrf_lane1.bank2[6], dut.vrf_lane1.bank1[6], dut.vrf_lane1.bank0[6]} = 32'h0000_0000;
        {dut.vrf_lane2.bank3[6], dut.vrf_lane2.bank2[6], dut.vrf_lane2.bank1[6], dut.vrf_lane2.bank0[6]} = 32'hFFFF_FFFF;
        {dut.vrf_lane3.bank3[6], dut.vrf_lane3.bank2[6], dut.vrf_lane3.bank1[6], dut.vrf_lane3.bank0[6]} = 32'h7FFF_FFFF;

        {dut.vrf_lane0.bank3[7], dut.vrf_lane0.bank2[7], dut.vrf_lane0.bank1[7], dut.vrf_lane0.bank0[7]} = 32'h0000_0000;
        {dut.vrf_lane1.bank3[7], dut.vrf_lane1.bank2[7], dut.vrf_lane1.bank1[7], dut.vrf_lane1.bank0[7]} = 32'h0000_0000;
        {dut.vrf_lane2.bank3[7], dut.vrf_lane2.bank2[7], dut.vrf_lane2.bank1[7], dut.vrf_lane2.bank0[7]} = 32'hFFFF_FFFF;
        {dut.vrf_lane3.bank3[7], dut.vrf_lane3.bank2[7], dut.vrf_lane3.bank1[7], dut.vrf_lane3.bank0[7]} = 32'h0000_0000;

        issue_instr("vmadc.vv v8,v6,v7 vm=0", build_opv(VMADC, 1'b0, 3'b000, 5'd7, 5'd6, 5'd8));
        $display("[DATA] VMADC inputs");
        dump_lane_inputs(6, 7);
        wait_finish();
        $display("[DATA] VMADC mask pipeline");
        dump_mask_pipeline();
        $display("  VD(v8): L0=%08h L1=%08h L2=%08h L3=%08h", vrf_word(0,8), vrf_word(1,8), vrf_word(2,8), vrf_word(3,8));
        show_mask_equations("VMADC carry-out per lane", 8);
        // Với e32,m1: 4 phần tử mask được pack liên tục vào nibble thấp lane0.
        // Ví dụ bit phần tử {e3,e2,e1,e0}=0101 -> lane0 = 0x00000005.
        check_u32("VMADC lane0", vrf_word(0,8), 32'h0000_0005);
        check_u32("VMADC lane1", vrf_word(1,8), 32'h0000_0000);
        check_u32("VMADC lane2", vrf_word(2,8), 32'h0000_0000);
        check_u32("VMADC lane3", vrf_word(3,8), 32'h0000_0000);

        issue_instr("vmsbc.vv v9,v6,v7 vm=0", build_opv(VMSBC, 1'b0, 3'b000, 5'd7, 5'd6, 5'd9));
        $display("[DATA] VMSBC inputs");
        dump_lane_inputs(6, 7);
        wait_finish();
        $display("[DATA] VMSBC mask pipeline");
        dump_mask_pipeline();
        $display("  VD(v9): L0=%08h L1=%08h L2=%08h L3=%08h", vrf_word(0,9), vrf_word(1,9), vrf_word(2,9), vrf_word(3,9));
        show_mask_equations("VMSBC no-borrow per lane", 9);
        // VMSBC dùng carry-out của phép trừ (no-borrow=1):
        // lane0: FFFFFFFF-0 =>1, lane1:0-0=>1, lane2:FFFFFFFF-FFFFFFFF=>1, lane3:7fffffff-0=>1
        check_u32("VMSBC lane0", vrf_word(0,9), 32'h0000_000F);
        check_u32("VMSBC lane1", vrf_word(1,9), 32'h0000_0000);
        check_u32("VMSBC lane2", vrf_word(2,9), 32'h0000_0000);
        check_u32("VMSBC lane3", vrf_word(3,9), 32'h0000_0000);

        // ================= Extra scenarios (config/lệnh khác) =================
        // A) e16,m2 + vmadc
        rs1_scalar_data = 32'd16;
        issue_instr("vsetvli e16,m2 avl=16", build_vsetvli(ZIMM_E16_M2, 5'd0, 5'd0));
        wait_finish();
        check_u32("CONFIG e16,m2 csr_vtype[7:0]", csr_vtype_o[7:0], 8'h09);

        // Dữ liệu 16-bit để tạo carry khác nhau giữa lane phần tử.
        // vs2=v10, vs1=v11
        {dut.vrf_lane0.bank3[10], dut.vrf_lane0.bank2[10], dut.vrf_lane0.bank1[10], dut.vrf_lane0.bank0[10]} = 32'hFFFF_0001;
        {dut.vrf_lane1.bank3[10], dut.vrf_lane1.bank2[10], dut.vrf_lane1.bank1[10], dut.vrf_lane1.bank0[10]} = 32'h7FFF_8000;
        {dut.vrf_lane2.bank3[10], dut.vrf_lane2.bank2[10], dut.vrf_lane2.bank1[10], dut.vrf_lane2.bank0[10]} = 32'h0000_FFFF;
        {dut.vrf_lane3.bank3[10], dut.vrf_lane3.bank2[10], dut.vrf_lane3.bank1[10], dut.vrf_lane3.bank0[10]} = 32'h1234_ABCD;

        {dut.vrf_lane0.bank3[11], dut.vrf_lane0.bank2[11], dut.vrf_lane0.bank1[11], dut.vrf_lane0.bank0[11]} = 32'h0001_FFFF;
        {dut.vrf_lane1.bank3[11], dut.vrf_lane1.bank2[11], dut.vrf_lane1.bank1[11], dut.vrf_lane1.bank0[11]} = 32'h8001_7FFF;
        {dut.vrf_lane2.bank3[11], dut.vrf_lane2.bank2[11], dut.vrf_lane2.bank1[11], dut.vrf_lane2.bank0[11]} = 32'hFFFF_0000;
        {dut.vrf_lane3.bank3[11], dut.vrf_lane3.bank2[11], dut.vrf_lane3.bank1[11], dut.vrf_lane3.bank0[11]} = 32'hEDCB_5433;

        issue_instr("vmadc.vv v12,v10,v11 vm=0 (e16,m2)", build_opv(VMADC, 1'b0, 3'b000, 5'd11, 5'd10, 5'd12));
        wait_finish();
        $display("[EXTRA] VMADC e16,m2 VD(v12): L0=%08h L1=%08h L2=%08h L3=%08h",
            vrf_word(0,12), vrf_word(1,12), vrf_word(2,12), vrf_word(3,12));
        check_u32("EXTRA VMADC e16,m2 lane0", vrf_word(0,12), 32'h0000_21FF);
        check_u32("EXTRA VMADC e16,m2 lane1", vrf_word(1,12), 32'h0000_0000);
        check_u32("EXTRA VMADC e16,m2 lane2", vrf_word(2,12), 32'h0000_0000);
        check_u32("EXTRA VMADC e16,m2 lane3", vrf_word(3,12), 32'h0000_0000);

        // B) e8,m1 + vmsbc
        rs1_scalar_data = 32'd16;
        issue_instr("vsetvli e8,m1 avl=16", build_vsetvli(ZIMM_E8_M1, 5'd0, 5'd0));
        wait_finish();
        check_u32("CONFIG e8,m1 csr_vtype[7:0]", csr_vtype_o[7:0], 8'h00);

        {dut.vrf_lane0.bank3[13], dut.vrf_lane0.bank2[13], dut.vrf_lane0.bank1[13], dut.vrf_lane0.bank0[13]} = 32'hFF00_10F0;
        {dut.vrf_lane1.bank3[13], dut.vrf_lane1.bank2[13], dut.vrf_lane1.bank1[13], dut.vrf_lane1.bank0[13]} = 32'h0102_0304;
        {dut.vrf_lane2.bank3[13], dut.vrf_lane2.bank2[13], dut.vrf_lane2.bank1[13], dut.vrf_lane2.bank0[13]} = 32'hA0B0_C0D0;
        {dut.vrf_lane3.bank3[13], dut.vrf_lane3.bank2[13], dut.vrf_lane3.bank1[13], dut.vrf_lane3.bank0[13]} = 32'h7F80_FE01;

        {dut.vrf_lane0.bank3[14], dut.vrf_lane0.bank2[14], dut.vrf_lane0.bank1[14], dut.vrf_lane0.bank0[14]} = 32'h0101_0101;
        {dut.vrf_lane1.bank3[14], dut.vrf_lane1.bank2[14], dut.vrf_lane1.bank1[14], dut.vrf_lane1.bank0[14]} = 32'h0001_0203;
        {dut.vrf_lane2.bank3[14], dut.vrf_lane2.bank2[14], dut.vrf_lane2.bank1[14], dut.vrf_lane2.bank0[14]} = 32'h1010_1010;
        {dut.vrf_lane3.bank3[14], dut.vrf_lane3.bank2[14], dut.vrf_lane3.bank1[14], dut.vrf_lane3.bank0[14]} = 32'h7F01_FF01;

        issue_instr("vmsbc.vv v15,v13,v14 vm=0 (e8,m1)", build_opv(VMSBC, 1'b0, 3'b000, 5'd14, 5'd13, 5'd15));
        wait_finish();
        $display("[EXTRA] VMSBC e8,m1 VD(v15): L0=%08h L1=%08h L2=%08h L3=%08h",
            vrf_word(0,15), vrf_word(1,15), vrf_word(2,15), vrf_word(3,15));
        check_u32("EXTRA VMSBC e8,m1 lane0", vrf_word(0,15), 32'h0000_DFFB);
        check_u32("EXTRA VMSBC e8,m1 lane1", vrf_word(1,15), 32'h0000_0000);
        check_u32("EXTRA VMSBC e8,m1 lane2", vrf_word(2,15), 32'h0000_0000);
        check_u32("EXTRA VMSBC e8,m1 lane3", vrf_word(3,15), 32'h0000_0000);

        $display("=== SUMMARY mask-carry TB: PASS=%0d FAIL=%0d ===", pass_count, fail_count);
        if (fail_count == 0) $display("=== RESULT: PASS ===");
        else                 $display("=== RESULT: FAIL ===");
        #20;
        $finish;
    end

endmodule

