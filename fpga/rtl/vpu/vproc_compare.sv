// Module so sánh (compare) 32-bit với hỗ trợ "sew" giống adder:
//   sew = 0 : 4 phần tử  8-bit  -> 4 bit kết quả
//   sew = 1 : 2 phần tử 16-bit  -> 2 bit kết quả
//   sew = 2 : 1 phần tử 32-bit  -> 1 bit kết quả
//
// Hỗ trợ 2 loại so sánh, điều khiển bởi các tín hiệu control:
//   - is_less_than = 0 : so sánh equal (==)
//   - is_less_than = 1 : so sánh less than (<)
//       + is_unsign = 0 : so sánh dạng signed
//       + is_unsign = 1 : so sánh dạng unsigned
//
// Mapping kết quả:
//   - sew = 0 : result[0..3] cho 4 byte
//   - sew = 1 : result[0] cho 16-bit thấp, result[1] cho 16-bit cao, [3:2] = 0
//   - sew = 2 : result[0] là kết quả so sánh 32-bit, các bit khác = 0
//
// Viết theo Verilog cũ, behavioral, thân thiện FPGA.

module vproc_compare (
    input  [31:0] op_a,
    input  [31:0] op_b,
    input  [2:0]  sew,
    input         is_less_than,   // 0: eq, 1: <
    input         is_unsign,      // 0: signed, 1: unsigned (chỉ dùng khi is_less_than = 1)
    output [3:0]  cmp_result      // kết quả so sánh theo lane
);

    reg [3:0] cmp_result_r;

    assign cmp_result = cmp_result_r;

    always_comb begin
        cmp_result_r = 4'b0000;

        case (sew)
            3'd0: begin
                // 4 phần tử 8-bit
                if (!is_less_than) begin
                    cmp_result_r[0] = (op_a[7:0]    == op_b[7:0])    ? 1'b1 : 1'b0;
                    cmp_result_r[1] = (op_a[15:8]   == op_b[15:8])   ? 1'b1 : 1'b0;
                    cmp_result_r[2] = (op_a[23:16]  == op_b[23:16])  ? 1'b1 : 1'b0;
                    cmp_result_r[3] = (op_a[31:24]  == op_b[31:24])  ? 1'b1 : 1'b0;
                end else begin
                    if (is_unsign) begin
                        cmp_result_r[0] = (op_a[7:0]    < op_b[7:0])    ? 1'b1 : 1'b0;
                        cmp_result_r[1] = (op_a[15:8]   < op_b[15:8])   ? 1'b1 : 1'b0;
                        cmp_result_r[2] = (op_a[23:16]  < op_b[23:16])  ? 1'b1 : 1'b0;
                        cmp_result_r[3] = (op_a[31:24]  < op_b[31:24])  ? 1'b1 : 1'b0;
                    end else begin
                        cmp_result_r[0] = ($signed(op_a[7:0])    < $signed(op_b[7:0]))    ? 1'b1 : 1'b0;
                        cmp_result_r[1] = ($signed(op_a[15:8])   < $signed(op_b[15:8]))   ? 1'b1 : 1'b0;
                        cmp_result_r[2] = ($signed(op_a[23:16])  < $signed(op_b[23:16]))  ? 1'b1 : 1'b0;
                        cmp_result_r[3] = ($signed(op_a[31:24])  < $signed(op_b[31:24]))  ? 1'b1 : 1'b0;
                    end
                end
            end

            3'd1: begin
                // 2 phần tử 16-bit
                if (!is_less_than) begin
                    // Equal
                    cmp_result_r[0] = (op_a[15:0]  == op_b[15:0])  ? 1'b1 : 1'b0;
                    cmp_result_r[1] = (op_a[31:16] == op_b[31:16]) ? 1'b1 : 1'b0;
                end else begin
                    // Less than: signed/unsigned tùy is_unsign
                    if (is_unsign) begin
                        cmp_result_r[0] = (op_a[15:0]  < op_b[15:0])  ? 1'b1 : 1'b0;
                        cmp_result_r[1] = (op_a[31:16] < op_b[31:16]) ? 1'b1 : 1'b0;
                    end else begin
                        cmp_result_r[0] = ($signed(op_a[15:0])  < $signed(op_b[15:0]))  ? 1'b1 : 1'b0;
                        cmp_result_r[1] = ($signed(op_a[31:16]) < $signed(op_b[31:16])) ? 1'b1 : 1'b0;
                    end
                end
            end

            3'd2: begin
                // 1 phần tử 32-bit
                if (!is_less_than) begin
                    cmp_result_r[0] = (op_a == op_b) ? 1'b1 : 1'b0;
                end else begin
                    if (is_unsign)
                        cmp_result_r[0] = (op_a < op_b) ? 1'b1 : 1'b0;
                    else
                        cmp_result_r[0] = ($signed(op_a) < $signed(op_b)) ? 1'b1 : 1'b0;
                end
            end

            default: begin
                cmp_result_r = 4'b0000;
            end
        endcase
    end

endmodule

