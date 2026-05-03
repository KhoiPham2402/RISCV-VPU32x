module eight_bit_adder (
	input logic [7:0] a,
	input logic [7:0] b,
	input logic 		cin,
	
	output logic [7:0] 	s,
	output logic 			cout,
	output logic 			cnr
);

	logic [6:0] c;
	
	full_adder FA0 (.a(a[0]),.b(b[0]),.cin(cin),.s(s[0]),.cout(c[0]));
	full_adder FA1 (.a(a[1]),.b(b[1]),.cin(c[0]),.s(s[1]),.cout(c[1]));
	full_adder FA2 (.a(a[2]),.b(b[2]),.cin(c[1]),.s(s[2]),.cout(c[2]));
	full_adder FA3 (.a(a[3]),.b(b[3]),.cin(c[2]),.s(s[3]),.cout(c[3]));
	full_adder FA4 (.a(a[4]),.b(b[4]),.cin(c[3]),.s(s[4]),.cout(c[4]));
	full_adder FA5 (.a(a[5]),.b(b[5]),.cin(c[4]),.s(s[5]),.cout(c[5]));
	full_adder FA6 (.a(a[6]),.b(b[6]),.cin(c[5]),.s(s[6]),.cout(c[6]));
	full_adder FA7 (.a(a[7]),.b(b[7]),.cin(c[6]),.s(s[7]),.cout(cout));
	
	assign cnr = c[6] ;
	
endmodule 