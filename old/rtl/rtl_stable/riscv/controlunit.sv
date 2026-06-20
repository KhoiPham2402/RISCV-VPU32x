/* verilator lint_off UNUSED */
module controlunit(
	input logic [31:0] instr,
	input logic br_equal,
	input logic br_less,
	output logic br_sel,
	output logic rd_wren,
	output logic br_unsigned,
	output logic op_a_sel,
	output logic op_b_sel,
	output logic [3:0] alu_op,
	output logic mem_wren,
	output logic mem_rden,
	output logic [1:0] wb_sel,
	output logic o_insn_vld,
	output logic [2:0] load_sel,
	output logic [1:0] store_sel
);

logic [6:0] opcode;
logic [2:0] func3;

assign opcode = instr[6:0];
assign func3  = instr[14:12];

localparam R_TYPE  	 = 7'b0110011;
localparam I_TYPE 	 = 7'b0010011;
localparam S_TYPE  	 = 7'b0100011;
localparam B_TYPE	 = 7'b1100011;
localparam LOAD_TYPE = 7'b0000011;
localparam LUI 		 = 7'b0110111;
localparam AUIPC	 = 7'b0010111;
localparam JALR 	 = 7'b1100111;
localparam JAL 		 = 7'b1101111;

always @(*) begin
	o_insn_vld = 0;
	case(opcode) // instruction[6:0]
		R_TYPE: begin
			br_sel    = 1'b0; 										
			rd_wren   = 1'b1;
			op_a_sel  = 1'b0;
			op_b_sel  = 1'b0;
			mem_wren  = 1'b0;
			wb_sel    = 2'b00;
			load_sel  = 3'b000;
			store_sel = 2'b00;
			br_unsigned = 0;
			mem_rden = 0;
			case(func3)
				3'b000: alu_op = (instr[30] == 0)?4'b0000:4'b0001;	// ADD
				3'b010: alu_op = 4'b0010; 							// SLT
				3'b011: begin										// SLTU
					alu_op = 4'b0011;
					br_unsigned = 1;
				end 
				3'b100: alu_op = 4'b0100; 							// XOR
				3'b110: alu_op = 4'b0101; 							// OR
				3'b111: alu_op = 4'b0110; 							// AND
				3'b001: alu_op = 4'b0111; 							// SLL
				3'b101: alu_op = (instr[30] == 0)?4'b1000:4'b1001; 	// SRL/SRA
				default: begin
					alu_op = 4'b0000;
					o_insn_vld = 1;
				end
			endcase
		end

		I_TYPE: begin
			br_sel   = 1'b0;  										
			rd_wren  = 1'b1;
			op_a_sel = 1'b0;
			op_b_sel = 1'b1;
			mem_wren = 1'b0;
			wb_sel   = 2'b00;
			load_sel  = 3'b000;
			store_sel = 2'b00;
			br_unsigned = 0;
			mem_rden = 0;
			case(func3)
				3'b000: alu_op = 4'b0000; 							// ADDI
				3'b010: alu_op = 4'b0010; 							// SLTI
				3'b011: begin										// SLTU
					alu_op = 4'b0011;
					br_unsigned = 1;
				end 												
				3'b100: alu_op = 4'b0100; 							// XORI
				3'b110: alu_op = 4'b0101; 							// ORI
				3'b111: alu_op = 4'b0110; 							// ANDI
				3'b001: alu_op = 4'b0111; 							// SLLI
				3'b101: alu_op = (instr[30] == 0)?4'b1000:4'b1001; 	// SRLI/SRAI
				default: begin
					alu_op = 4'b0000;
					o_insn_vld = 1;
				end
			endcase
		end

		S_TYPE: begin
			br_sel = 1'b0;
			br_unsigned = 0;
			load_sel  = 3'b000;
			store_sel = 2'b00;
			wb_sel   = 2'b00;		
			mem_rden = 0;
			case(func3)					
				3'b000: begin										// SB
					op_a_sel  = 1'b0;
					op_b_sel  = 1'b1;
					mem_wren  = 1'b1;
					rd_wren   = 1'b0;
					alu_op 	  = 4'b0000;
					store_sel = 2'b01;
				end
				3'b001: begin										// SH
					op_a_sel  = 1'b0;
					op_b_sel  = 1'b1;
					mem_wren  = 1'b1;
					rd_wren	  = 1'b0;
					alu_op	  = 4'b0000;
					store_sel = 2'b10;
				end
				3'b010: begin										// SW
					op_a_sel  = 1'b0;
					op_b_sel  = 1'b1;
					mem_wren  = 1'b1;
					rd_wren   = 1'b0;
					alu_op 	  = 4'b0000;
					store_sel = 2'b11;
				end
				default: begin
					op_a_sel  = 1'b0;
					op_b_sel  = 1'b0;
					mem_wren  = 1'b0;
					rd_wren   = 1'b0;
					alu_op 	 = 4'b0000;
					store_sel = 2'b00;
					o_insn_vld = 1;
				end 
			endcase
		end

		B_TYPE: begin
			wb_sel   = 2'b00;
			mem_wren  = 1'b0;
			alu_op = 4'b0000;
			op_a_sel = 1'b1;
			op_b_sel = 1'b1;
			rd_wren = 1'b0;
			load_sel  = 3'b000;
			store_sel = 2'b00;
			br_unsigned = 0;
			mem_rden = 0;
			case(func3)
			3'b000: begin	// BEQ
				br_sel = br_equal?1'b1:1'b0;
			end
			3'b001: begin	// BNE
				br_sel = !br_equal?1'b1:1'b0;
			end
			3'b100: begin 	// BLT
				br_sel = br_less?1'b1:1'b0;
			end
			3'b101: begin	// BGE
				br_sel = !br_less?1'b1:1'b0;
			end
			3'b110: begin	// BLTU
				br_sel = br_less?1'b1:1'b0;
				br_unsigned = 1'b1;
			end
			3'b111: begin	// BGEU
				br_sel = !br_less?1'b1:1'b0;
			 	br_unsigned = 1'b1;
			end
			default: begin
				br_sel = 0;
				br_unsigned = 1'b0;
				o_insn_vld = 1;
			end
			endcase
		end


		LOAD_TYPE: begin
			br_sel    = 1'b0;
			store_sel = 2'b00; 
			br_unsigned = 0;
			mem_rden = 1;
			case(func3)
				3'b000: begin // LB
					op_a_sel = 1'b0;
					op_b_sel = 1'b1;
					wb_sel = 2'b01;
					rd_wren = 1'b1;
					alu_op = 4'b0000;
					mem_wren = 1'b0;
					load_sel = 3'b001;
				end
				3'b001: begin // LH
					op_a_sel = 1'b0;
					op_b_sel = 1'b1;
					wb_sel = 2'b01;
					rd_wren = 1'b1;
					alu_op = 4'b0000;
					mem_wren = 1'b0;
					load_sel = 3'b010;
				end
				3'b100: begin // LBU
					op_a_sel = 1'b0;
					op_b_sel = 1'b1;
					wb_sel = 2'b01;
					rd_wren = 1'b1;
					alu_op = 4'b0000;
					mem_wren = 1'b0;
					load_sel = 3'b011;
				end
				3'b101: begin // LHU
					op_a_sel = 1'b0;
					op_b_sel = 1'b1;
					wb_sel = 2'b01;
					rd_wren = 1'b1;
					alu_op = 4'b0000;
					mem_wren = 1'b0;
					load_sel = 3'b100;
				end
				3'b010: begin // LW
					op_a_sel = 1'b0;
					op_b_sel = 1'b1;
					wb_sel = 2'b01;
					rd_wren = 1'b1;
					alu_op = 4'b0000;
					mem_wren = 1'b0;
					load_sel = 3'b101;
				end
				default: begin
					op_a_sel = 1'b0;
					op_b_sel = 1'b0;
					wb_sel = 2'b00;
					rd_wren = 1'b0;
					alu_op = 4'b0000;
					mem_wren = 1'b0;
					load_sel = 3'b000;
					o_insn_vld = 1;
				end
			endcase
		end


		LUI: begin
			br_sel   = 1'b0; 
			br_unsigned = 0;
			op_a_sel = 1'b0;
			op_b_sel = 1'b1;
			rd_wren = 1'b1;
			mem_wren = 1'b0;
			wb_sel = 2'b00;
			alu_op = 4'b1010;
			load_sel  = 3'b000;
			store_sel = 2'b00;
			mem_rden = 0;
		end

		JAL: begin
			mem_wren = 1'b0;
			br_sel   = 1'b1;
			br_unsigned = 0;	
			op_a_sel = 1'b1;
			op_b_sel = 1'b1;
			rd_wren  = 1'b1;
			wb_sel 	 = 2'b10;
			alu_op 	 = 4'b0000;
			load_sel  = 3'b000;
			store_sel = 2'b00;
			mem_rden = 0;
		end

		JALR: begin
			br_sel   = 1'b1; 
			br_unsigned = 0;
			op_a_sel = 1'b0;
			op_b_sel = 1'b1;
			rd_wren  = 1'b1;
			wb_sel   = 2'b11;
			alu_op   = 4'b0000;
			mem_wren = 1'b0;
			load_sel  = 3'b000;
			store_sel = 2'b00;
			mem_rden = 0;
		end

		AUIPC: begin
			br_sel   = 1'b0; 
			br_unsigned = 0;
			wb_sel   = 2'b00;
			mem_wren = 1'b0;
			op_a_sel = 1'b1;
			op_b_sel = 1'b1;
			alu_op   = 4'b0000;
			rd_wren  = 1'b1;
			load_sel  = 3'b000;
			store_sel = 2'b00;
			mem_rden = 0;
		end
		default: begin
			br_sel   = 1'b0; 
			br_unsigned = 0;
			wb_sel   = 2'b00;
			mem_wren = 1'b0;
			op_a_sel = 1'b0;
			op_b_sel = 1'b0;
			alu_op   = 4'b0000;
			rd_wren  = 1'b0;
			load_sel  = 3'b000;
			store_sel = 2'b00;
			o_insn_vld = 1;
			mem_rden = 0;
		end
	endcase
end
endmodule
