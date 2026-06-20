module brc (
	input logic [31:0]	i_rs1_data,
	input logic [31:0]	i_rs2_data,
	input logic 		i_br_un,
	
	output logic 		o_br_less,
	output logic 		o_br_equal
);

	logic o_lt;
	logic o_gt;
	logic sel;
	
	assign sel = (i_rs1_data[31] ^ i_rs2_data[31]) & i_br_un;
	
	mag_comparator comp32 (	.in1 (i_rs1_data),
				.in2 	(i_rs2_data),
				.i_eq 	(1'b1),
				.i_lt	(1'b0),
				.i_gt	(1'b0),
				.o_eq 	(o_br_equal),
				.o_gt 	(o_gt),
				.o_lt	(o_lt));
	mux2X1	MUX2to1	(	.in0 (o_lt),
				.in1 (o_gt),
				.sel (sel),
				.out (o_br_less));
								
endmodule 

