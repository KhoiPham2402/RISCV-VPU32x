// =============================================================================
// scalar_core_v2.sv  —  RV32IM Scalar Core, 2-Stage Pipeline
//
// Pipeline stages:
//   IF : PC register drives imem_sync. Instruction valid 1 cycle later.
//   EX : Decode + RF read + ALU + branch resolution + load/store.
//
// Hazards:
//   Load stall  : 1 extra cycle when EX has a load (sync DMEM latency).
//                 ex_bubble injected; DMEM result committed from load_wb_*.
//   Branch flush: 1 cycle penalty; instruction in IF stage discarded.
//   VPU stall   : entire pipeline frozen (PC held, IMEM frozen, EX held).
//
// Memory:
//   DMEM 0x0000_0000–0x0000_FFFF via TL-UL bus (slave 0).
//   UART 0xFF00_00xx via TL-UL bus (slave 1).
//   IO registers 0x1000_xxxx directly inside this module (no bus latency).
//
// External interface is drop-in compatible with single_cycle.sv
// (same VPU ports, same IO ports, same pc_debug/insn_vld).
// =============================================================================
import tl_pkg::*;

module scalar_core_v2 (
    input  logic         clk,
    input  logic         rst_n,

    // ── Board IO ─────────────────────────────────────────────────────────────
    input  logic [31:0]  io_sw_i,
    output logic [31:0]  io_ledr_o,
    output logic [31:0]  io_ledg_o,
    output logic [31:0]  io_lcd_o,
    output logic [ 6:0]  io_hex0_o,
    output logic [ 6:0]  io_hex1_o,
    output logic [ 6:0]  io_hex2_o,
    output logic [ 6:0]  io_hex3_o,
    output logic [ 6:0]  io_hex4_o,
    output logic [ 6:0]  io_hex5_o,
    output logic [ 6:0]  io_hex6_o,
    output logic [ 6:0]  io_hex7_o,

    // ── Debug ─────────────────────────────────────────────────────────────────
    output logic [31:0]  pc_debug_o,
    output logic         insn_vld_o,

    // ── VPU interface (same as single_cycle.sv) ───────────────────────────────
    input  logic         vpu_ready_i,
    input  logic         vpu_cfg_done_i,
    input  logic [31:0]  vpu_vl_remain_i,
    output logic         vpu_insn_vld_o,
    output logic [31:0]  vpu_insn_o,
    output logic [31:0]  vpu_rs1_data_o,
    output logic [31:0]  vpu_rs2_data_o,
    output logic [11:0]  csr_addr_o,
    input  logic [31:0]  csr_rdata_i,

    // ── TL-UL master port (→ xbar → DMEM/UART) ───────────────────────────────
    output tl_a_t        tl_a_o,
    input  tl_d_t        tl_d_i
);
    // =========================================================================
    // Local parameters and constants
    // =========================================================================
    localparam logic [31:0] NOP = 32'h0000_0013;  // addi x0,x0,0
    localparam logic [15:0] IO_BASE  = 16'h1000;  // 0x1000_xxxx: LEDs / HEX / LCD
    localparam logic [15:0] IO_BASE_SW = 16'h1001; // 0x1001_0000: switches

    // =========================================================================
    // Register File (32 × 32-bit, synchronous write / combinatorial read)
    // =========================================================================
    logic [31:0] rf [0:31];

    function automatic logic [31:0] rf_read(input logic [4:0] addr);
        return (addr == 5'd0) ? 32'd0 : rf[addr];
    endfunction

    // =========================================================================
    // Pipeline registers
    // =========================================================================
    logic [31:0] pc_reg;       // PC for current IMEM fetch (IF stage)
    logic        ex_bubble;    // 1 = EX stage holds a bubble (NOP)
    logic [31:0] pc_ex;        // PC of instruction in EX (for debug / AUIPC / JAL)
    logic        stall_all;    // = vpu_stall (driven in pipeline section)

    // IMEM sync output (= instruction in EX stage when ex_bubble=0)
    logic [31:0] instr_raw;    // registered IMEM output

    wire  [31:0] instr_ex = ex_bubble ? NOP : instr_raw;

    // =========================================================================
    // IMEM instantiation (from the shared rtl/ directory)
    // =========================================================================
    // en_i = 0 during VPU stall to freeze IMEM output (freeze EX instruction)
    logic imem_en;
    imem_sync #(.DEPTH(2048)) u_imem (
        .clk     (clk),
        .rst_n   (rst_n),
        .en_i    (imem_en),
        .pc_i    (pc_reg),
        .instr_o (instr_raw)
    );

    // =========================================================================
    // Decode — combinatorial from instr_ex
    // =========================================================================
    logic [6:0]  opcode;
    logic [4:0]  rs1_addr, rs2_addr, rd_addr;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [31:0] rs1_data, rs2_data;

    assign opcode   = instr_ex[6:0];
    assign rd_addr  = instr_ex[11:7];
    assign funct3   = instr_ex[14:12];
    assign rs1_addr = instr_ex[19:15];
    assign rs2_addr = instr_ex[24:20];
    assign funct7   = instr_ex[31:25];

    assign rs1_data = rf_read(rs1_addr);
    assign rs2_data = rf_read(rs2_addr);

    // Instruction categories
    logic is_rtype, is_itype, is_load, is_store, is_branch, is_jal, is_jalr;
    logic is_lui, is_auipc, is_system, is_vpu, is_vls;
    logic is_vpu_config, vpu_insn_vld, vpu_stall;

    assign is_rtype  = (opcode == 7'b0110011);
    assign is_itype  = (opcode == 7'b0010011);
    assign is_load   = (opcode == 7'b0000011);
    assign is_store  = (opcode == 7'b0100011);
    assign is_branch = (opcode == 7'b1100011);
    assign is_jal    = (opcode == 7'b1101111);
    assign is_jalr   = (opcode == 7'b1100111);
    assign is_lui    = (opcode == 7'b0110111);
    assign is_auipc  = (opcode == 7'b0010111);
    assign is_system = (opcode == 7'b1110011);
    assign is_vpu    = (opcode == 7'b1010111);   // OP-V
    assign is_vls    = (opcode == 7'b0000111) || (opcode == 7'b0100111); // VL/VS

    assign is_vpu_config = is_vpu && (instr_ex[14:12] == 3'b111);  // vsetvl/vsetvli/vsetivli only
    assign vpu_insn_vld  = (is_vpu || is_vls) && !ex_bubble;

    // =========================================================================
    // Immediate generation
    // =========================================================================
    logic [31:0] imm;

    always_comb begin
        case (opcode)
            7'b0010011,  // I-type (ALU immediate)
            7'b0000011,  // LOAD
            7'b1100111,  // JALR
            7'b1110011:  // SYSTEM (CSR)
                imm = {{20{instr_ex[31]}}, instr_ex[31:20]};
            7'b0100011:  // STORE
                imm = {{20{instr_ex[31]}}, instr_ex[31:25], instr_ex[11:7]};
            7'b1100011:  // BRANCH
                imm = {{19{instr_ex[31]}}, instr_ex[31], instr_ex[7],
                        instr_ex[30:25], instr_ex[11:8], 1'b0};
            7'b0110111,  // LUI
            7'b0010111:  // AUIPC
                imm = {instr_ex[31:12], 12'd0};
            7'b1101111:  // JAL
                imm = {{11{instr_ex[31]}}, instr_ex[31], instr_ex[19:12],
                        instr_ex[20], instr_ex[30:21], 1'b0};
            7'b1010111:  // OP-V (use zimm for vsetvli)
                imm = {27'd0, instr_ex[19:15]};
            default:
                imm = 32'd0;
        endcase
    end

    // =========================================================================
    // ALU
    // =========================================================================
    logic [31:0] alu_a, alu_b, alu_result;
    logic [63:0] mulh_tmp;

    // Operand A: rs1 or PC
    assign alu_a = (is_auipc || is_jal) ? pc_ex : rs1_data;

    // Operand B: rs2 or immediate
    assign alu_b = (is_rtype || is_branch) ? rs2_data : imm;

    // ALU operation
    always_comb begin
        case (opcode)
            7'b0110011: begin  // R-type: base ISA or M-extension (funct7=0000001)
                if (funct7 == 7'b0000001) begin  // M-extension
                    case (funct3)
                        3'b000: alu_result = alu_a * alu_b;
                        3'b001: begin mulh_tmp = $signed({{32{alu_a[31]}},alu_a}) * $signed({{32{alu_b[31]}},alu_b}); alu_result = mulh_tmp[63:32]; end
                        3'b010: begin mulh_tmp = $signed({{32{alu_a[31]}},alu_a}) * {1'b0,alu_b}; alu_result = mulh_tmp[63:32]; end
                        3'b011: begin mulh_tmp = {1'b0,alu_a} * {1'b0,alu_b}; alu_result = mulh_tmp[63:32]; end
                        3'b100: alu_result = $signed(alu_a) / $signed(alu_b);
                        3'b101: alu_result = alu_a / alu_b;
                        3'b110: alu_result = $signed(alu_a) % $signed(alu_b);
                        3'b111: alu_result = alu_a % alu_b;
                    endcase
                end else begin  // base R-type
                    case (funct3)
                        3'b000: alu_result = funct7[5] ? alu_a - alu_b : alu_a + alu_b;
                        3'b001: alu_result = alu_a << alu_b[4:0];
                        3'b010: alu_result = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;
                        3'b011: alu_result = (alu_a < alu_b) ? 32'd1 : 32'd0;
                        3'b100: alu_result = alu_a ^ alu_b;
                        3'b101: alu_result = funct7[5] ? $signed($signed(alu_a) >>> alu_b[4:0])
                                                        : alu_a >> alu_b[4:0];
                        3'b110: alu_result = alu_a | alu_b;
                        3'b111: alu_result = alu_a & alu_b;
                    endcase
                end
            end
            7'b0010011: begin  // I-type ALU
                case (funct3)
                    3'b000: alu_result = alu_a + alu_b;   // ADDI
                    3'b001: alu_result = alu_a << alu_b[4:0];
                    3'b010: alu_result = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;
                    3'b011: alu_result = (alu_a < alu_b) ? 32'd1 : 32'd0;
                    3'b100: alu_result = alu_a ^ alu_b;
                    3'b101: alu_result = funct7[5] ? $signed($signed(alu_a) >>> alu_b[4:0])
                                                   : alu_a >> alu_b[4:0];
                    3'b110: alu_result = alu_a | alu_b;
                    3'b111: alu_result = alu_a & alu_b;
                endcase
            end
            default: alu_result = alu_a + alu_b;  // LOAD/STORE addr, JAL/JALR, BRANCH, AUIPC
        endcase
    end

    // =========================================================================
    // Branch resolution
    // =========================================================================
    logic br_taken;
    always_comb begin
        br_taken = 1'b0;
        if (is_branch && !ex_bubble) begin
            case (funct3)
                3'b000: br_taken = (rs1_data == rs2_data);
                3'b001: br_taken = (rs1_data != rs2_data);
                3'b100: br_taken = ($signed(rs1_data) <  $signed(rs2_data));
                3'b101: br_taken = ($signed(rs1_data) >= $signed(rs2_data));
                3'b110: br_taken = (rs1_data <  rs2_data);
                3'b111: br_taken = (rs1_data >= rs2_data);
                default: br_taken = 1'b0;
            endcase
        end
    end

    logic branch_flush;
    assign branch_flush = (br_taken || is_jal || is_jalr) && !ex_bubble;

    // =========================================================================
    // Next-PC computation
    // =========================================================================
    logic [31:0] pc_next;
    always_comb begin
        if (is_jal || (is_branch && br_taken))
            pc_next = pc_ex + imm;          // PC-relative
        else if (is_jalr)
            pc_next = (rs1_data + imm) & ~32'd1;  // indirect
        else
            pc_next = pc_reg + 32'd4;       // sequential (pc_reg = next fetch addr)
    end

    // =========================================================================
    // VPU stall (same logic as single_cycle.sv)
    // =========================================================================
    logic vpu_cfg_pending_r;
    // Gate on vpu_ready_i: pending_r must only set once the FIFO actually
    // accepts the instruction.  Without this, if vpu_ready=0 when vsetvl
    // arrives, pending_r sets (blocking vpu_insn_vld_o) but the instruction
    // is never pushed, so vpu_cfg_done_i never fires → deadlock.
    wire  vpu_cfg_start = vpu_insn_vld && is_vpu_config && !vpu_cfg_pending_r && vpu_ready_i;

    always_ff @(posedge clk) begin
        if (!rst_n)
            vpu_cfg_pending_r <= 1'b0;
        else if (vpu_cfg_done_i)
            vpu_cfg_pending_r <= 1'b0;
        else if (vpu_cfg_start)
            vpu_cfg_pending_r <= 1'b1;
    end

    wire vpu_cfg_stall = vpu_cfg_start | (vpu_cfg_pending_r & ~vpu_cfg_done_i);
    assign vpu_stall   = (vpu_insn_vld & ~vpu_ready_i) | vpu_cfg_stall;

    // =========================================================================
    // TL-UL memory request generation
    // =========================================================================
    // IO range check
    logic is_io_region, is_io_sw;
    assign is_io_region = (alu_result[31:16] == IO_BASE);
    assign is_io_sw     = (alu_result[31:16] == IO_BASE_SW);
    logic is_dmem;
    assign is_dmem = !is_io_region && !is_io_sw && !ex_bubble;

    // Byte enable from funct3 and address[1:0]
    logic [3:0] store_be;
    always_comb begin
        case (funct3)
            3'b000: case (alu_result[1:0])  // SB
                2'b00: store_be = 4'b0001;
                2'b01: store_be = 4'b0010;
                2'b10: store_be = 4'b0100;
                2'b11: store_be = 4'b1000;
            endcase
            3'b001: store_be = alu_result[1] ? 4'b1100 : 4'b0011;  // SH
            default: store_be = 4'b1111;  // SW
        endcase
    end

    // TL-UL A channel
    always_comb begin
        tl_a_o = TL_A_IDLE;
        if (!ex_bubble && !vpu_stall && (is_load || is_store) && is_dmem) begin
            tl_a_o.valid   = 1'b1;
            tl_a_o.address = alu_result;
            tl_a_o.size    = 3'd2;  // 4 bytes (word)
            if (is_store) begin
                tl_a_o.opcode = (funct3 == 3'b010) ? TL_A_PUT_FULL : TL_A_PUT_PARTIAL;
                tl_a_o.mask   = store_be;
                tl_a_o.data   = rs2_data;
            end else begin
                tl_a_o.opcode = TL_A_GET;
                tl_a_o.mask   = 4'b1111;
            end
        end else if (!ex_bubble && !vpu_stall &&
                     (alu_result[31:8] == 24'hFF0000) && (is_load || is_store)) begin
            // UART region via TL-UL
            tl_a_o.valid   = 1'b1;
            tl_a_o.address = alu_result;
            tl_a_o.size    = 3'd2;
            if (is_store) begin
                tl_a_o.opcode = TL_A_PUT_FULL;
                tl_a_o.mask   = 4'b1111;
                tl_a_o.data   = rs2_data;
            end else begin
                tl_a_o.opcode = TL_A_GET;
            end
        end
    end

    // =========================================================================
    // Load stall detection
    // =========================================================================
    // Stall when EX has a load (sync DMEM, result arrives next cycle).
    // For IO range loads the result is combinatorial — no stall needed.
    logic load_stall;
    assign load_stall = is_load && is_dmem && !ex_bubble && !vpu_stall;

    // =========================================================================
    // Load write-back pending
    // =========================================================================
    logic        load_wb_pending_r;
    logic [4:0]  load_wb_rd_r;
    logic [2:0]  load_wb_op_r;
    logic [1:0]  load_wb_addr_lo_r;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            load_wb_pending_r <= 1'b0;
        end else begin
            load_wb_pending_r <= load_stall;
            if (load_stall) begin
                load_wb_rd_r      <= rd_addr;
                load_wb_op_r      <= funct3;
                load_wb_addr_lo_r <= alu_result[1:0];
            end
        end
    end

    // Sign/zero-extend loaded data (from TL-UL D channel)
    logic [31:0] load_result;
    always_comb begin
        logic [31:0] raw;
        raw = tl_d_i.data;
        case (load_wb_op_r)
            3'b000: case (load_wb_addr_lo_r)  // LB
                2'b00: load_result = {{24{raw[7]}},  raw[7:0]};
                2'b01: load_result = {{24{raw[15]}}, raw[15:8]};
                2'b10: load_result = {{24{raw[23]}}, raw[23:16]};
                2'b11: load_result = {{24{raw[31]}}, raw[31:24]};
            endcase
            3'b001: load_result = load_wb_addr_lo_r[1] ?  // LH
                {{16{raw[31]}}, raw[31:16]} : {{16{raw[15]}}, raw[15:0]};
            3'b100: case (load_wb_addr_lo_r)  // LBU
                2'b00: load_result = {24'd0, raw[7:0]};
                2'b01: load_result = {24'd0, raw[15:8]};
                2'b10: load_result = {24'd0, raw[23:16]};
                2'b11: load_result = {24'd0, raw[31:24]};
            endcase
            3'b101: load_result = load_wb_addr_lo_r[1] ?  // LHU
                {16'd0, raw[31:16]} : {16'd0, raw[15:0]};
            default: load_result = raw;  // LW
        endcase
    end

    // =========================================================================
    // IO Registers (direct, no TL-UL — LEDs/HEX/LCD/SW)
    // =========================================================================
    logic [31:0] reg_ledr, reg_ledg, reg_hexl, reg_hexh, reg_lcd;
    logic [31:0] reg_sw;

    // Helper function: apply SB/SH/SW to a 32-bit register word
    function automatic logic [31:0] io_store(
        input logic [31:0] curr,
        input logic [31:0] wdata,
        input logic [2:0]  op,
        input logic [1:0]  addr_lo
    );
        logic [31:0] result;
        result = curr;
        case (op)
            3'b000: case (addr_lo)  // SB
                2'b00: result[7:0]   = wdata[7:0];
                2'b01: result[15:8]  = wdata[7:0];
                2'b10: result[23:16] = wdata[7:0];
                2'b11: result[31:24] = wdata[7:0];
            endcase
            3'b001: if (addr_lo[1]) result[31:16] = wdata[15:0];  // SH
                    else            result[15:0]  = wdata[15:0];
            default: result = wdata;  // SW
        endcase
        return result;
    endfunction

    logic io_store_en;
    assign io_store_en = is_store && is_io_region && !ex_bubble && !vpu_stall;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            reg_ledr <= '0;  reg_ledg <= '0;
            reg_hexl <= '0;  reg_hexh <= '0;  reg_lcd  <= '0;
            reg_sw   <= '0;
        end else begin
            reg_sw <= io_sw_i;
            if (io_store_en) begin
                case (alu_result[15:12])
                    4'h0: reg_ledr <= io_store(reg_ledr, rs2_data, funct3, alu_result[1:0]);
                    4'h1: reg_ledg <= io_store(reg_ledg, rs2_data, funct3, alu_result[1:0]);
                    4'h2: reg_hexl <= io_store(reg_hexl, rs2_data, funct3, alu_result[1:0]);
                    4'h3: reg_hexh <= io_store(reg_hexh, rs2_data, funct3, alu_result[1:0]);
                    4'h4: reg_lcd  <= io_store(reg_lcd,  rs2_data, funct3, alu_result[1:0]);
                    default: ;
                endcase
            end
        end
    end

    // IO load data (combinatorial — no stall for IO reads)
    logic [31:0] io_load_data;
    always_comb begin
        io_load_data = 32'd0;
        if (is_io_region) begin
            case (alu_result[15:12])
                4'h0: io_load_data = reg_ledr;
                4'h1: io_load_data = reg_ledg;
                4'h2: io_load_data = reg_hexl;
                4'h3: io_load_data = reg_hexh;
                4'h4: io_load_data = reg_lcd;
                default: ;
            endcase
        end else if (is_io_sw) begin
            io_load_data = reg_sw;
        end
    end

    // =========================================================================
    // Write-back mux
    // =========================================================================
    logic        wb_en;
    logic [4:0]  wb_rd;
    logic [31:0] wb_data;

    // Priority: load_wb_pending > vpu_cfg_done > normal EX
    always_comb begin
        wb_en   = 1'b0;
        wb_rd   = 5'd0;
        wb_data = 32'd0;

        if (load_wb_pending_r) begin
            wb_en   = (load_wb_rd_r != 5'd0);
            wb_rd   = load_wb_rd_r;
            wb_data = load_result;
        end else if (vpu_cfg_done_i) begin
            wb_en   = (rd_addr != 5'd0);
            wb_rd   = rd_addr;
            wb_data = vpu_vl_remain_i;
        end else if (!ex_bubble && !vpu_stall && !is_store && !is_branch) begin
            logic [31:0] alu_wb;
            case (opcode)
                7'b0110111: alu_wb = imm;          // LUI
                7'b0010111: alu_wb = alu_result;   // AUIPC (pc_ex + imm)
                7'b1101111,
                7'b1100111: alu_wb = pc_ex + 32'd4; // JAL/JALR (return addr)
                7'b0000011: alu_wb = io_load_data;  // IO load (no stall)
                7'b1110011: alu_wb = csr_rdata_i;   // CSRR*
                default:    alu_wb = alu_result;    // R/I-type
            endcase
            // IO loads write back here; DMEM/bus loads use load_wb_pending path
            wb_en   = (rd_addr != 5'd0) && (!is_load || is_io_region || is_io_sw);
            wb_rd   = rd_addr;
            wb_data = alu_wb;
        end
    end

    // Register file write
    always_ff @(posedge clk) begin
        if (wb_en)
            rf[wb_rd] <= wb_data;
    end

    // =========================================================================
    // Pipeline registers update
    // =========================================================================
    assign stall_all = vpu_stall;  // freeze everything during VPU stall

    // IMEM enable: freeze when VPU stalling
    assign imem_en = !stall_all;

    // PC register
    always_ff @(posedge clk) begin
        if (!rst_n)
            pc_reg <= 32'h0;
        else if (!stall_all && !load_stall)
            pc_reg <= branch_flush ? pc_next : pc_reg + 32'd4;
    end

    // PC of instruction in EX (for AUIPC/JAL/JALR/debug)
    always_ff @(posedge clk) begin
        if (!rst_n)
            pc_ex <= 32'h0;
        else if (!stall_all && !load_stall)
            pc_ex <= pc_reg;
    end

    // ex_bubble register
    always_ff @(posedge clk) begin
        if (!rst_n)
            ex_bubble <= 1'b1;   // start with bubble
        else if (!stall_all)
            ex_bubble <= branch_flush || load_stall;
    end

    // =========================================================================
    // Debug / insn_vld
    // =========================================================================
    logic insn_vld_r;
    always_ff @(posedge clk) begin
        if (!rst_n) insn_vld_r <= 1'b0;
        else        insn_vld_r <= !ex_bubble && !vpu_stall;
    end

    assign insn_vld_o  = insn_vld_r;
    assign pc_debug_o  = pc_ex;

    // =========================================================================
    // VPU interface outputs
    // =========================================================================
    assign vpu_insn_vld_o  = vpu_insn_vld & ~vpu_cfg_pending_r;
    assign vpu_insn_o      = instr_ex;
    assign vpu_rs1_data_o  = rs1_data;
    assign vpu_rs2_data_o  = rs2_data;
    assign csr_addr_o      = instr_ex[31:20];

    // =========================================================================
    // IO output assignments
    // =========================================================================
    assign io_ledr_o = reg_ledr;
    assign io_ledg_o = reg_ledg;
    assign io_lcd_o  = reg_lcd;
    assign io_hex0_o = reg_hexl[ 6: 0];
    assign io_hex1_o = reg_hexl[14: 8];
    assign io_hex2_o = reg_hexl[22:16];
    assign io_hex3_o = reg_hexl[30:24];
    assign io_hex4_o = reg_hexh[ 6: 0];
    assign io_hex5_o = reg_hexh[14: 8];
    assign io_hex6_o = reg_hexh[22:16];
    assign io_hex7_o = reg_hexh[30:24];

endmodule
