module adder (
	input logic [31:0] 	i_operand_a,
	input logic [31:0] 	i_operand_b,
	input logic					 	cin,
	
	output logic [31:0] 	o_sum_data,
	output logic 					cout
);
	logic c1, c2, c3, cnr;

	eight_bit_adder BYTE0 (	.a 	(i_operand_a [7:0]),
									.b 	(i_operand_b [7:0]),
									.cin 	(cin),
									.s 	(o_sum_data  [7:0]),
									.cout (c1));
	eight_bit_adder BYTE1 (	.a 	(i_operand_a [15:8]),
									.b 	(i_operand_b [15:8]),
									.cin 	(c1),
									.s 	(o_sum_data[15:8]),
									.cout (c2));
	eight_bit_adder BYTE2 (	.a 	(i_operand_a [23:16]),
									.b 	(i_operand_b [23:16]),
									.cin 	(c2),
									.s 	(o_sum_data[23:16]),
									.cout (c3));
	eight_bit_adder BYTE3 (	.a 	(i_operand_a [31:24]),
									.b 	(i_operand_b [31:24]),
									.cin 	(c3),
									.s 	(o_sum_data[31:24]),
									.cout (cout));
endmodule 