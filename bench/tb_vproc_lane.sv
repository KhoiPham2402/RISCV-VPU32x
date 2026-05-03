// Testbench for vproc_processor_lane
// Test các operations: ADD, SUB, MUL, LOGIC, SHIFT, COMPARE
// Sử dụng golden model để so sánh kết quả

`timescale 1ns / 1ps

module tb_vproc_lane ();
    // ===== Local Parameters =====
    localparam NUM_TESTS = 100;
    
    // funct6 opcodes
    localparam [5:0] VADD    = 6'b000000;
    localparam [5:0] VSUB    = 6'b000010;
    localparam [5:0] VMUL    = 6'b100101;
    localparam [5:0] VMULH   = 6'b100111;
    localparam [5:0] VMULHU  = 6'b100100;
    localparam [5:0] VMULHSU = 6'b100110;
    localparam [5:0] VAND    = 6'b001001;
    localparam [5:0] VOR     = 6'b001010;
    localparam [5:0] VXOR    = 6'b001011;
    localparam [5:0] VSLL    = 6'b010101;
    localparam [5:0] VSRL    = 6'b010000;
    localparam [5:0] VSRA    = 6'b010010;
    localparam [5:0] VCMPEQ  = 6'b011000;
    
    // ===== Test Signals =====
    reg clk;
    reg [31:0] vs1_data;
    reg [31:0] vs2_data;
    reg [31:0] immediate;
    reg [31:0] rs1_data;
    reg [5:0]  funct6;
    reg [2:0]  sew;
    reg        sub;
    reg        is_unsigned_vs1;
    reg        is_unsigned_vs2;
    reg        is_mulh;
    reg        shift_ctrl;
    reg [1:0]  cmp_op;
    
    wire [31:0] result_lo;
    wire [31:0] result_hi;
    
    // ===== Golden Model Outputs =====
    reg [31:0] golden_lo;
    reg [31:0] golden_hi;
    
    // ===== Test Statistics =====
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_count = 0;
    
    // ===== DUT Instantiation =====
    vproc_processor_lane dut (
        .vs1_data(vs1_data),
        .vs2_data(vs2_data),
        .immediate(immediate),
        .rs1_data(rs1_data),
        .funct6(funct6),
        .sew(sew),
        .sub(sub),
        .is_unsigned_vs1(is_unsigned_vs1),
        .is_unsigned_vs2(is_unsigned_vs2),
        .is_mulh(is_mulh),
        .shift_ctrl(shift_ctrl),
        .cmp_op(cmp_op),
        .result_lo(result_lo),
        .result_hi(result_hi)
    );

    // ===== Golden Model Task =====
    task automatic golden_model();
        begin
            golden_lo = 32'b0;
            golden_hi = 32'b0;
            
            case (funct6)
                VADD: begin
                    case (sew)
                        3'd0: begin
                            // 32-bit add
                            {golden_hi, golden_lo} = {1'b0, vs1_data} + {1'b0, vs2_data};
                            golden_hi = golden_hi[31:0];
                        end
                        3'd1: begin
                            // 2x 16-bit add
                            {golden_hi[15:0], golden_lo[15:0]} = vs1_data[15:0] + vs2_data[15:0];
                            {golden_hi[31:16], golden_lo[31:16]} = vs1_data[31:16] + vs2_data[31:16];
                        end
                        3'd2: begin
                            // 4x 8-bit add
                            golden_lo[7:0]   = vs1_data[7:0]   + vs2_data[7:0];
                            golden_lo[15:8]  = vs1_data[15:8]  + vs2_data[15:8];
                            golden_lo[23:16] = vs1_data[23:16] + vs2_data[23:16];
                            golden_lo[31:24] = vs1_data[31:24] + vs2_data[31:24];
                        end
                    endcase
                end

                VSUB: begin
                    case (sew)
                        3'd0: begin
                            // 32-bit sub
                            {golden_hi, golden_lo} = {1'b0, vs1_data} - {1'b0, vs2_data};
                            golden_hi = golden_hi[31:0];
                        end
                        3'd1: begin
                            // 2x 16-bit sub
                            {golden_hi[15:0], golden_lo[15:0]} = vs1_data[15:0] - vs2_data[15:0];
                            {golden_hi[31:16], golden_lo[31:16]} = vs1_data[31:16] - vs2_data[31:16];
                        end
                        3'd2: begin
                            // 4x 8-bit sub
                            golden_lo[7:0]   = vs1_data[7:0]   - vs2_data[7:0];
                            golden_lo[15:8]  = vs1_data[15:8]  - vs2_data[15:8];
                            golden_lo[23:16] = vs1_data[23:16] - vs2_data[23:16];
                            golden_lo[31:24] = vs1_data[31:24] - vs2_data[31:24];
                        end
                    endcase
                end

                VMUL: begin
                    // 32-bit multiply
                    reg signed [63:0] a_ext, b_ext, prod;
                    if (is_unsigned_vs1) begin
                        a_ext = {32'b0, vs1_data};
                    end else begin
                        a_ext = {{32{vs1_data[31]}}, vs1_data};
                    end
                    if (is_unsigned_vs2) begin
                        b_ext = {32'b0, vs2_data};
                    end else begin
                        b_ext = {{32{vs2_data[31]}}, vs2_data};
                    end
                    prod = a_ext * b_ext;
                    golden_lo = prod[31:0];
                    golden_hi = prod[63:32];
                end

                VMULH, VMULHU, VMULHSU: begin
                    // 32-bit multiply high
                    reg signed [63:0] a_ext, b_ext, prod;
                    if (is_unsigned_vs1) begin
                        a_ext = {32'b0, vs1_data};
                    end else begin
                        a_ext = {{32{vs1_data[31]}}, vs1_data};
                    end
                    if (is_unsigned_vs2) begin
                        b_ext = {32'b0, vs2_data};
                    end else begin
                        b_ext = {{32{vs2_data[31]}}, vs2_data};
                    end
                    prod = a_ext * b_ext;
                    golden_lo = prod[63:32];
                    golden_hi = 32'b0;
                end

                VAND: begin
                    golden_lo = vs1_data & vs2_data;
                    golden_hi = 32'b0;
                end

                VOR: begin
                    golden_lo = vs1_data | vs2_data;
                    golden_hi = 32'b0;
                end

                VXOR: begin
                    golden_lo = vs1_data ^ vs2_data;
                    golden_hi = 32'b0;
                end

                VSLL: begin
                    case (sew)
                        3'd0: begin
                            golden_lo = vs2_data << rs1_data[4:0];
                        end
                        3'd1: begin
                            golden_lo[15:0]  = vs2_data[15:0]  << rs1_data[3:0];
                            golden_lo[31:16] = vs2_data[31:16] << rs1_data[19:16];
                        end
                        3'd2: begin
                            golden_lo[7:0]   = vs2_data[7:0]   << rs1_data[2:0];
                            golden_lo[15:8]  = vs2_data[15:8]  << rs1_data[10:8];
                            golden_lo[23:16] = vs2_data[23:16] << rs1_data[18:16];
                            golden_lo[31:24] = vs2_data[31:24] << rs1_data[26:24];
                        end
                    endcase
                    golden_hi = 32'b0;
                end

                VSRL: begin
                    case (sew)
                        3'd0: begin
                            golden_lo = vs2_data >> rs1_data[4:0];
                        end
                        3'd1: begin
                            golden_lo[15:0]  = vs2_data[15:0]  >> rs1_data[3:0];
                            golden_lo[31:16] = vs2_data[31:16] >> rs1_data[19:16];
                        end
                        3'd2: begin
                            golden_lo[7:0]   = vs2_data[7:0]   >> rs1_data[2:0];
                            golden_lo[15:8]  = vs2_data[15:8]  >> rs1_data[10:8];
                            golden_lo[23:16] = vs2_data[23:16] >> rs1_data[18:16];
                            golden_lo[31:24] = vs2_data[31:24] >> rs1_data[26:24];
                        end
                    endcase
                    golden_hi = 32'b0;
                end

                VSRA: begin
                    reg signed [31:0] val;
                    case (sew)
                        3'd0: begin
                            val = $signed(vs2_data);
                            golden_lo = val >>> rs1_data[4:0];
                        end
                        3'd1: begin
                            val = $signed(vs2_data[15:0]);
                            golden_lo[15:0] = val >>> rs1_data[3:0];
                            val = $signed(vs2_data[31:16]);
                            golden_lo[31:16] = val >>> rs1_data[19:16];
                        end
                        3'd2: begin
                            val = $signed({{24{vs2_data[7]}}, vs2_data[7:0]});
                            golden_lo[7:0] = val >>> rs1_data[2:0];
                            val = $signed({{24{vs2_data[15]}}, vs2_data[15:8]});
                            golden_lo[15:8] = val >>> rs1_data[10:8];
                            val = $signed({{24{vs2_data[23]}}, vs2_data[23:16]});
                            golden_lo[23:16] = val >>> rs1_data[18:16];
                            val = $signed({{24{vs2_data[31]}}, vs2_data[31:24]});
                            golden_lo[31:24] = val >>> rs1_data[26:24];
                        end
                    endcase
                    golden_hi = 32'b0;
                end

                VCMPEQ: begin
                    reg [3:0] cmp_bits;
                    integer i;
                    cmp_bits = 4'b0;
                    case (sew)
                        3'd0: begin
                            case (cmp_op)
                                2'b00: cmp_bits[0] = (vs1_data == vs2_data) ? 1'b1 : 1'b0; // eq
                                2'b01: cmp_bits[0] = ($signed(vs1_data) < $signed(vs2_data)) ? 1'b1 : 1'b0; // lt
                                2'b10: begin // gt = NOT(eq) AND NOT(lt)
                                    cmp_bits[0] = ((vs1_data != vs2_data) && !($signed(vs1_data) < $signed(vs2_data))) ? 1'b1 : 1'b0;
                                end
                                default: cmp_bits[0] = 1'b0;
                            endcase
                            golden_lo = {32{cmp_bits[0]}};
                        end
                        3'd1: begin
                            // 16-bit lane 0
                            case (cmp_op)
                                2'b00: cmp_bits[0] = (vs1_data[15:0] == vs2_data[15:0]) ? 1'b1 : 1'b0;
                                2'b01: cmp_bits[0] = ($signed(vs1_data[15:0]) < $signed(vs2_data[15:0])) ? 1'b1 : 1'b0;
                                2'b10: cmp_bits[0] = ((vs1_data[15:0] != vs2_data[15:0]) && !($signed(vs1_data[15:0]) < $signed(vs2_data[15:0]))) ? 1'b1 : 1'b0;
                                default: cmp_bits[0] = 1'b0;
                            endcase
                            // 16-bit lane 1
                            case (cmp_op)
                                2'b00: cmp_bits[1] = (vs1_data[31:16] == vs2_data[31:16]) ? 1'b1 : 1'b0;
                                2'b01: cmp_bits[1] = ($signed(vs1_data[31:16]) < $signed(vs2_data[31:16])) ? 1'b1 : 1'b0;
                                2'b10: cmp_bits[1] = ((vs1_data[31:16] != vs2_data[31:16]) && !($signed(vs1_data[31:16]) < $signed(vs2_data[31:16]))) ? 1'b1 : 1'b0;
                                default: cmp_bits[1] = 1'b0;
                            endcase
                            golden_lo = {16{cmp_bits[1]}, 16{cmp_bits[0]}};
                        end
                        3'd2: begin
                            // Byte lanes 0-3
                            for (i = 0; i < 4; i = i + 1) begin
                                reg signed [8:0] v1_ext, v2_ext;
                                v1_ext = {vs1_data[i*8+7], vs1_data[i*8+7:i*8]};
                                v2_ext = {vs2_data[i*8+7], vs2_data[i*8+7:i*8]};
                                case (cmp_op)
                                    2'b00: cmp_bits[i] = (vs1_data[i*8+7:i*8] == vs2_data[i*8+7:i*8]) ? 1'b1 : 1'b0;
                                    2'b01: cmp_bits[i] = (v1_ext < v2_ext) ? 1'b1 : 1'b0;
                                    2'b10: cmp_bits[i] = ((vs1_data[i*8+7:i*8] != vs2_data[i*8+7:i*8]) && !(v1_ext < v2_ext)) ? 1'b1 : 1'b0;
                                    default: cmp_bits[i] = 1'b0;
                                endcase
                            end
                            golden_lo = {8{cmp_bits[3]}, 8{cmp_bits[2]}, 8{cmp_bits[1]}, 8{cmp_bits[0]}};
                        end
                    endcase
                    golden_hi = 32'b0;
                end

                default: begin
                    golden_lo = 32'b0;
                    golden_hi = 32'b0;
                end
            endcase
        end
    endtask

    // ===== Test Result Check Task =====
    task automatic check_result(string test_name);
        begin
            test_count = test_count + 1;
            if ((result_lo === golden_lo) && (result_hi === golden_hi)) begin
                pass_count = pass_count + 1;
                $display("[PASS] Test %3d: %s", test_count, test_name);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] Test %3d: %s", test_count, test_name);
                $display("       vs1=%08H, vs2=%08H, rs1=%08H", vs1_data, vs2_data, rs1_data);
                $display("       Got:    result_lo=%08H, result_hi=%08H", result_lo, result_hi);
                $display("       Golden: result_lo=%08H, result_hi=%08H", golden_lo, golden_hi);
            end
        end
    endtask

    // ===== Random Test Task =====
    task automatic random_test(string op_name, reg [5:0] op_code, 
                               reg [2:0] test_sew, reg test_sub, 
                               reg test_shift_ctrl, reg [1:0] test_cmp_op);
        begin
            funct6 = op_code;
            sew = test_sew;
            sub = test_sub;
            is_unsigned_vs1 = $urandom_range(0, 1);
            is_unsigned_vs2 = $urandom_range(0, 1);
            is_mulh = (op_code == VMULH || op_code == VMULHU || op_code == VMULHSU) ? 1'b1 : 1'b0;
            shift_ctrl = test_shift_ctrl;
            cmp_op = test_cmp_op;
            
            vs1_data = {$random};
            vs2_data = {$random};
            immediate = {$random};
            rs1_data = {$random};
            
            #5 golden_model();
            #5 check_result({op_name, " SEW=", $sformatf("%0d", test_sew)});
        end
    endtask

    // ===== Main Test Process =====
    initial begin
        $display("==========================================");
        $display("  VPROC_PROCESSOR_LANE COMPREHENSIVE TEST");
        $display("==========================================");
        $display("");
        
        // Test ADD operations
        $display("--- Testing VADD ---");
        random_test("VADD_32b", VADD, 3'd0, 1'b0, 1'b0, 2'b00); #10;
        random_test("VADD_16b", VADD, 3'd1, 1'b0, 1'b0, 2'b00); #10;
        random_test("VADD_8b",  VADD, 3'd2, 1'b0, 1'b0, 2'b00); #10;

        // Test SUB operations
        $display("--- Testing VSUB ---");
        random_test("VSUB_32b", VSUB, 3'd0, 1'b0, 1'b0, 2'b00); #10;
        random_test("VSUB_16b", VSUB, 3'd1, 1'b0, 1'b0, 2'b00); #10;
        random_test("VSUB_8b",  VSUB, 3'd2, 1'b0, 1'b0, 2'b00); #10;

        // Test MUL operations
        $display("--- Testing VMUL ---");
        random_test("VMUL_ss", VMUL, 3'd0, 1'b0, 1'b0, 2'b00); #10;
        random_test("VMUL_uu", VMUL, 3'd0, 1'b0, 1'b0, 2'b00); #10;
        
        $display("--- Testing VMULH ---");
        random_test("VMULH_ss", VMULH, 3'd0, 1'b0, 1'b0, 2'b00); #10;
        random_test("VMULHU_uu", VMULHU, 3'd0, 1'b0, 1'b0, 2'b00); #10;
        random_test("VMULHSU", VMULHSU, 3'd0, 1'b0, 1'b0, 2'b00); #10;

        // Test LOGIC operations
        $display("--- Testing VAND ---");
        random_test("VAND", VAND, 3'd0, 1'b0, 1'b0, 2'b00); #10;
        
        $display("--- Testing VOR ---");
        random_test("VOR", VOR, 3'd0, 1'b0, 1'b0, 2'b00); #10;
        
        $display("--- Testing VXOR ---");
        random_test("VXOR", VXOR, 3'd0, 1'b0, 1'b0, 2'b00); #10;

        // Test SHIFT operations
        $display("--- Testing VSLL ---");
        random_test("VSLL_32b", VSLL, 3'd0, 1'b0, 1'b0, 2'b00); #10;
        random_test("VSLL_16b", VSLL, 3'd1, 1'b0, 1'b0, 2'b00); #10;
        
        $display("--- Testing VSRL ---");
        random_test("VSRL_32b", VSRL, 3'd0, 1'b0, 1'b1, 2'b00); #10;
        random_test("VSRL_16b", VSRL, 3'd1, 1'b0, 1'b1, 2'b00); #10;
        
        $display("--- Testing VSRA ---");
        random_test("VSRA_32b", VSRA, 3'd0, 1'b0, 1'b1, 2'b00); #10;
        random_test("VSRA_16b", VSRA, 3'd1, 1'b0, 1'b1, 2'b00); #10;

        // Test COMPARE operations
        $display("--- Testing VCMPEQ (Equal) ---");
        random_test("VCMPEQ_32b_eq", VCMPEQ, 3'd0, 1'b0, 1'b0, 2'b00); #10;
        random_test("VCMPEQ_16b_eq", VCMPEQ, 3'd1, 1'b0, 1'b0, 2'b00); #10;
        random_test("VCMPEQ_8b_eq",  VCMPEQ, 3'd2, 1'b0, 1'b0, 2'b00); #10;
        
        $display("--- Testing VCMPLT (Less Than) ---");
        random_test("VCMPEQ_32b_lt", VCMPEQ, 3'd0, 1'b0, 1'b0, 2'b01); #10;
        random_test("VCMPEQ_16b_lt", VCMPEQ, 3'd1, 1'b0, 1'b0, 2'b01); #10;
        random_test("VCMPEQ_8b_lt",  VCMPEQ, 3'd2, 1'b0, 1'b0, 2'b01); #10;
        
        $display("--- Testing VCMPGT (Greater Than) ---");
        random_test("VCMPEQ_32b_gt", VCMPEQ, 3'd0, 1'b0, 1'b0, 2'b10); #10;
        random_test("VCMPEQ_16b_gt", VCMPEQ, 3'd1, 1'b0, 1'b0, 2'b10); #10;
        random_test("VCMPEQ_8b_gt",  VCMPEQ, 3'd2, 1'b0, 1'b0, 2'b10); #10;

        // Additional random tests
        $display("--- Additional Random Tests ---");
        repeat (NUM_TESTS / 5) random_test("Random", VADD, 3'd0, 1'b0, 1'b0, 2'b00);
        repeat (NUM_TESTS / 5) random_test("Random", VSUB, 3'd1, 1'b0, 1'b0, 2'b00);
        repeat (NUM_TESTS / 5) random_test("Random", VMUL, 3'd0, 1'b0, 1'b0, 2'b00);
        repeat (NUM_TESTS / 5) random_test("Random", VSLL, 3'd0, 1'b0, 1'b0, 2'b00);
        repeat (NUM_TESTS / 5) random_test("Random", VCMPEQ, 3'd2, 1'b0, 1'b0, 2'b01);

        // Print test summary
        $display("");
        $display("==========================================");
        $display("              TEST SUMMARY");
        $display("==========================================");
        $display("Total Tests:  %3d", test_count);
        $display("Passed:       %3d", pass_count);
        $display("Failed:       %3d", fail_count);
        if (fail_count == 0) begin
            $display("Result:       *** ALL TESTS PASSED ***");
        end else begin
            $display("Result:       *** SOME TESTS FAILED ***");
        end
        $display("==========================================");
        $finish;
    end

endmodule
