module register_file #(
	parameter int DATA_W = 32,
	parameter int ADDR_W = 5
)(
	input logic 		  	i_clk,
	input logic 			i_rst,
	input logic [ADDR_W-1:0] 	i_rs1_addr,
	input logic [ADDR_W-1:0] 	i_rs2_addr,
	input logic [DATA_W-1:0] 	i_rd_data,
	input logic [ADDR_W-1:0] 	i_rd_addr,
	input logic			i_rd_wren,
	
	output logic [DATA_W-1:0] 	o_rs1_data,
	output logic [DATA_W-1:0] 	o_rs2_data
);

	logic [31:0] 	data0;
	logic [31:0]	data1;
	logic [31:0]	data2;
	logic [31:0]	data3;
	logic [31:0]	data4;
	logic [31:0]	data5;
	logic [31:0]	data6;
	logic [31:0]	data7;
	logic [31:0]	data8;
	logic [31:0]	data9;
	logic [31:0]	data10;
	logic [31:0]	data11;
	logic [31:0]	data12;
	logic [31:0]	data13;
	logic [31:0]	data14;
	logic [31:0]	data15;
	logic [31:0]	data16;
	logic [31:0]	data17;
	logic [31:0]	data18;
	logic [31:0]	data19;
	logic [31:0]	data20;
	logic [31:0]	data21;
	logic [31:0]	data22;
	logic [31:0]	data23;
	logic [31:0]	data24;
	logic [31:0]	data25;
	logic [31:0]	data26;
	logic [31:0]	data27;
	logic [31:0]	data28;
	logic [31:0]	data29;
	logic [31:0]	data30;
	logic [31:0]	data31;
	logic [31:0]	enW;
	
	decoder5to32 DECODE (	.in(i_rd_addr),
				.en(i_rd_wren),
				.out(enW));
	Regfile	REGFILE	(
		.D    (i_rd_data),
		.clk  (i_clk),
		.rst_n(i_rst),        // active low reset
		.en   (enW),
		.q0   (data0),
		.q1   (data1),
		.q2   (data2),
		.q3   (data3),
		.q4   (data4),
		.q5   (data5),
		.q6   (data6),
		.q7   (data7),
		.q8   (data8),
		.q9   (data9),
		.q10  (data10),
		.q11  (data11),
		.q12  (data12),
		.q13  (data13),
		.q14  (data14),
		.q15  (data15),
		.q16  (data16),
		.q17  (data17),
		.q18  (data18),
		.q19  (data19),
		.q20  (data20),
		.q21  (data21),
		.q22  (data22),
		.q23  (data23),
		.q24  (data24),
		.q25  (data25),
		.q26  (data26),
		.q27  (data27),
		.q28  (data28),
		.q29  (data29),
		.q30  (data30),
		.q31  (data31)
	);
	
	mux32to1	MUX1	(
		.sel(i_rs1_addr),
		.in0(data0),
		.in1(data1),
		.in2(data2),
		.in3(data3),
		.in4(data4),
		.in5(data5),
		.in6(data6),
		.in7(data7),
		.in8(data8),
		.in9(data9),
		.in10(data10),
		.in11(data11),
		.in12(data12),
		.in13(data13),
		.in14(data14),
		.in15(data15),
		.in16(data16),
		.in17(data17),
		.in18(data18),
		.in19(data19),
		.in20(data20),
		.in21(data21),
		.in22(data22),
		.in23(data23),
		.in24(data24),
		.in25(data25),
		.in26(data26),
		.in27(data27),
		.in28(data28),
		.in29(data29),
		.in30(data30),
		.in31(data31),
		.out(o_rs1_data)
	);

	mux32to1	MUX2	(
		.sel(i_rs2_addr),
		.in0(data0),
		.in1(data1),
		.in2(data2),
		.in3(data3),
		.in4(data4),
		.in5(data5),
		.in6(data6),
		.in7(data7),
		.in8(data8),
		.in9(data9),
		.in10(data10),
		.in11(data11),
		.in12(data12),
		.in13(data13),
		.in14(data14),
		.in15(data15),
		.in16(data16),
		.in17(data17),
		.in18(data18),
		.in19(data19),
		.in20(data20),
		.in21(data21),
		.in22(data22),
		.in23(data23),
		.in24(data24),
		.in25(data25),
		.in26(data26),
		.in27(data27),
		.in28(data28),
		.in29(data29),
		.in30(data30),
		.in31(data31),
		.out(o_rs2_data)
	);
	
endmodule 
