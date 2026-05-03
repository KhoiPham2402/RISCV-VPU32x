module immgen (
    input  logic [24:0] instr,   // instr[31:7]
    input  logic [2:0]  Immsel,  // từ Controller
    output logic [31:0] imm
);

    logic [31:0] imm_I, imm_S, imm_B, imm_U, imm_J;

    // Decode từng loại immediate
    // Ghi chú: instr[25] <=> instr[31], instr[24:20] <=> instr[30:26], ...

    // I-type: imm[11:0] = instr[31:20]
    assign imm_I = {{21{instr[24]}}, instr[23:13]};

    // S-type: imm[11:5] = instr[31:25], imm[4:0] = instr[11:7]
    assign imm_S = {{21{instr[24]}}, instr[23:18], instr[4:0]};

    // B-type: imm[12] = instr[31], imm[10:5] = instr[30:25],
    //          imm[4:1] = instr[11:8], imm[11] = instr[7], imm[0] = 0
    assign imm_B = {{20{instr[24]}}, instr[0], instr[23:18], instr[4:1], 1'b0};

    // U-type: imm[31:12] = instr[31:12], imm[11:0] = 0
	 assign imm_U = {instr[24:5], {12{1'b0}}};
    // J-type: imm[20] = instr[31], imm[10:1] = instr[30:21],
    //          imm[11] = instr[20], imm[19:12] = instr[19:12], imm[0] = 0
    assign imm_J = {{12{instr[24]}}, instr[12:5], instr[13], instr[23:18], instr[17:14], 1'b0};

    always_comb begin
        unique case(Immsel)
            3'b000: imm = imm_I;   // I-type (ADDI, LOAD, JALR, ...)
            3'b001: imm = imm_S;   // S-type (SW, SB, SH)
            3'b010: imm = imm_B;   // B-type (BEQ, BNE, ...)
            3'b011: imm = imm_U;   // U-type (LUI, AUIPC)
            3'b100: imm = imm_J;   // J-type (JAL)
            default: imm = 32'b0;
        endcase
    end

endmodule
