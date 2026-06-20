//==================================================================
//  control_unit.sv – Updated for Forwarding Pipeline
//  Added: 'is_load' output signal for Hazard Detection
//==================================================================
module control_unit (
    input  logic [10:0] instr,  // 1 bit func7 + 3 bit func3 + 7 bit opcode

    output logic       br_ctrl, // 1 = lệnh branch (B-type)
    output logic       j_taken, // 1 = jal or jalr
    output logic [2:0] Immsel,
    output logic [3:0] alu_op,
    output logic [1:0] wb_sel,  // 00=Mem, 01=ALU, 10=PC+4, 11=Imm
    output logic       br_un,   // 1 = unsigned branch
    output logic       opa_sel, // 00=rs1, 01=pc
    output logic       opb_sel, // 1 = imm
    output logic       mem_wren,
    output logic       rd_wren,
    output logic       insn_vld,
    output logic       func7,   // instr[30]
    
    // NEW SIGNAL FOR HAZARD UNIT
    output logic       is_load,  // 1 = Lệnh đọc từ Memory (Load) -> Check Stall
    output logic       is_vector // Báo hiệu đây là lệnh gửi sang Vicuna
);

    // Phân rã tín hiệu
    logic [6:0] opcode;    
    logic [2:0] funct3;    
    logic       funct7_30; 

    assign opcode    = instr[6:0];
    assign funct3    = instr[9:7];
    assign funct7_30 = instr[10];

    // Opcodes Definition
    localparam logic [6:0] 
        OPC_LUI    = 7'b0110111,
        OPC_AUIPC  = 7'b0010111,
        OPC_JAL    = 7'b1101111,
        OPC_JALR   = 7'b1100111,
        OPC_BRANCH = 7'b1100011,
        OPC_LOAD   = 7'b0000011,
        OPC_STORE  = 7'b0100011,
        OPC_REGIMM = 7'b0010011, // ADDI...
        OPC_REGREG = 7'b0110011, // ADD...
        OPC_LOAD_FP  = 7'b0000111, // Vector Load (vle...)
        OPC_STORE_FP = 7'b0100111, // Vector Store (vse...)
        OPC_OP_V   = 7'b1010111; // Vector Arithmetic

    always_comb begin
        // --- Default values ---
        br_ctrl   = 1'b0;
        j_taken   = 1'b0;
        Immsel    = 3'b000;
        alu_op    = 4'b0000;
        wb_sel    = 2'b00;
        br_un     = 1'b0;
        opa_sel   = 1'b0;   // rs1
        opb_sel   = 1'b0;   // rs2
        mem_wren  = 1'b0;
        rd_wren   = 1'b0;
        insn_vld  = 1'b0;
        is_vector = 1'b0;
        func7     = funct7_30;
        is_load   = 1'b0; 

        case (opcode)
            OPC_REGREG: begin                // R-type
                insn_vld = 1'b1;
                rd_wren  = 1'b1;
                opa_sel  = 1'b0;   
                opb_sel  = 1'b0;    
                wb_sel   = 2'b01;   
                case (funct3)
                    3'b000: alu_op = {funct7_30, 3'b000}; // ADD/SUB
                    3'b001: alu_op = {funct7_30, 3'b001}; // SLL
                    3'b010: alu_op = {funct7_30, 3'b010}; // SLT
                    3'b011: alu_op = {funct7_30, 3'b011}; // SLTU
                    3'b100: alu_op = {funct7_30, 3'b100}; // XOR
                    3'b101: alu_op = {funct7_30, 3'b101}; // SRL/SRA
                    3'b110: alu_op = {funct7_30, 3'b110}; // OR
                    3'b111: alu_op = {funct7_30, 3'b111}; // AND
                endcase
            end

            OPC_REGIMM: begin                // I-type ALU
                insn_vld = 1'b1;
                rd_wren  = 1'b1;
                opa_sel  = 1'b0;   
                opb_sel  = 1'b1;    // imm
                wb_sel   = 2'b01;   
                Immsel   = 3'b000;  
                case (funct3)
                    3'b000: alu_op = 4'b0000; 
                    3'b001: alu_op = 4'b0001; 
                    3'b010: alu_op = 4'b0010; 
                    3'b011: alu_op = 4'b0011; 
                    3'b100: alu_op = 4'b0100; 
                    3'b101: alu_op = {funct7_30, 3'b101}; 
                    3'b110: alu_op = 4'b0110; 
                    3'b111: alu_op = 4'b0111; 
                endcase
            end

            OPC_LOAD: begin                  // lw/lh/lb...
                insn_vld = 1'b1;
                rd_wren  = 1'b1;
                opa_sel  = 1'b0;   
                opb_sel  = 1'b1;    
                wb_sel   = 2'b00;   // Memory data
                Immsel   = 3'b000;  
                alu_op   = 4'b0000; 
                
                // --- Đánh dấu đây là lệnh Load ---
                // Hazard Unit sẽ dùng cờ này để Stall pipeline nếu có hazard
                is_load  = 1'b1;    
            end

            OPC_STORE: begin                 // sw/sh/sb
                insn_vld = 1'b1;
                mem_wren = 1'b1;
                opa_sel  = 1'b0;   
                opb_sel  = 1'b1;    
                Immsel   = 3'b001;  
                alu_op   = 4'b0000; 
            end

            OPC_BRANCH: begin                // beq/bne...
                insn_vld = 1'b1;
                br_ctrl  = 1'b1;
                opa_sel  = 1'b1;   
                opb_sel  = 1'b1;    
                Immsel   = 3'b010;  
                case (funct3)
                    3'b000, 3'b001: br_un = 1'b0;
                    3'b100, 3'b101: br_un = 1'b0;
                    3'b110, 3'b111: br_un = 1'b1;
                endcase
            end

            OPC_JAL: begin                   // jal
                insn_vld = 1'b1;
                j_taken  = 1'b1;
                rd_wren  = 1'b1;
                wb_sel   = 2'b10;   // pc+4
                opa_sel  = 1'b1;   
                opb_sel  = 1'b1;    
                Immsel   = 3'b100;  
            end

            OPC_JALR: begin                  // jalr
                insn_vld = 1'b1;
                j_taken  = 1'b1;
                rd_wren  = 1'b1;
                wb_sel   = 2'b10;   // pc+4
                opa_sel  = 1'b0;   
                opb_sel  = 1'b1;    
                Immsel   = 3'b000;  
                alu_op   = 4'b0000;
            end

            OPC_LUI: begin                   // lui
                insn_vld = 1'b1;
                rd_wren  = 1'b1;
                opa_sel  = 1'b0;   
                opb_sel  = 1'b1;
                wb_sel   = 2'b11;   
                Immsel   = 3'b011;  
            end

            OPC_AUIPC: begin                 // auipc
                insn_vld = 1'b1;
                rd_wren  = 1'b1;
                opa_sel  = 1'b1;   
                opb_sel  = 1'b1;    
                wb_sel   = 2'b01;   
                Immsel   = 3'b011;  
                alu_op   = 4'b0000;
            end
            OPC_LOAD_FP, OPC_STORE_FP, OPC_OP_V: begin
            insn_vld  = 1'b1;
            is_vector = 1'b1;   // Báo hiệu gửi sang Vicuna
            
            // QUAN TRỌNG:
            // Với lệnh Vector Load/Store, Core chính KHÔNG tự kích hoạt mem_wren/rd_wren của nó.
            // Core chính chỉ offload lệnh, Vicuna sẽ tự sinh ra yêu cầu mem_wren sau.
            mem_wren  = 1'b0; 
            rd_wren   = 1'b0; // Trừ khi là lệnh vmv.x.s (move to scalar)
            
            // Các tín hiệu khác giữ 0
            alu_op    = 4'b0000;
        end
            default: begin
                insn_vld = 1'b0;
                rd_wren  = 1'b0;
                mem_wren = 1'b0;
            end
        endcase
    end

endmodule 