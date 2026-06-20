module mux8to1 (
	input logic [31:0] in0,
	input logic [31:0] in1,
	input logic [31:0] in2,
	input logic [31:0] in3,
	input logic [31:0] in4,
	input logic [31:0] in5,
	input logic [31:0] in6,
	input logic [31:0] in7,
	input logic [2:0]  sel,
	
	output logic [31:0] out
);
	
	always_comb begin
		case (sel)
			4'd0: out = in0;
			4'd1: out = in1;
			4'd2: out = in2;
			4'd3: out = in3;
			4'd4: out = in4;
			4'd5: out = in5;
			4'd6: out = in6;
			4'd7: out = in7;
		endcase
	end
	
endmodule
	


