module mag_comparator (
	input logic [31:0] 	in1,
	input logic [31:0] 	in2,
	input logic 			i_eq,
	input logic 			i_lt,
	input logic 			i_gt,
	
	output logic 			o_eq,
	output logic			o_gt,
	output logic			o_lt
);
	logic [2:0] eq;
	logic [2:0] lt;
	logic [2:0] gt;
	
	mag_comparator8 M3( .in1 (in1[31:24]),
							.in2 (in2[31:24]),
							.i_eq(i_eq),
							.i_gt(i_gt),
							.i_lt(i_lt),
							.o_eq(eq[2]),
							.o_lt(lt[2]),
							.o_gt(gt[2]));
	
	mag_comparator8 M2( .in1 (in1[23:16]),
							.in2 (in2[23:16]),
							.i_eq(eq[2]),
							.i_gt(gt[2]),
							.i_lt(lt[2]),
							.o_eq(eq[1]),
							.o_lt(lt[1]),
							.o_gt(gt[1]));
	
	mag_comparator8 M1( .in1 (in1[15:8]),
							.in2 (in2[15:8]),
							.i_eq(eq[1]),
							.i_gt(gt[1]),
							.i_lt(lt[1]),
							.o_eq(eq[0]),
							.o_lt(lt[0]),
							.o_gt(gt[0]));
	
	mag_comparator8 M0( .in1 (in1[7:0]),
							.in2 (in2[7:0]),
							.i_eq(eq[0]),
							.i_gt(gt[0]),
							.i_lt(lt[0]),
							.o_eq(o_eq),
							.o_lt(o_lt),
							.o_gt(o_gt));
	
endmodule 