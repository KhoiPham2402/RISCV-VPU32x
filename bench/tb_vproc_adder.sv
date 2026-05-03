`timescale 1ns/1ps

module tb_vproc_adder;
    // DUT inputs
    reg  [31:0] op_a;
    reg  [31:0] op_b;
    reg         use_carry;
    reg  [3:0]  carry_in;
    reg         sub;
    reg  [2:0]  sew;
    reg         unsign;

    // DUT outputs
    wire [31:0] result_lo;
    wire [31:0] result_hi;

    // Instantiate DUT
    vproc_adder dut (
        .op_a(op_a),
        .op_b(op_b),
        .use_carry(use_carry),
        .carry_in(carry_in),
        .sub(sub),
        .sew(sew),
        .unsign(unsign),
        .result_lo(result_lo),
        .result_hi(result_hi)
    );

    // Golden model helpers
    function [31:0] lane_addsub;
        input [31:0] a;
        input [31:0] b;
        input        sub_f;
        input        use_carry_f;
        input        carry_f;
        input integer w; // 32,16,8
        reg   [31:0] mask;
        reg   [31:0] bb;
        reg   [32:0] tmp;
    begin
        if (w == 32) mask = 32'hFFFF_FFFF;
        else if (w == 16) mask = 32'h0000_FFFF;
        else mask = 32'h0000_00FF;

        bb  = sub_f ? (~b & mask) : (b & mask);
        tmp = {1'b0, (a & mask)} + {1'b0, bb} + (sub_f ? 1'b1 : (use_carry_f ? carry_f : 1'b0));
        lane_addsub = tmp[31:0] & mask;
    end
    endfunction

    task compute_golden;
        input  [31:0] a;
        input  [31:0] b;
        input         sub_f;
        input         use_carry_f;
        input  [3:0]  carry_f;
        input  [2:0]  sew_f;
        input         unsign_f;
        output [31:0] gold_lo;
        output [31:0] gold_hi;
        reg    [31:0] lo;
        reg    [31:0] t;
    begin
        lo = 32'b0;
        case (sew_f)
            3'd0: begin
                lo = lane_addsub(a, b, sub_f, use_carry_f, carry_f[0], 32);
            end
            3'd1: begin
                t = lane_addsub(a[15:0],  b[15:0],  sub_f, use_carry_f, carry_f[0], 16);
                lo[15:0] = t[15:0];
                t = lane_addsub(a[31:16], b[31:16], sub_f, use_carry_f, carry_f[1], 16);
                lo[31:16] = t[15:0];
            end
            3'd2: begin
                t = lane_addsub(a[7:0],   b[7:0],   sub_f, use_carry_f, carry_f[0], 8);
                lo[7:0] = t[7:0];
                t = lane_addsub(a[15:8],  b[15:8],  sub_f, use_carry_f, carry_f[1], 8);
                lo[15:8] = t[7:0];
                t = lane_addsub(a[23:16], b[23:16], sub_f, use_carry_f, carry_f[2], 8);
                lo[23:16] = t[7:0];
                t = lane_addsub(a[31:24], b[31:24], sub_f, use_carry_f, carry_f[3], 8);
                lo[31:24] = t[7:0];
            end
            default: begin
                lo = 32'b0;
            end
        endcase

        gold_lo = lo;

        // Golden cho result_hi theo đúng DUT
        case (sew_f)
            3'd0: begin
                if (unsign_f) gold_hi = 32'b0;            // addwu/subwu
                else          gold_hi = {32{lo[31]}};     // addw/subw
            end
            3'd1: begin
                if (unsign_f) gold_hi = 32'b0;
                else begin
                    gold_hi[15:0]  = {16{lo[15]}};
                    gold_hi[31:16] = {16{lo[31]}};
                end
            end
            3'd2: begin
                if (unsign_f) gold_hi = 32'b0;
                else begin
                    gold_hi[7:0]   = {8{lo[7]}};
                    gold_hi[15:8]  = {8{lo[15]}};
                    gold_hi[23:16] = {8{lo[23]}};
                    gold_hi[31:24] = {8{lo[31]}};
                end
            end
            default: begin
                gold_hi = 32'b0;
            end
        endcase
    end
    endtask

    integer i, j, k, l, m, n;
    integer random_iter;
    integer total_checks;
    integer total_fails;
    integer cov_mode [0:2][0:1][0:1][0:1][0:15];
    integer cov_hit_count;

    reg [31:0] gold_lo;
    reg [31:0] gold_hi;
    reg [31:0] vec_pool [0:11];

    task run_and_check;
        input [31:0] a;
        input [31:0] b;
        input        use_carry_i;
        input [3:0]  c;
        input        sub_f;
        input [2:0]  sew_f;
        input        unsign_f;
        input [127:0] tag;
    begin
        op_a      = a;
        op_b      = b;
        use_carry = use_carry_i;
        carry_in  = c;
        sub       = sub_f;
        sew       = sew_f;
        unsign    = unsign_f;

        #1;
        compute_golden(op_a, op_b, sub, use_carry, carry_in, sew, unsign, gold_lo, gold_hi);
        total_checks = total_checks + 1;

        if ((result_lo !== gold_lo) || (result_hi !== gold_hi)) begin
            total_fails = total_fails + 1;
            $display("FAIL [%0s] check=%0d", tag, total_checks);
            $display("  op_a   = 0x%08x", op_a);
            $display("  op_b   = 0x%08x", op_b);
            $display("  use_carry = %0d", use_carry);
            $display("  carry  = 0x%1x", carry_in);
            $display("  sub    = %0d", sub);
            $display("  unsign = %0d", unsign);
            $display("  sew    = %0d", sew);
            $display("  DUT lo = 0x%08x, hi = 0x%08x", result_lo, result_hi);
            $display("  GLD lo = 0x%08x, hi = 0x%08x", gold_lo, gold_hi);
            $fatal(1);
        end
    end
    endtask

    initial begin
        // khởi tạo
        op_a   = 32'b0;
        op_b   = 32'b0;
        use_carry = 1'b0;
        carry_in = 4'b0;
        sub    = 1'b0;
        sew    = 3'd0;
        unsign = 1'b0;
        total_checks = 0;
        total_fails  = 0;
        random_iter  = 50000;

        for (i = 0; i < 3; i = i + 1)
            for (j = 0; j < 2; j = j + 1)
                for (k = 0; k < 2; k = k + 1)
                    for (m = 0; m < 2; m = m + 1)
                        for (l = 0; l < 16; l = l + 1)
                            cov_mode[i][j][k][m][l] = 0;

        // Directed corner vectors
        vec_pool[0]  = 32'h00000000;
        vec_pool[1]  = 32'hFFFFFFFF;
        vec_pool[2]  = 32'h7FFFFFFF;
        vec_pool[3]  = 32'h80000000;
        vec_pool[4]  = 32'hAAAAAAAA;
        vec_pool[5]  = 32'h55555555;
        vec_pool[6]  = 32'h0000FFFF;
        vec_pool[7]  = 32'hFFFF0000;
        vec_pool[8]  = 32'h00FF00FF;
        vec_pool[9]  = 32'hFF00FF00;
        vec_pool[10] = 32'h00000001;
        vec_pool[11] = 32'hFFFFFFFE;

        // Exhaustive mode coverage: sew/sub/unsign/carry
        for (i = 0; i < 3; i = i + 1) begin
            for (j = 0; j < 2; j = j + 1) begin
                for (k = 0; k < 2; k = k + 1) begin
                    for (m = 0; m < 2; m = m + 1) begin
                        for (l = 0; l < 16; l = l + 1) begin
                            for (n = 0; n < 12; n = n + 1) begin
                                run_and_check(
                                    vec_pool[n],
                                    vec_pool[(n + l + j + k + m + i) % 12],
                                    m[0],
                                    l[3:0],
                                    j[0],
                                    i[2:0],
                                    k[0],
                                    "directed"
                                );
                                cov_mode[i][j][k][m][l] = cov_mode[i][j][k][m][l] + 1;
                            end
                        end
                    end
                end
            end
        end

        // Random regression (bao gồm cả invalid sew để test default)
        for (i = 0; i < random_iter; i = i + 1) begin
            op_a = $urandom;
            op_b = $urandom;
            use_carry = $urandom & 1;
            carry_in = $urandom & 4'hF;
            sub  = $urandom & 1;
            unsign = $urandom & 1;

            case (($urandom % 8))
                0: sew = 3'd3;
                1: sew = 3'd4;
                2: sew = 3'd7;
                default: sew = $urandom % 3;
            endcase

            run_and_check(op_a, op_b, use_carry, carry_in, sub, sew, unsign, "random");
            if (sew < 3)
                cov_mode[sew][sub][unsign][use_carry][carry_in] = cov_mode[sew][sub][unsign][use_carry][carry_in] + 1;
        end

        cov_hit_count = 0;
        for (i = 0; i < 3; i = i + 1)
            for (j = 0; j < 2; j = j + 1)
                for (k = 0; k < 2; k = k + 1)
                    for (m = 0; m < 2; m = m + 1)
                        for (l = 0; l < 16; l = l + 1)
                            if (cov_mode[i][j][k][m][l] > 0)
                                cov_hit_count = cov_hit_count + 1;

        $display("===========================================");
        $display("PASS: tb_vproc_adder");
        $display("  total_checks      = %0d", total_checks);
        $display("  random_checks     = %0d", random_iter);
        $display("  directed_checks   = %0d", (3*2*2*2*16*12));
        $display("  mode_cov_hit      = %0d / %0d", cov_hit_count, (3*2*2*2*16));
        $display("  total_fails       = %0d", total_fails);
        $display("===========================================");
        $finish;
    end
endmodule

