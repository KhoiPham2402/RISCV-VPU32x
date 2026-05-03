// Module dịch bit 32-bit, hỗ trợ nhiều lane theo sew (giống vproc_adder):
//   - ctrl = 0 : shift left (logical)
//   - ctrl = 1 : shift right (logical hoặc arithmetic tùy arith)
//   - arith = 1 : arithmetic right shift (giữ dấu), chỉ có ý nghĩa khi ctrl = 1
//   - sew = 0 : 4 phép shift  8-bit độc lập (mỗi lane shamt 0..7)
//   - sew = 1 : 2 phép shift 16-bit độc lập (mỗi lane shamt 0..15)
//   - sew = 2 : 1 phép shift 32-bit (shamt 0..31)
//   - shamt_in: lượng dịch; sew=2 dùng [4:0], sew=1 dùng [3:0] và [19:16],
//               sew=0 dùng [2:0],[10:8],[18:16],[26:24]

module vproc_shifter (
    input  [31:0] op_in,
    input  [31:0] shamt_in,
    input  [2:0]  sew,
    input         ctrl,       // 0: left shift, 1: right shift
    input         arith,      // 0: logical, 1: arithmetic (chỉ khi ctrl=1)
    output [31:0] result
);

    reg [31:0] result_r;
    assign result = result_r;

    always @(*) begin
        result_r = 32'b0;

        case (sew)
            3'd0: begin
                if (ctrl == 1'b0) begin
                    result_r[7:0]   = op_in[7:0]   << shamt_in[2:0];
                    result_r[15:8]  = op_in[15:8]  << shamt_in[10:8];
                    result_r[23:16] = op_in[23:16] << shamt_in[18:16];
                    result_r[31:24] = op_in[31:24] << shamt_in[26:24];
                end else if (arith) begin
                    result_r[7:0]   = $signed(op_in[7:0])   >>> shamt_in[2:0];
                    result_r[15:8]  = $signed(op_in[15:8])  >>> shamt_in[10:8];
                    result_r[23:16] = $signed(op_in[23:16]) >>> shamt_in[18:16];
                    result_r[31:24] = $signed(op_in[31:24]) >>> shamt_in[26:24];
                end else begin
                    result_r[7:0]   = op_in[7:0]   >> shamt_in[2:0];
                    result_r[15:8]  = op_in[15:8]  >> shamt_in[10:8];
                    result_r[23:16] = op_in[23:16] >> shamt_in[18:16];
                    result_r[31:24] = op_in[31:24] >> shamt_in[26:24];
                end
            end

            3'd1: begin
                if (ctrl == 1'b0) begin
                    result_r[15:0]  = op_in[15:0]  << shamt_in[3:0];
                    result_r[31:16] = op_in[31:16] << shamt_in[19:16];
                end else if (arith) begin
                    result_r[15:0]  = $signed(op_in[15:0])  >>> shamt_in[3:0];
                    result_r[31:16] = $signed(op_in[31:16]) >>> shamt_in[19:16];
                end else begin
                    result_r[15:0]  = op_in[15:0]  >> shamt_in[3:0];
                    result_r[31:16] = op_in[31:16] >> shamt_in[19:16];
                end
            end

            3'd2: begin
                if (ctrl == 1'b0)
                    result_r = op_in << shamt_in[4:0];
                else if (arith)
                    result_r = $signed(op_in) >>> shamt_in[4:0];
                else
                    result_r = op_in >> shamt_in[4:0];
            end

            default: begin
                result_r = 32'b0;
            end
        endcase
    end

endmodule
