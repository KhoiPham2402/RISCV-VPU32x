// Module xử lý các phép logic 32-bit:
//   - AND:  op_a & op_b  -> result_and
//   - OR :  op_a | op_b  -> result_or
//   - XOR:  op_a ^ op_b  -> result_xor
// Viết theo kiểu behavioral, Verilog cũ, thân thiện FPGA.

module vproc_logic (
    input  [31:0] op_a,
    input  [31:0] op_b,
    output [31:0] result_and,
    output [31:0] result_or,
    output [31:0] result_xor
);

    reg [31:0] result_and_r;
    reg [31:0] result_or_r;
    reg [31:0] result_xor_r;

    assign result_and = result_and_r;
    assign result_or  = result_or_r;
    assign result_xor = result_xor_r;

    always @(*) begin
        result_and_r = op_a & op_b;
        result_or_r  = op_a | op_b;
        result_xor_r = op_a ^ op_b;
    end

endmodule

