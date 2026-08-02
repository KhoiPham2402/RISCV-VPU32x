// Behavioral-style adder/subtractor, viết theo kiểu Verilog cũ
// Hỗ trợ:
//   sew = 0 : 4 phép  8-bit ( 8 +-  8) độc lập
//   sew = 1 : 2 phép 16-bit (16 +- 16) độc lập
//   sew = 2 : 1 phép 32-bit (32 +- 32)
//
// Đồng thời hỗ trợ "widening" cho mọi sew với 2 ngõ ra:
//   - result_lo: phần "thấp" theo sew
//   - result_hi: phần "cao" theo sew (mở rộng dấu hoặc zero-extend tùy unsign)
//
// Mapping với các lệnh kiểu RISC-V 64-bit (ý nghĩa logic):
//   - unsign = 0 : xử lý như signed (addw/subw)
//                  -> result_hi = sign-extend(result_lo[31])
//   - unsign = 1 : xử lý như unsigned (addwu/subwu)
//                  -> result_hi = 32'b0 (zero-extend)
//
// Carry/borrow từ v0 (use_carry = vadc/vsbc/vmadc/vmsbc):
//   - Cộng:  op_a + op_b + carry_in[i]        (ADC / vmadc cộng)
//   - Trừ:   op_a - op_b - carry_in[i]
//            = op_a + ~op_b + (1 - carry_in[i]) = op_a + ~op_b + ~carry_in[i] khi carry_in ∈ {0,1}
//   - Trừ không dùng v0 (vsub...): op_a + ~op_b + 1

module vproc_adder (
    input  [31:0] op_a,       // toán hạng A
    input  [31:0] op_b,       // toán hạng B
    input         use_carry,  // 1: dùng carry_in, 0: carry mặc định = 0 khi cộng
    input         use_mask_carry, // 1: xuất kết quả dạng carry/borrow mask cho vd
    input  [3:0]  carry_in,   // carry-in từ v0, dùng theo sew
    input         sub,        // 0: cộng, 1: trừ (A - B)
    input  [2:0]  sew,        // 0: 4x8-bit, 1: 2x16-bit, 2: 32-bit
    input         unsign,     // 0: signed (addw/subw), 1: unsigned (addwu/subwu)
    output [31:0] result_lo,  // kết quả thấp theo sew
    output [31:0] result_hi,  // kết quả cao (widening cho sew = 0)
    output [3:0]  carry_mask_out // bit carry/borrow theo phần tử (tối đa 4 phần tử/lane)
);

    reg [31:0] result_lo_r;
    reg [31:0] result_hi_r;
    reg [3:0] carry_mask_out_r;

    assign result_lo = result_lo_r;
    assign result_hi = result_hi_r;
    assign carry_mask_out = carry_mask_out_r;

    // dùng thêm bit phụ để giữ carry trong từng lane, tránh lan sang lane khác
    reg [32:0] tmp32;
    reg [16:0] tmp16_lo, tmp16_hi;
    reg [8:0]  tmp8_0, tmp8_1, tmp8_2, tmp8_3;

    // Bit thứ ba của A + (~B|B) + ?:  ADC dùng +cin; SBC dùng +~cin; vsub dùng +1.
    function automatic logic adder_third_1b(
        input logic sub_i,
        input logic use_c,
        input logic cin_b
    );
        if (!sub_i)
            adder_third_1b = use_c ? cin_b : 1'b0;
        else
            adder_third_1b = use_c ? ~cin_b : 1'b1;
    endfunction

    always_comb begin
        // mặc định
        result_lo_r = 32'b0;
        result_hi_r = 32'b0;
        carry_mask_out_r = 4'b0;

        case (sew)
            3'd0: begin
                // 4 phép 8-bit độc lập
                tmp8_0 = {1'b0, op_a[7:0]} +
                         {1'b0, (sub ? ~op_b[7:0] : op_b[7:0])} +
                         adder_third_1b(sub, use_carry, carry_in[0]);

                tmp8_1 = {1'b0, op_a[15:8]} +
                         {1'b0, (sub ? ~op_b[15:8] : op_b[15:8])} +
                         adder_third_1b(sub, use_carry, carry_in[1]);

                tmp8_2 = {1'b0, op_a[23:16]} +
                         {1'b0, (sub ? ~op_b[23:16] : op_b[23:16])} +
                         adder_third_1b(sub, use_carry, carry_in[2]);

                tmp8_3 = {1'b0, op_a[31:24]} +
                         {1'b0, (sub ? ~op_b[31:24] : op_b[31:24])} +
                         adder_third_1b(sub, use_carry, carry_in[3]);

                result_lo_r[7:0]   = tmp8_0[7:0];
                result_lo_r[15:8]  = tmp8_1[7:0];
                result_lo_r[23:16] = tmp8_2[7:0];
                result_lo_r[31:24] = tmp8_3[7:0];

                if (~unsign) begin
                    result_hi_r[7:0]   = {8{result_lo_r[7]}};
                    result_hi_r[15:8]  = {8{result_lo_r[15]}};
                    result_hi_r[23:16] = {8{result_lo_r[23]}};
                    result_hi_r[31:24] = {8{result_lo_r[31]}};
                end else begin
                    result_hi_r = 32'b0;
                end

                if (use_mask_carry) begin
                    carry_mask_out_r = {tmp8_3[8], tmp8_2[8], tmp8_1[8], tmp8_0[8]};
                end
            end

            3'd1: begin
                // 2 phép 16-bit độc lập
                tmp16_lo = {1'b0, op_a[15:0]} +
                           {1'b0, (sub ? ~op_b[15:0] : op_b[15:0])} +
                           adder_third_1b(sub, use_carry, carry_in[0]);

                tmp16_hi = {1'b0, op_a[31:16]} +
                           {1'b0, (sub ? ~op_b[31:16] : op_b[31:16])} +
                           adder_third_1b(sub, use_carry, carry_in[1]);

                // phần thấp (16 bit) cho mỗi lane
                result_lo_r[15:0]  = tmp16_lo[15:0];
                result_lo_r[31:16] = tmp16_hi[15:0];

                // phần cao cho mỗi lane: sign-extend hoặc zero-extend 16-bit kết quả
                if (~unsign) begin
                    // signed: widening bằng cách sign-extend bit cao của mỗi lane
                    result_hi_r[15:0]  = {16{result_lo_r[15]}};
                    result_hi_r[31:16] = {16{result_lo_r[31]}};
                end else begin
                    // unsigned: zero-extend
                    result_hi_r[15:0]  = 16'b0;
                    result_hi_r[31:16] = 16'b0;
                end

                if (use_mask_carry) begin
                    carry_mask_out_r = {2'b0, tmp16_hi[16], tmp16_lo[16]};
                end
            end

            3'd2: begin
                // 32-bit +- 32-bit, có widening lên 64-bit
                tmp32 = {1'b0, op_a} +
                        {1'b0, (sub ? ~op_b : op_b)} +
                        adder_third_1b(sub, use_carry, carry_in[0]);

                result_lo_r = tmp32[31:0];

                if (~unsign) begin
                    result_hi_r = {32{result_lo_r[31]}};
                end else begin
                    result_hi_r = 32'b0;
                end

                if (use_mask_carry) begin
                    carry_mask_out_r = {3'b0, tmp32[32]};
                end
            end

            default: begin
                result_lo_r = 32'b0;
                result_hi_r = 32'b0;
            end
        endcase
    end

endmodule

