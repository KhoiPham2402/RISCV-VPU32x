module brc_comparator (
	input logic in1,
	input logic in2,
	input logic i_lt,
	input logic i_gt,
	input logic i_eq,
	
	output logic o_eq,
	output logic o_gt,
	output logic o_lt
);

	assign o_eq = i_eq & !(in1 ^ in2);
	assign o_lt = i_lt | (i_eq & !in1 & in2);
	assign o_gt = i_gt | (i_eq & in1 & !in2);
	
endmodule 