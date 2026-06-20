// Min/Max cho 2 operand 32-bit theo tung phan tu, ho tro signed/unsigned.
// Mapping sew:
//   sew=0 -> 4 phan tu 8-bit
//   sew=1 -> 2 phan tu 16-bit
//   sew=2 -> 1 phan tu 32-bit
module vproc_minmax (
    input  [31:0] op_a,
    input  [31:0] op_b,
    input  [2:0]  sew,
    input         is_min,     // 1: min, 0: max
    input         is_unsign,  // 1: unsigned compare, 0: signed compare
    output reg [31:0] result
);

    reg [7:0]  a8_0, a8_1, a8_2, a8_3;
    reg [7:0]  b8_0, b8_1, b8_2, b8_3;
    reg [15:0] a16_0, a16_1;
    reg [15:0] b16_0, b16_1;
    reg        a8_0_lt_b8_0_s, a8_0_gt_b8_0_s;
    reg        a8_1_lt_b8_1_s, a8_1_gt_b8_1_s;
    reg        a8_2_lt_b8_2_s, a8_2_gt_b8_2_s;
    reg        a8_3_lt_b8_3_s, a8_3_gt_b8_3_s;
    reg        a16_0_lt_b16_0_s, a16_0_gt_b16_0_s;
    reg        a16_1_lt_b16_1_s, a16_1_gt_b16_1_s;
    reg        a32_lt_b32_s, a32_gt_b32_s;
    reg [31:0] out32;

    always @(*) begin
        result = 32'b0;

        case (sew)
            3'd0: begin
                // 4 lane x 8-bit
                a8_0 = op_a[7:0];    b8_0 = op_b[7:0];
                a8_1 = op_a[15:8];   b8_1 = op_b[15:8];
                a8_2 = op_a[23:16];  b8_2 = op_b[23:16];
                a8_3 = op_a[31:24];  b8_3 = op_b[31:24];

                a8_0_lt_b8_0_s = (a8_0[7] ^ b8_0[7]) ? a8_0[7] : (a8_0[6:0] < b8_0[6:0]);
                a8_0_gt_b8_0_s = (a8_0[7] ^ b8_0[7]) ? b8_0[7] : (a8_0[6:0] > b8_0[6:0]);
                a8_1_lt_b8_1_s = (a8_1[7] ^ b8_1[7]) ? a8_1[7] : (a8_1[6:0] < b8_1[6:0]);
                a8_1_gt_b8_1_s = (a8_1[7] ^ b8_1[7]) ? b8_1[7] : (a8_1[6:0] > b8_1[6:0]);
                a8_2_lt_b8_2_s = (a8_2[7] ^ b8_2[7]) ? a8_2[7] : (a8_2[6:0] < b8_2[6:0]);
                a8_2_gt_b8_2_s = (a8_2[7] ^ b8_2[7]) ? b8_2[7] : (a8_2[6:0] > b8_2[6:0]);
                a8_3_lt_b8_3_s = (a8_3[7] ^ b8_3[7]) ? a8_3[7] : (a8_3[6:0] < b8_3[6:0]);
                a8_3_gt_b8_3_s = (a8_3[7] ^ b8_3[7]) ? b8_3[7] : (a8_3[6:0] > b8_3[6:0]);

                if (is_unsign) begin
                    if (is_min) begin
                        result[7:0]    = (a8_0 <= b8_0) ? a8_0 : b8_0;
                        result[15:8]   = (a8_1 <= b8_1) ? a8_1 : b8_1;
                        result[23:16]  = (a8_2 <= b8_2) ? a8_2 : b8_2;
                        result[31:24]  = (a8_3 <= b8_3) ? a8_3 : b8_3;
                    end else begin
                        result[7:0]    = (a8_0 >= b8_0) ? a8_0 : b8_0;
                        result[15:8]   = (a8_1 >= b8_1) ? a8_1 : b8_1;
                        result[23:16]  = (a8_2 >= b8_2) ? a8_2 : b8_2;
                        result[31:24]  = (a8_3 >= b8_3) ? a8_3 : b8_3;
                    end
                end else begin
                    if (is_min) begin
                        result[7:0]    = a8_0_gt_b8_0_s ? b8_0 : a8_0;
                        result[15:8]   = a8_1_gt_b8_1_s ? b8_1 : a8_1;
                        result[23:16]  = a8_2_gt_b8_2_s ? b8_2 : a8_2;
                        result[31:24]  = a8_3_gt_b8_3_s ? b8_3 : a8_3;
                    end else begin
                        result[7:0]    = a8_0_lt_b8_0_s ? b8_0 : a8_0;
                        result[15:8]   = a8_1_lt_b8_1_s ? b8_1 : a8_1;
                        result[23:16]  = a8_2_lt_b8_2_s ? b8_2 : a8_2;
                        result[31:24]  = a8_3_lt_b8_3_s ? b8_3 : a8_3;
                    end
                end
            end

            3'd1: begin
                // 2 lane x 16-bit
                a16_0 = op_a[15:0];    b16_0 = op_b[15:0];
                a16_1 = op_a[31:16];   b16_1 = op_b[31:16];

                a16_0_lt_b16_0_s = (a16_0[15] ^ b16_0[15]) ? a16_0[15] : (a16_0[14:0] < b16_0[14:0]);
                a16_0_gt_b16_0_s = (a16_0[15] ^ b16_0[15]) ? b16_0[15] : (a16_0[14:0] > b16_0[14:0]);
                a16_1_lt_b16_1_s = (a16_1[15] ^ b16_1[15]) ? a16_1[15] : (a16_1[14:0] < b16_1[14:0]);
                a16_1_gt_b16_1_s = (a16_1[15] ^ b16_1[15]) ? b16_1[15] : (a16_1[14:0] > b16_1[14:0]);

                if (is_unsign) begin
                    if (is_min) begin
                        result[15:0]   = (a16_0 <= b16_0) ? a16_0 : b16_0;
                        result[31:16]  = (a16_1 <= b16_1) ? a16_1 : b16_1;
                    end else begin
                        result[15:0]   = (a16_0 >= b16_0) ? a16_0 : b16_0;
                        result[31:16]  = (a16_1 >= b16_1) ? a16_1 : b16_1;
                    end
                end else begin
                    if (is_min) begin
                        result[15:0]   = a16_0_gt_b16_0_s ? b16_0 : a16_0;
                        result[31:16]  = a16_1_gt_b16_1_s ? b16_1 : a16_1;
                    end else begin
                        result[15:0]   = a16_0_lt_b16_0_s ? b16_0 : a16_0;
                        result[31:16]  = a16_1_lt_b16_1_s ? b16_1 : a16_1;
                    end
                end
            end

            3'd2: begin
                // 1 lane x 32-bit
                a32_lt_b32_s = (op_a[31] ^ op_b[31]) ? op_a[31] : (op_a[30:0] < op_b[30:0]);
                a32_gt_b32_s = (op_a[31] ^ op_b[31]) ? op_b[31] : (op_a[30:0] > op_b[30:0]);
                if (is_unsign) begin
                    if (is_min)
                        out32 = (op_a <= op_b) ? op_a : op_b;
                    else
                        out32 = (op_a >= op_b) ? op_a : op_b;
                end else begin
                    if (is_min)
                        out32 = a32_gt_b32_s ? op_b : op_a;
                    else
                        out32 = a32_lt_b32_s ? op_b : op_a;
                end

                result = out32;
            end

            default: begin
                result = 32'b0;
            end
        endcase
    end

endmodule
