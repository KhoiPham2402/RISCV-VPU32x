module d_ff (
	input logic D,
	input logic clk,
	input logic en,
	input logic rst_n,
	
	output logic Q
);
	
	logic Q_next;
	
	always_comb begin
		if (en) begin
			Q_next = D;
		end else begin
			Q_next = Q;
		end
	end

	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			Q <= 1'b0;
		end else begin
			Q <= Q_next;
		end
	end
endmodule
