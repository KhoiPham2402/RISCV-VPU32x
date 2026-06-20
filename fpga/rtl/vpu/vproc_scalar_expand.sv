// Expand scalar/immediate theo sew để match số phần tử trong 1 lane.
// sew mapping theo RVV:
//   3'd0: 4x8
//   3'd1: 2x16 (replicate 16-bit)
//   3'd2: 1x32

module vproc_scalar_expand (
    input  [31:0] data_in,
    input  [2:0]  sew,
    output reg [31:0] data_out
);
    always @(*) begin
        case (sew)
            3'd0: data_out = {data_in[7:0], data_in[7:0], data_in[7:0], data_in[7:0]};
            3'd1: data_out = {data_in[15:0], data_in[15:0]};
            3'd2: data_out = data_in;
            default: data_out = data_in;
        endcase
    end
endmodule

