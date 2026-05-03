module mux2X1(
    input logic in0, in1,
    input logic sel,
    output logic out
);
always_comb begin
	case(sel) 
		1'b0: out = in0;
		1'b1: out = in1;
	endcase
end
endmodule 
