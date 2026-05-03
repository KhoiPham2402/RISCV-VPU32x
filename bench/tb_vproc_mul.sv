`timescale 1ns/1ps

module tb_vproc_mul;

    reg  [31:0] op_a;
    reg  [31:0] op_b;
    reg  [2:0]  sew;
    reg         unsign_a;
    reg         unsign_b;

    wire [31:0] result_lo;
    wire [31:0] result_hi;

    // DUT
    vproc_mul dut (
        .op_a(op_a),
        .op_b(op_b),
        .sew(sew),
        .unsign_a(unsign_a),
        .unsign_b(unsign_b),
        .result_lo(result_lo),
        .result_hi(result_hi)
    );

    // Golden model
    reg [31:0] gold_lo;
    reg [31:0] gold_hi;

    task compute_golden;
        input  [31:0] a;
        input  [31:0] b;
        input  [2:0]  sew_f;
        input         ua;
        input         ub;
        output [31:0] lo;
        output [31:0] hi;

        reg signed [63:0] a32, b32, p32;
        reg signed [31:0] a16l, b16l, p16l;
        reg signed [31:0] a16h, b16h, p16h;
        reg signed [15:0] a8_0, b8_0, p8_0;
        reg signed [15:0] a8_1, b8_1, p8_1;
        reg signed [15:0] a8_2, b8_2, p8_2;
        reg signed [15:0] a8_3, b8_3, p8_3;
    begin
        lo = 32'b0;
        hi = 32'b0;

        case (sew_f)
            3'd0: begin
                // 32x32
                if (ua) a32 = {32'b0, a}; else a32 = {{32{a[31]}}, a};
                if (ub) b32 = {32'b0, b}; else b32 = {{32{b[31]}}, b};
                p32 = a32 * b32;
                lo  = p32[31:0];
                hi  = p32[63:32];
            end

            3'd1: begin
                // 2 x 16x16
                if (ua) a16l = {16'b0, a[15:0]};  else a16l = {{16{a[15]}},  a[15:0]};
                if (ub) b16l = {16'b0, b[15:0]};  else b16l = {{16{b[15]}},  b[15:0]};
                p16l = a16l * b16l;

                if (ua) a16h = {16'b0, a[31:16]}; else a16h = {{16{a[31]}}, a[31:16]};
                if (ub) b16h = {16'b0, b[31:16]}; else b16h = {{16{b[31]}}, b[31:16]};
                p16h = a16h * b16h;

                lo[15:0]   = p16l[15:0];
                lo[31:16]  = p16h[15:0];
                hi[15:0]   = p16l[31:16];
                hi[31:16]  = p16h[31:16];
            end

            3'd2: begin
                // 4 x 8x8
                if (ua) a8_0 = {8'b0, a[7:0]};   else a8_0 = {{8{a[7]}},   a[7:0]};
                if (ub) b8_0 = {8'b0, b[7:0]};   else b8_0 = {{8{b[7]}},   b[7:0]};
                p8_0 = a8_0 * b8_0;

                if (ua) a8_1 = {8'b0, a[15:8]};  else a8_1 = {{8{a[15]}},  a[15:8]};
                if (ub) b8_1 = {8'b0, b[15:8]};  else b8_1 = {{8{b[15]}},  b[15:8]};
                p8_1 = a8_1 * b8_1;

                if (ua) a8_2 = {8'b0, a[23:16]}; else a8_2 = {{8{a[23]}}, a[23:16]};
                if (ub) b8_2 = {8'b0, b[23:16]}; else b8_2 = {{8{b[23]}}, b[23:16]};
                p8_2 = a8_2 * b8_2;

                if (ua) a8_3 = {8'b0, a[31:24]}; else a8_3 = {{8{a[31]}}, a[31:24]};
                if (ub) b8_3 = {8'b0, b[31:24]}; else b8_3 = {{8{b[31]}}, b[31:24]};
                p8_3 = a8_3 * b8_3;

                lo[7:0]    = p8_0[7:0];
                lo[15:8]   = p8_1[7:0];
                lo[23:16]  = p8_2[7:0];
                lo[31:24]  = p8_3[7:0];

                hi[7:0]    = p8_0[15:8];
                hi[15:8]   = p8_1[15:8];
                hi[23:16]  = p8_2[15:8];
                hi[31:24]  = p8_3[15:8];
            end

            default: begin
                lo = 32'b0;
                hi = 32'b0;
            end
        endcase
    end
    endtask

    integer i;
    integer errors;

    initial begin
        op_a     = 0;
        op_b     = 0;
        sew      = 0;
        unsign_a = 0;
        unsign_b = 0;
        errors   = 0;

        $display("===== TB vproc_mul: start =====");

        // Một vài testcase trực tiếp
        op_a = 32'h0000_0003; op_b = 32'h0000_0004; sew = 3'd0; unsign_a = 0; unsign_b = 0;
        #1 compute_golden(op_a, op_b, sew, unsign_a, unsign_b, gold_lo, gold_hi);
        $display("TC0: a=%0d b=%0d sew=%0d ua=%0b ub=%0b | dut_lo=0x%08x dut_hi=0x%08x | gold_lo=0x%08x gold_hi=0x%08x",
                 op_a, op_b, sew, unsign_a, unsign_b, result_lo, result_hi, gold_lo, gold_hi);
        if (result_lo !== gold_lo || result_hi !== gold_hi) errors = errors + 1;

        // Random test
        for (i = 0; i < 2000; i = i + 1) begin
            op_a     = $urandom;
            op_b     = $urandom;
            sew      = $urandom % 3;       // 0..2
            unsign_a = $urandom & 1;
            unsign_b = $urandom & 1;
            #1;
            compute_golden(op_a, op_b, sew, unsign_a, unsign_b, gold_lo, gold_hi);

            if (result_lo !== gold_lo || result_hi !== gold_hi) begin
                $display("[FAIL] iter=%0d sew=%0d ua=%0b ub=%0b", i, sew, unsign_a, unsign_b);
                $display("  op_a=0x%08x op_b=0x%08x", op_a, op_b);
                $display("  dut_lo=0x%08x dut_hi=0x%08x", result_lo, result_hi);
                $display("  gld_lo=0x%08x gld_hi=0x%08x", gold_lo, gold_hi);
                errors = errors + 1;
                // có thể $stop ở đây nếu muốn debug sớm
            end

            if (i < 10 || i > 1990) begin
                // In chi tiết từng lane để dễ bấm máy tính kiểm tra
                case (sew)
                    3'd0: begin
                        $display("iter=%0d [sew=0] ua=%0b ub=%0b", i, unsign_a, unsign_b);
                        $display("  op_a = 0x%08x, op_b = 0x%08x", op_a, op_b);
                        $display("  dut_lo=0x%08x dut_hi=0x%08x", result_lo, result_hi);
                        $display("  gld_lo=0x%08x gld_hi=0x%08x", gold_lo, gold_hi);
                    end
                    3'd1: begin
                        $display("iter=%0d [sew=1] ua=%0b ub=%0b", i, unsign_a, unsign_b);
                        $display("  lane0: a[15:0]=0x%04x, b[15:0]=0x%04x", op_a[15:0],  op_b[15:0]);
                        $display("         dut_lo[15:0]=0x%04x, dut_hi[15:0]=0x%04x",
                                 result_lo[15:0], result_hi[15:0]);
                        $display("         gld_lo[15:0]=0x%04x, gld_hi[15:0]=0x%04x",
                                 gold_lo[15:0], gold_hi[15:0]);
                        $display("  lane1: a[31:16]=0x%04x, b[31:16]=0x%04x", op_a[31:16], op_b[31:16]);
                        $display("         dut_lo[31:16]=0x%04x, dut_hi[31:16]=0x%04x",
                                 result_lo[31:16], result_hi[31:16]);
                        $display("         gld_lo[31:16]=0x%04x, gld_hi[31:16]=0x%04x",
                                 gold_lo[31:16], gold_hi[31:16]);
                    end
                    3'd2: begin
                        $display("iter=%0d [sew=2] ua=%0b ub=%0b", i, unsign_a, unsign_b);
                        $display("  lane0: a[7:0]=0x%02x,  b[7:0]=0x%02x",  op_a[7:0],   op_b[7:0]);
                        $display("         dut_lo[7:0]=0x%02x,  dut_hi[7:0]=0x%02x",
                                 result_lo[7:0],  result_hi[7:0]);
                        $display("         gld_lo[7:0]=0x%02x,  gld_hi[7:0]=0x%02x",
                                 gold_lo[7:0],  gold_hi[7:0]);
                        $display("  lane1: a[15:8]=0x%02x, b[15:8]=0x%02x", op_a[15:8],  op_b[15:8]);
                        $display("         dut_lo[15:8]=0x%02x, dut_hi[15:8]=0x%02x",
                                 result_lo[15:8], result_hi[15:8]);
                        $display("         gld_lo[15:8]=0x%02x, gld_hi[15:8]=0x%02x",
                                 gold_lo[15:8], gold_hi[15:8]);
                        $display("  lane2: a[23:16]=0x%02x, b[23:16]=0x%02x", op_a[23:16], op_b[23:16]);
                        $display("         dut_lo[23:16]=0x%02x, dut_hi[23:16]=0x%02x",
                                 result_lo[23:16], result_hi[23:16]);
                        $display("         gld_lo[23:16]=0x%02x, gld_hi[23:16]=0x%02x",
                                 gold_lo[23:16], gold_hi[23:16]);
                        $display("  lane3: a[31:24]=0x%02x, b[31:24]=0x%02x", op_a[31:24], op_b[31:24]);
                        $display("         dut_lo[31:24]=0x%02x, dut_hi[31:24]=0x%02x",
                                 result_lo[31:24], result_hi[31:24]);
                        $display("         gld_lo[31:24]=0x%02x, gld_hi[31:24]=0x%02x",
                                 gold_lo[31:24], gold_hi[31:24]);
                    end
                    default: ;
                endcase
            end
        end

        if (errors == 0)
            $display("PASS: tb_vproc_mul (2000 random tests, no mismatch)");
        else
            $display("FAIL: tb_vproc_mul (%0d mismatches)", errors);

        $finish;
    end

endmodule

