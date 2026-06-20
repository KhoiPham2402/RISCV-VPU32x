module alu (
	input logic [31:0]	i_operand_a,
	input logic [31:0]	i_operand_b,
	input logic [3:0]		i_alu_op,
	input logic				func7,
	
	output logic [31:0]	o_alu_data
);
	
	logic [31:0] opb;
	logic [31:0] o_sum_data;
	logic [31:0] xor_data;
	logic [31:0] or_data;
	logic [31:0] and_data;
	logic [31:0] sltu_data;
	logic [31:0] slt_data;
	logic [31:0] sr_data;
	logic [31:0] sll_data;
	logic			 less;
	

assign slt_data 	= {31'd0,less};
	
word_xor XORER (	.in1	(i_operand_b),
						.in2	({32{i_alu_op[3]}}),
						.out	(opb));

adder ADD (	.i_operand_a (i_operand_a),
				.i_operand_b (opb),
				.cin (i_alu_op[3]),
				.o_sum_data (o_sum_data));
				
word_xor XOR (	.in1(i_operand_a),
					.in2(i_operand_b),
					.out(xor_data));
				
word_or OR	(	.in1(i_operand_a),
					.in2(i_operand_b),
					.out(or_data));
					
word_and AND (	.in1(i_operand_a),
					.in2(i_operand_b),
					.out(and_data));
brc	COMP	(	.i_rs1_data(i_operand_a),
			.i_rs2_data(i_operand_b),
			.i_br_un(!i_alu_op[0]),
			.func3(3'd0),
			.o_br_less(less));
	
barrel_shifter_32bit SR (	.data (i_operand_a),
									.is_arithmetic (func7),
									.amt (i_operand_b[4:0]),
									.out (sr_data));
									
barrel_shifter_32bit_left SLL (	.data (i_operand_a),
											.amt (i_operand_b[4:0]),
											.out (sll_data));
	
mux8to1 MUX (	.in0 (o_sum_data),
				.in1 (sll_data),
				.in2 (slt_data),
				.in3 (slt_data),
				.in4 (xor_data),
				.in5 (sr_data),
				.in6 (or_data),
				.in7 (and_data),
				.sel (i_alu_op[2:0]),
				.out (o_alu_data));
				
endmodule 
