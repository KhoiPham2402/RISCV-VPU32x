// Behavioral multiplier, thân thiện với Verilog cũ
// Hỗ trợ sew giống vproc_adder:
//   sew = 0 : 4 phép nhân  8x8  -> mỗi tích 16 bit, pack vào các lane 8-bit lo/hi
//   sew = 1 : 2 phép nhân 16x16 -> mỗi tích 32 bit, pack vào các lane 16-bit lo/hi
//   sew = 2 : 1 phép nhân 32x32  -> tích 64 bit (lo/hi 32-bit)
//
// unsign_a / unsign_b áp dụng cho toàn bộ phép nhân (từng lane được mở rộng
// sign/zero giống nhau):
//   unsign_a = 0, unsign_b = 0 : signed * signed  (mul / mulh)
//   unsign_a = 1, unsign_b = 1 : unsigned * unsigned (mulhu)
//   unsign_a = 0, unsign_b = 1 : signed * unsigned (mulhsu)

module vproc_mul (
    input  [31:0] op_a,
    input  [31:0] op_b,
    input  [2:0]  sew,        // 0: 4x8-bit, 1: 2x16-bit, 2: 32-bit
    input         unsign_a,   // 1: op_a là unsigned, 0: op_a là signed
    input         unsign_b,   // 1: op_b là unsigned, 0: op_b là signed
    output [31:0] result_lo,  // phần thấp theo sew
    output [31:0] result_hi   // phần cao theo sew
);

    reg [31:0] result_lo_r;
    reg [31:0] result_hi_r;

    assign result_lo = result_lo_r;
    assign result_hi = result_hi_r;

    // Biến tạm cho các mode khác nhau
    reg signed [63:0] a_ext32, b_ext32, prod32;

    reg signed [31:0] a16_lo_ext, b16_lo_ext, prod16_lo;
    reg signed [31:0] a16_hi_ext, b16_hi_ext, prod16_hi;

    reg signed [15:0] a8_0_ext, b8_0_ext, prod8_0;
    reg signed [15:0] a8_1_ext, b8_1_ext, prod8_1;
    reg signed [15:0] a8_2_ext, b8_2_ext, prod8_2;
    reg signed [15:0] a8_3_ext, b8_3_ext, prod8_3;

    always @(*) begin
        // mặc định
        result_lo_r = 32'b0;
        result_hi_r = 32'b0;

        case (sew)
            3'd0: begin
                // 4 phép nhân 8x8 độc lập
                if (unsign_a) a8_0_ext = {8'b0, op_a[7:0]};    else a8_0_ext = {{8{op_a[7]}}, op_a[7:0]};
                if (unsign_b) b8_0_ext = {8'b0, op_b[7:0]};    else b8_0_ext = {{8{op_b[7]}}, op_b[7:0]};
                prod8_0 = a8_0_ext * b8_0_ext;

                if (unsign_a) a8_1_ext = {8'b0, op_a[15:8]};   else a8_1_ext = {{8{op_a[15]}}, op_a[15:8]};
                if (unsign_b) b8_1_ext = {8'b0, op_b[15:8]};   else b8_1_ext = {{8{op_b[15]}}, op_b[15:8]};
                prod8_1 = a8_1_ext * b8_1_ext;

                if (unsign_a) a8_2_ext = {8'b0, op_a[23:16]};  else a8_2_ext = {{8{op_a[23]}}, op_a[23:16]};
                if (unsign_b) b8_2_ext = {8'b0, op_b[23:16]};  else b8_2_ext = {{8{op_b[23]}}, op_b[23:16]};
                prod8_2 = a8_2_ext * b8_2_ext;

                if (unsign_a) a8_3_ext = {8'b0, op_a[31:24]};  else a8_3_ext = {{8{op_a[31]}}, op_a[31:24]};
                if (unsign_b) b8_3_ext = {8'b0, op_b[31:24]};  else b8_3_ext = {{8{op_b[31]}}, op_b[31:24]};
                prod8_3 = a8_3_ext * b8_3_ext;

                result_lo_r[7:0]   = prod8_0[7:0];
                result_lo_r[15:8]  = prod8_1[7:0];
                result_lo_r[23:16] = prod8_2[7:0];
                result_lo_r[31:24] = prod8_3[7:0];
                result_hi_r[7:0]   = prod8_0[15:8];
                result_hi_r[15:8]  = prod8_1[15:8];
                result_hi_r[23:16] = prod8_2[15:8];
                result_hi_r[31:24] = prod8_3[15:8];
            end

            3'd1: begin
                // 2 phép nhân 16x16 độc lập
                // Lane thấp: [15:0]
                if (unsign_a)
                    a16_lo_ext = {16'b0, op_a[15:0]};
                else
                    a16_lo_ext = {{16{op_a[15]}}, op_a[15:0]};

                if (unsign_b)
                    b16_lo_ext = {16'b0, op_b[15:0]};
                else
                    b16_lo_ext = {{16{op_b[15]}}, op_b[15:0]};

                prod16_lo = a16_lo_ext * b16_lo_ext;  // 32 bit

                // Lane cao: [31:16]
                if (unsign_a)
                    a16_hi_ext = {16'b0, op_a[31:16]};
                else
                    a16_hi_ext = {{16{op_a[31]}}, op_a[31:16]};

                if (unsign_b)
                    b16_hi_ext = {16'b0, op_b[31:16]};
                else
                    b16_hi_ext = {{16{op_b[31]}}, op_b[31:16]};

                prod16_hi = a16_hi_ext * b16_hi_ext;  // 32 bit

                // Phần thấp 16-bit cho mỗi lane
                result_lo_r[15:0]  = prod16_lo[15:0];
                result_lo_r[31:16] = prod16_hi[15:0];

                // Phần cao 16-bit cho mỗi lane
                result_hi_r[15:0]  = prod16_lo[31:16];
                result_hi_r[31:16] = prod16_hi[31:16];
            end

            3'd2: begin
                // 1 phép nhân 32x32 -> 64 bit
                if (unsign_a) a_ext32 = {32'b0, op_a};
                else          a_ext32 = {{32{op_a[31]}}, op_a};

                if (unsign_b) b_ext32 = {32'b0, op_b};
                else          b_ext32 = {{32{op_b[31]}}, op_b};

                prod32 = a_ext32 * b_ext32;
                result_lo_r = prod32[31:0];
                result_hi_r = prod32[63:32];
            end

            default: begin
                result_lo_r = 32'b0;
                result_hi_r = 32'b0;
            end
        endcase
    end

endmodule

