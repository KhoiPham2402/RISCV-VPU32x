module mag_comparator8 (
	input logic [7:0] 	in1,
	input logic [7:0] 	in2,
	input logic 			i_eq,
	input logic 			i_lt,
	input logic 			i_gt,
	
	output logic 			o_eq,
	output logic			o_gt,
	output logic			o_lt
);

	logic [6:0] eq;
	logic [6:0] gt;
	logic [6:0] lt;
	
	brc_comparator COMP7 (	.in1(in1[7]), 
								.in2(in2[7]),
								.i_eq(i_eq),
								.i_gt(i_gt),
								.i_lt(i_lt),
								.o_eq(eq[6]),
								.o_lt(lt[6]),
								.o_gt(gt[6]));
	brc_comparator COMP6 (	.in1(in1[6]), 
								.in2(in2[6]),
								.i_eq(eq[6]),
								.i_gt(gt[6]),
								.i_lt(lt[6]),
								.o_eq(eq[5]),
								.o_lt(lt[5]),
								.o_gt(gt[5]));						
	brc_comparator COMP5 (	.in1(in1[5]), 
								.in2(in2[5]),
								.i_eq(eq[5]),
								.i_gt(gt[5]),
								.i_lt(lt[5]),
								.o_eq(eq[4]),
								.o_lt(lt[4]),
								.o_gt(gt[4]));				
	brc_comparator COMP4 (	.in1(in1[4]), 
								.in2(in2[4]),
								.i_eq(eq[4]),
								.i_gt(gt[4]),
								.i_lt(lt[4]),
								.o_eq(eq[3]),
								.o_lt(lt[3]),
								.o_gt(gt[3]));	
	brc_comparator COMP3 (	.in1(in1[3]), 
								.in2(in2[3]),
								.i_eq(eq[3]),
								.i_gt(gt[3]),
								.i_lt(lt[3]),
								.o_eq(eq[2]),
								.o_lt(lt[2]),
								.o_gt(gt[2]));
	brc_comparator COMP2 (	.in1(in1[2]), 
								.in2(in2[2]),
								.i_eq(eq[2]),
								.i_gt(gt[2]),
								.i_lt(lt[2]),
								.o_eq(eq[1]),
								.o_lt(lt[1]),
								.o_gt(gt[1]));
	brc_comparator COMP1 (	.in1(in1[1]), 
								.in2(in2[1]),
								.i_eq(eq[1]),
								.i_gt(gt[1]),
								.i_lt(lt[1]),
								.o_eq(eq[0]),
								.o_lt(lt[0]),
								.o_gt(gt[0]));
	brc_comparator COMP0 (	.in1(in1[0]), 
								.in2(in2[0]),
								.i_eq(eq[0]),
								.i_gt(gt[0]),
								.i_lt(lt[0]),
								.o_eq(o_eq),
								.o_lt(o_lt),
								.o_gt(o_gt));
endmodule 			