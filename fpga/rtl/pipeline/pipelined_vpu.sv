//==========================================================================
// pipelined_vpu.sv
// 5-stage RISC-V pipeline based on pipelined.sv with:
//   - Sync IMEM (imem_sync.sv): output goes directly to decode stage
//   - External scalar DMEM port (connect to dmem_sync.sv)
//   - Inlined IO registers (from lsu.sv, sync active-high reset)
//   - Inlined load-use hazard detection + EX/MEM/WB forwarding
//   - VPU custom dispatch interface
//
// Reset: synchronous, active-HIGH (i_reset)
//
// DMEM stall/retry (s_dmem_stall_i, from fpga/rtl/bus/dmem_arbiter.sv):
// scalar DMEM access can be denied on any cycle the VPU/VLSU also wants the
// shared port (VLSU has priority). On denial, ID/EX and EX/MEM freeze
// (ex_hold) so the MEM-stage instruction re-drives the identical
// address/be/wdata next cycle (sourced from already-latched alu_result_m/
// rs2_data_m/func3_m — nothing new needs to be computed to retry). MEM/WB
// takes a bubble instead of holding, since a denied access never reaches
// memory: a store is simply never committed on the denied cycle (no double
// write), and a load has no data to advance into WB yet. See vpu_insn_vld_o
// below for how a vector instruction concurrently held in EX by this same
// mechanism is prevented from double-dispatching to the VPU.
//==========================================================================

module pipelined_vpu (
    input  logic         i_clk,
    input  logic         i_reset,       // active-high synchronous

    input  logic [31:0]  i_io_sw,
    output logic [31:0]  o_io_ledr,
    output logic [31:0]  o_io_ledg,
    output logic [31:0]  o_io_lcd,
    output logic [ 6:0]  o_io_hex0,
    output logic [ 6:0]  o_io_hex1,
    output logic [ 6:0]  o_io_hex2,
    output logic [ 6:0]  o_io_hex3,
    output logic [ 6:0]  o_io_hex4,
    output logic [ 6:0]  o_io_hex5,
    output logic [ 6:0]  o_io_hex6,
    output logic [ 6:0]  o_io_hex7,

    output logic [31:0]  o_pc_debug,
    output logic         o_insn_vld,
    output logic         o_illegal_instr, // 1 = unimplemented RV32M encoding squashed in ID

    // External scalar DMEM (connect to dmem_sync.sv scalar port)
    output logic [31:0]  s_dmem_addr_o,
    output logic [31:0]  s_dmem_wdata_o,
    output logic         s_dmem_we_o,
    output logic [ 3:0]  s_dmem_be_o,
    output logic         s_dmem_re_o,
    input  logic [31:0]  s_dmem_rdata_i,
    input  logic         s_dmem_stall_i,   // 1 = DMEM port denied this cycle (arbiter, VLSU priority)

    // VPU custom interface (connect to vproc_system_wrapper)
    input  logic         vpu_ready_i,
    input  logic         vpu_cfg_done_i,
    input  logic [31:0]  vpu_vl_remain_i,
    output logic         vpu_insn_vld_o,
    output logic [31:0]  vpu_insn_o,
    output logic [31:0]  vpu_rs1_data_o,
    output logic [31:0]  vpu_rs2_data_o
);

    //==================================================================
    // Local constants
    //==================================================================
    localparam logic [31:0] NOP      = 32'h00000013; // ADDI x0, x0, 0
    localparam logic [15:0] IO_BASE0 = 16'h1000;     // LEDs/HEX/LCD
    localparam logic [15:0] IO_BASE1 = 16'h1001;     // switches

    //==================================================================
    // IF Stage
    //==================================================================
    logic [31:0] pc;
    logic [31:0] pc_four;
    logic [31:0] pc_next;

    //==================================================================
    // IF/ID Pipeline Registers
    // inst_decode driven directly by imem_sync output
    //==================================================================
    logic [31:0] inst_decode;
    logic [31:0] pcd;
    logic [31:0] pc_four_d;

    //==================================================================
    // ID Stage
    //==================================================================
    logic [4:0]  rs1_addr, rs2_addr, rd_addr;
    logic [2:0]  func3;
    logic [31:0] rs1_raw, rs2_raw;
    logic [31:0] rs1_data_d, rs2_data_d;
    logic [31:0] imm;
    logic        br_ctrl, j_taken;
    logic [2:0]  ImmSel;
    logic [3:0]  alu_op;
    logic [1:0]  wb_sel;
    logic        br_un, opa_sel, opb_sel;
    logic        mem_wren, rd_wren;
    logic        insn_vld_d, func7_d;
    logic        is_load, is_vector;
    logic        illegal_instr_d;

    //==================================================================
    // Hazard / Forwarding
    //==================================================================
    logic        stall_ld;
    logic        vpu_stall;
    logic        mem_stall;        // scalar DMEM access denied by arbiter this cycle
    logic        ex_hold;          // ID/EX + EX/MEM frozen (vpu_stall | mem_stall)
    logic        vpu_disp_done_r;  // vector insn in EX already dispatched while held
    logic        stall;
    logic        flush;
    logic        hazard;
    logic [1:0]  fwd_a, fwd_b;
    logic        rf1_fwd, rf2_fwd;

    //==================================================================
    // ID/EX Pipeline Registers
    //==================================================================
    logic [31:0] rs1_data_exe, rs2_data_exe;
    logic [31:0] imm_exe, pce, pc_four_exe;
    logic [31:0] inst_exe;
    logic [4:0]  rs1_addr_exe, rs2_addr_exe, rd_addr_exe;
    logic [2:0]  func3_exe;
    logic        br_ctrl_exe, j_ctrl_exe, br_un_exe;
    logic        opa_sel_exe, opb_sel_exe;
    logic [3:0]  alu_op_exe;
    logic        mem_wren_exe, rd_wren_exe;
    logic [1:0]  wb_sel_exe;
    logic        insn_vld_exe, func7_exe;
    logic        is_load_exe, is_vector_exe;
    logic        is_cfg_exe;          // vsetvl* in EX

    //==================================================================
    // EX Stage
    //==================================================================
    logic [31:0] rs1_data, rs2_data;
    logic [31:0] operand_a, operand_b;
    logic [31:0] alu_result;
    logic        br_taken, pc_sel;

    //==================================================================
    // EX/MEM Pipeline Registers
    //==================================================================
    logic [31:0] alu_result_m, rs2_data_m;
    logic [31:0] imm_m, pc_four_m, pcm;
    logic [2:0]  func3_m;
    logic [4:0]  rd_addr_mem;
    logic        mem_wren_mem, rd_wren_mem;
    logic [1:0]  wb_sel_mem;
    logic        insn_vld_mem, is_load_mem;

    //==================================================================
    // MEM Stage
    //==================================================================
    logic        is_io_mem;
    logic [31:0] io_rdata_mem;

    //==================================================================
    // MEM/WB Pipeline Registers
    //==================================================================
    logic [31:0] alu_result_wb, imm_wb, pc_four_wb;
    logic [2:0]  func3_wb;
    logic [1:0]  addr_lo_wb;
    logic [4:0]  rd_addr_wb;
    logic        rd_wren_wb;
    logic [1:0]  wb_sel_wb;
    logic        insn_vld_wb, is_io_wb;
    logic [31:0] io_rdata_wb;

    //==================================================================
    // WB Stage
    //==================================================================
    logic [31:0] wb_data;
    logic [31:0] raw_load_data, load_formatted;

    //==================================================================
    // Register file write (VPU cfg writeback overrides normal WB)
    //==================================================================
    logic        rf_wren;
    logic [4:0]  rf_waddr;
    logic [31:0] rf_wdata;

    //==================================================================
    // IO Registers
    //==================================================================
    logic [31:0] ledr_r, ledg_r, hexl_r, hexh_r, lcd_r, sw_r;

    //==================================================================
    // VPU Config Writeback State
    //==================================================================
    logic [4:0]  vpu_cfg_rd_r;
    logic        vpu_cfg_pending_r;

    //==================================================================
    // COMBINATIONAL LOGIC
    //==================================================================

    assign pc_four  = pc + 32'd4;
    assign pc_sel   = j_ctrl_exe | (br_taken & br_ctrl_exe);
    assign pc_next  = pc_sel ? alu_result : pc_four;
    assign flush    = pc_sel;

    assign rs1_addr = inst_decode[19:15];
    assign rs2_addr = inst_decode[24:20];
    assign rd_addr  = inst_decode[11:7];
    assign func3    = inst_decode[14:12];

    // Load-use hazard: LOAD in EX, dependent instruction in ID
    assign stall_ld = is_load_exe && (rd_addr_exe != 5'b0) &&
                      ((rd_addr_exe == rs1_addr) || (rd_addr_exe == rs2_addr));

    // VPU stall: vector instruction in EX waiting for VPU to accept.
    // vpu_disp_done_r guards against re-dispatching the same instruction if
    // EX is held for an extra cycle by mem_stall after it already dispatched
    // (see vpu_insn_vld_o below) — without it, vpu_ready staying 1 across a
    // held cycle would look identical to "not yet dispatched" and vpu_stall
    // would deassert, letting EX advance before mem_stall actually clears.
    assign vpu_stall = is_vector_exe && !vpu_ready_i && !vpu_disp_done_r;
    // Scalar DMEM access denied by the shared-bus arbiter this cycle (VLSU
    // has priority) — the MEM-stage instruction must retry next cycle.
    assign mem_stall = s_dmem_stall_i;
    assign ex_hold   = vpu_stall | mem_stall;
    assign stall     = stall_ld | ex_hold;
    assign hazard    = flush | stall_ld;  // bubble injection trigger

    // EX forwarding mux select
    always_comb begin
        if (rd_wren_mem && rd_addr_mem != 5'b0 && rd_addr_mem == rs1_addr_exe)
            fwd_a = 2'b01;   // forward from MEM (mem_fwd_value)
        else if (rf_wren && rf_waddr != 5'b0 && rf_waddr == rs1_addr_exe)
            fwd_a = 2'b10;   // forward from WB (rf_wdata)
        else
            fwd_a = 2'b00;   // use register file value

        if (rd_wren_mem && rd_addr_mem != 5'b0 && rd_addr_mem == rs2_addr_exe)
            fwd_b = 2'b01;
        else if (rf_wren && rf_waddr != 5'b0 && rf_waddr == rs2_addr_exe)
            fwd_b = 2'b10;
        else
            fwd_b = 2'b00;
    end

    // Value to forward from MEM stage (bug fix 2026-08-02). The old code
    // always forwarded alu_result_m, which is only the MEM-stage
    // instruction's real result for regular ALU ops and AUIPC (wb_sel_mem
    // == 01). For LUI (wb_sel_mem == 11) the real result is imm_m — LUI has
    // no true rs1 field, so alu_result_m for it is garbage computed from
    // whatever register instr[19:15] happens to alias. For JAL/JALR
    // (wb_sel_mem == 10) the real result is pc_four_m (the return address);
    // alu_result_m for them is the jump *target*, not the link value. Any
    // instruction immediately following a lui/jal/jalr and consuming its rd
    // (e.g. the addi half of a `li reg, <32-bit constant>` expansion) hit
    // this exact 1-cycle-apart forwarding path and got silently wrong data.
    // wb_sel_mem == 00 (LOAD) is not handled here: stall_ld guarantees a
    // load's consumer never reaches EX while the load is still in MEM — by
    // the time it does, the load is in WB and fwd_a/fwd_b already correctly
    // select 10 (forward from WB, via rf_wdata / wb_sel_wb == 00).
    logic [31:0] mem_fwd_value;
    always_comb begin
        case (wb_sel_mem)
            2'b11:   mem_fwd_value = imm_m;        // LUI
            2'b10:   mem_fwd_value = pc_four_m;    // JAL / JALR
            default: mem_fwd_value = alu_result_m; // ALU / AUIPC (01); LOAD (00, unreachable)
        endcase
    end

    // WB->ID bypass at register file read
    assign rf1_fwd = rf_wren && (rf_waddr != 5'b0) && (rf_waddr == rs1_addr);
    assign rf2_fwd = rf_wren && (rf_waddr != 5'b0) && (rf_waddr == rs2_addr);

    // VPU outputs
    assign is_cfg_exe     = is_vector_exe && (inst_exe[14:12] == 3'b111); // vsetvl*
    // A vector instruction must dispatch exactly once. Normally EX advances
    // the cycle after a successful dispatch, which guarantees this by
    // construction; mem_stall can now hold EX for an extra cycle for reasons
    // unrelated to VPU readiness, so "already dispatched" must be latched
    // explicitly — otherwise vproc_system_wrapper's push_valid/vls_fire would
    // fire a second time for the same instruction while EX is held.
    assign vpu_insn_vld_o = is_vector_exe && !vpu_disp_done_r;
    assign vpu_insn_o     = inst_exe;
    assign vpu_rs1_data_o = rs1_data;
    assign vpu_rs2_data_o = rs2_data;

    // MEM: IO region detection
    assign is_io_mem = (alu_result_m[31:16] == IO_BASE0) ||
                       (alu_result_m[31:16] == IO_BASE1 && alu_result_m[15:0] == 16'h0000);

    // MEM: combinatorial IO read data
    always_comb begin
        io_rdata_mem = 32'b0;
        if (alu_result_m[31:16] == IO_BASE0) begin
            case (alu_result_m[15:12])
                4'h0: io_rdata_mem = ledr_r;
                4'h1: io_rdata_mem = ledg_r;
                4'h2: io_rdata_mem = hexl_r;
                4'h3: io_rdata_mem = hexh_r;
                4'h4: io_rdata_mem = lcd_r;
                default: io_rdata_mem = 32'b0;
            endcase
        end else if (alu_result_m[31:16] == IO_BASE1) begin
            io_rdata_mem = sw_r;
        end
    end

    // MEM: external DMEM port control
    always_comb begin
        s_dmem_addr_o  = alu_result_m;
        s_dmem_we_o    = 1'b0;
        s_dmem_be_o    = 4'b0;
        s_dmem_wdata_o = 32'b0;
        s_dmem_re_o    = 1'b0;
        if (!is_io_mem) begin
            s_dmem_re_o = is_load_mem;
            if (mem_wren_mem) begin
                s_dmem_we_o = 1'b1;
                case (func3_m)
                    3'b000: begin  // SB: replicate byte, select lane via be
                        s_dmem_wdata_o = {4{rs2_data_m[7:0]}};
                        case (alu_result_m[1:0])
                            2'b00: s_dmem_be_o = 4'b0001;
                            2'b01: s_dmem_be_o = 4'b0010;
                            2'b10: s_dmem_be_o = 4'b0100;
                            2'b11: s_dmem_be_o = 4'b1000;
                        endcase
                    end
                    3'b001: begin  // SH
                        s_dmem_wdata_o = {2{rs2_data_m[15:0]}};
                        s_dmem_be_o = alu_result_m[1] ? 4'b1100 : 4'b0011;
                    end
                    3'b010: begin  // SW
                        s_dmem_wdata_o = rs2_data_m;
                        s_dmem_be_o    = 4'b1111;
                    end
                    default: begin end
                endcase
            end
        end
    end

    // WB: select IO data or DMEM data (sync DMEM result already registered by dmem_sync)
    assign raw_load_data = is_io_wb ? io_rdata_wb : s_dmem_rdata_i;

    // WB: load sign/zero extension
    always_comb begin
        load_formatted = 32'b0;
        case (func3_wb)
            3'b000: begin  // LB
                case (addr_lo_wb)
                    2'b00: load_formatted = {{24{raw_load_data[ 7]}}, raw_load_data[ 7: 0]};
                    2'b01: load_formatted = {{24{raw_load_data[15]}}, raw_load_data[15: 8]};
                    2'b10: load_formatted = {{24{raw_load_data[23]}}, raw_load_data[23:16]};
                    2'b11: load_formatted = {{24{raw_load_data[31]}}, raw_load_data[31:24]};
                endcase
            end
            3'b001: begin  // LH
                load_formatted = addr_lo_wb[1] ?
                    {{16{raw_load_data[31]}}, raw_load_data[31:16]} :
                    {{16{raw_load_data[15]}}, raw_load_data[15: 0]};
            end
            3'b010: load_formatted = raw_load_data;  // LW
            3'b100: begin  // LBU
                case (addr_lo_wb)
                    2'b00: load_formatted = {24'b0, raw_load_data[ 7: 0]};
                    2'b01: load_formatted = {24'b0, raw_load_data[15: 8]};
                    2'b10: load_formatted = {24'b0, raw_load_data[23:16]};
                    2'b11: load_formatted = {24'b0, raw_load_data[31:24]};
                endcase
            end
            3'b101: begin  // LHU
                load_formatted = addr_lo_wb[1] ?
                    {16'b0, raw_load_data[31:16]} :
                    {16'b0, raw_load_data[15: 0]};
            end
            default: load_formatted = 32'b0;
        endcase
    end

    // WB mux
    always_comb begin
        case (wb_sel_wb)
            2'b00:   wb_data = load_formatted;
            2'b01:   wb_data = alu_result_wb;
            2'b10:   wb_data = pc_four_wb;
            2'b11:   wb_data = imm_wb;
            default: wb_data = 32'b0;
        endcase
    end

    // RF write: VPU cfg writeback overrides normal WB path
    always_comb begin
        if (vpu_cfg_done_i && vpu_cfg_pending_r && vpu_cfg_rd_r != 5'b0) begin
            rf_wren  = 1'b1;
            rf_waddr = vpu_cfg_rd_r;
            rf_wdata = vpu_vl_remain_i;
        end else begin
            rf_wren  = rd_wren_wb;
            rf_waddr = rd_addr_wb;
            rf_wdata = wb_data;
        end
    end

    // IO output assignments
    assign o_io_ledr = ledr_r;
    assign o_io_ledg = ledg_r;
    assign o_io_hex0 = hexl_r[ 6: 0];
    assign o_io_hex1 = hexl_r[14: 8];
    assign o_io_hex2 = hexl_r[22:16];
    assign o_io_hex3 = hexl_r[30:24];
    assign o_io_hex4 = hexh_r[ 6: 0];
    assign o_io_hex5 = hexh_r[14: 8];
    assign o_io_hex6 = hexh_r[22:16];
    assign o_io_hex7 = hexh_r[30:24];
    assign o_io_lcd  = lcd_r;
    assign o_insn_vld = insn_vld_wb;
    assign o_illegal_instr = illegal_instr_d;

    //==================================================================
    // INSTANTIATED MODULES
    //==================================================================

    // Sync IMEM: registered output goes directly to decode stage
    imem_sync #(.DEPTH(2048)) u_imem (
        .clk  (i_clk),
        .reset(i_reset),
        .flush(flush),
        .stall(stall),
        .pc   (pc),
        .instr(inst_decode)
    );

    // Control unit — full funct7[6:0] (needed to detect RV32M funct7=0000001)
    control_unit u_control (
        .instr    ({inst_decode[31:25], inst_decode[14:12], inst_decode[6:0]}),
        .br_ctrl  (br_ctrl),
        .j_taken  (j_taken),
        .Immsel   (ImmSel),
        .alu_op   (alu_op),
        .wb_sel   (wb_sel),
        .br_un    (br_un),
        .opa_sel  (opa_sel),
        .opb_sel  (opb_sel),
        .mem_wren (mem_wren),
        .rd_wren  (rd_wren),
        .insn_vld (insn_vld_d),
        .func7    (func7_d),
        .is_load  (is_load),
        .is_vector(is_vector),
        .illegal_instr(illegal_instr_d)
    );

    immgen u_immgen (
        .instr  (inst_decode[31:7]),
        .Immsel (ImmSel),
        .imm    (imm)
    );

    register_file #(
        .DATA_W(32),
        .ADDR_W(5)
    ) u_regfile (
        .i_clk     (i_clk),
        .i_rst     (~i_reset),  // register_file/d_ff uses active-LOW rst_n
        .i_rs1_addr(rs1_addr),
        .i_rs2_addr(rs2_addr),
        .i_rd_addr (rf_waddr),
        .i_rd_data (rf_wdata),
        .i_rd_wren (rf_wren),
        .o_rs1_data(rs1_raw),
        .o_rs2_data(rs2_raw)
    );

    // WB->ID bypass muxes (select forwarded wb_data when write-read conflict)
    mux2to1 bypass1 (
        .in0(rs1_raw),
        .in1(rf_wdata),
        .sel(rf1_fwd),
        .out(rs1_data_d)
    );
    mux2to1 bypass2 (
        .in0(rs2_raw),
        .in1(rf_wdata),
        .sel(rf2_fwd),
        .out(rs2_data_d)
    );

    // EX forwarding muxes (00=RF, 01=MEM, 10=WB)
    mux4to1 ex1_fwd (
        .in0(rs1_data_exe),
        .in1(mem_fwd_value),
        .in2(rf_wdata),
        .in3(32'b0),
        .sel(fwd_a),
        .out(rs1_data)
    );
    mux4to1 ex2_fwd (
        .in0(rs2_data_exe),
        .in1(mem_fwd_value),
        .in2(rf_wdata),
        .in3(32'b0),
        .sel(fwd_b),
        .out(rs2_data)
    );

    brc u_brc (
        .i_rs1_data(rs1_data),
        .i_rs2_data(rs2_data),
        .i_br_un   (br_un_exe),
        .func3     (func3_exe),
        .o_br_taken(br_taken)
    );

    mux2to1 opa_mux (
        .in0(rs1_data),
        .in1(pce),
        .sel(opa_sel_exe),
        .out(operand_a)
    );
    mux2to1 opb_mux (
        .in0(rs2_data),
        .in1(imm_exe),
        .sel(opb_sel_exe),
        .out(operand_b)
    );

    alu u_alu (
        .i_operand_a(operand_a),
        .i_operand_b(operand_b),
        .i_alu_op   (alu_op_exe),
        .func7      (func7_exe),
        .o_alu_data (alu_result)
    );

    //==================================================================
    // SEQUENTIAL LOGIC — PIPELINE REGISTERS
    //==================================================================

    //------------------------------------------------------------------
    // PC Register — hold on any stall
    //------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_reset)     pc <= 32'b0;
        else if (!stall) pc <= pc_next;
    end

    //------------------------------------------------------------------
    // IF/ID Registers — inst_decode handled by imem_sync above
    //------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_reset || flush)  pcd <= 32'b0;
        else if (!stall)       pcd <= pc;
    end
    always_ff @(posedge i_clk) begin
        if (i_reset || flush)  pc_four_d <= 32'b0;
        else if (!stall)       pc_four_d <= pc_four;
    end

    //------------------------------------------------------------------
    // ID/EX Registers
    //   enable = !ex_hold (holds while retrying a denied DMEM access too)
    //   hazard (flush|stall_ld) → inject bubble
    //------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_reset) begin
            rs1_data_exe  <= 32'b0; rs2_data_exe  <= 32'b0;
            imm_exe       <= 32'b0; pce           <= 32'b0;
            pc_four_exe   <= 32'b0; inst_exe      <= NOP;
            rs1_addr_exe  <= 5'b0;  rs2_addr_exe  <= 5'b0;
            rd_addr_exe   <= 5'b0;  func3_exe     <= 3'b0;
            br_ctrl_exe   <= 1'b0;  j_ctrl_exe    <= 1'b0;
            br_un_exe     <= 1'b0;  opa_sel_exe   <= 1'b0;
            opb_sel_exe   <= 1'b0;  alu_op_exe    <= 4'b0;
            mem_wren_exe  <= 1'b0;  rd_wren_exe   <= 1'b0;
            wb_sel_exe    <= 2'b0;  insn_vld_exe  <= 1'b0;
            func7_exe     <= 1'b0;  is_load_exe   <= 1'b0;
            is_vector_exe <= 1'b0;
        end else if (!ex_hold) begin
            if (hazard) begin
                // Bubble: zero all control signals, keep PCs for debug
                rs1_data_exe  <= 32'b0; rs2_data_exe  <= 32'b0;
                imm_exe       <= 32'b0; pce           <= pcd;
                pc_four_exe   <= pc_four_d; inst_exe  <= NOP;
                rs1_addr_exe  <= 5'b0;  rs2_addr_exe  <= 5'b0;
                rd_addr_exe   <= 5'b0;  func3_exe     <= 3'b0;
                br_ctrl_exe   <= 1'b0;  j_ctrl_exe    <= 1'b0;
                br_un_exe     <= 1'b0;  opa_sel_exe   <= 1'b0;
                opb_sel_exe   <= 1'b0;  alu_op_exe    <= 4'b0;
                mem_wren_exe  <= 1'b0;  rd_wren_exe   <= 1'b0;
                wb_sel_exe    <= 2'b0;  insn_vld_exe  <= 1'b0;
                func7_exe     <= 1'b0;  is_load_exe   <= 1'b0;
                is_vector_exe <= 1'b0;
            end else begin
                rs1_data_exe  <= rs1_data_d; rs2_data_exe  <= rs2_data_d;
                imm_exe       <= imm;        pce           <= pcd;
                pc_four_exe   <= pc_four_d;  inst_exe      <= inst_decode;
                rs1_addr_exe  <= rs1_addr;   rs2_addr_exe  <= rs2_addr;
                rd_addr_exe   <= rd_addr;    func3_exe     <= func3;
                br_ctrl_exe   <= br_ctrl;    j_ctrl_exe    <= j_taken;
                br_un_exe     <= br_un;      opa_sel_exe   <= opa_sel;
                opb_sel_exe   <= opb_sel;    alu_op_exe    <= alu_op;
                mem_wren_exe  <= mem_wren;   rd_wren_exe   <= rd_wren;
                wb_sel_exe    <= wb_sel;     insn_vld_exe  <= insn_vld_d;
                func7_exe     <= func7_d;    is_load_exe   <= is_load;
                is_vector_exe <= is_vector;
            end
        end
        // ex_hold && !i_reset: hold all ID/EX values (implicit)
    end

    //------------------------------------------------------------------
    // Vector dispatch one-shot — see vpu_insn_vld_o comment above.
    // Set when a dispatch succeeds while EX is held; cleared once EX is
    // free to advance again. Purely a function of registered state, so
    // there is no combinational loop through the arbiter's mem_stall.
    //------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_reset)                            vpu_disp_done_r <= 1'b0;
        else if (!ex_hold)                      vpu_disp_done_r <= 1'b0;
        else if (vpu_insn_vld_o && vpu_ready_i) vpu_disp_done_r <= 1'b1;
    end

    //------------------------------------------------------------------
    // EX/MEM Registers — enable = !ex_hold (holds while retrying a denied
    // DMEM access, not just while the VPU isn't ready)
    //------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_reset) begin
            alu_result_m <= 32'b0; rs2_data_m   <= 32'b0;
            imm_m        <= 32'b0; pc_four_m    <= 32'b0;
            pcm          <= 32'b0; func3_m      <= 3'b0;
            rd_addr_mem  <= 5'b0;  mem_wren_mem <= 1'b0;
            rd_wren_mem  <= 1'b0;  wb_sel_mem   <= 2'b0;
            insn_vld_mem <= 1'b0;  is_load_mem  <= 1'b0;
        end else if (!ex_hold) begin
            alu_result_m <= alu_result;    rs2_data_m   <= rs2_data;
            imm_m        <= imm_exe;       pc_four_m    <= pc_four_exe;
            pcm          <= pce;           func3_m      <= func3_exe;
            rd_addr_mem  <= rd_addr_exe;   mem_wren_mem <= mem_wren_exe;
            rd_wren_mem  <= rd_wren_exe;   wb_sel_mem   <= wb_sel_exe;
            insn_vld_mem <= insn_vld_exe;  is_load_mem  <= is_load_exe;
        end
    end

    //------------------------------------------------------------------
    // MEM/WB Registers — enable = !vpu_stall (unchanged). On mem_stall
    // alone, inject a bubble instead of holding: the MEM-stage instruction
    // stays in EX/MEM (frozen by ex_hold above) retrying its DMEM access,
    // so nothing valid is available to advance into WB this cycle. Holding
    // MEM/WB instead would re-present last cycle's already-completed
    // instruction, which the WB stage would (harmlessly, since it's an
    // idempotent same-value rewrite) commit again — bubbling is the
    // correct/clean behavior, not just the safe one.
    // addr_lo captured here for WB load formatting (sync DMEM result
    // arrives one cycle after MEM issues the read, i.e., in WB cycle)
    //------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_reset) begin
            alu_result_wb <= 32'b0; imm_wb      <= 32'b0;
            pc_four_wb    <= 32'b0; func3_wb    <= 3'b0;
            addr_lo_wb    <= 2'b0;  rd_addr_wb  <= 5'b0;
            rd_wren_wb    <= 1'b0;  wb_sel_wb   <= 2'b0;
            insn_vld_wb   <= 1'b0;  is_io_wb    <= 1'b0;
            io_rdata_wb   <= 32'b0;
        end else if (!vpu_stall) begin
            if (mem_stall) begin
                alu_result_wb <= 32'b0; imm_wb      <= 32'b0;
                pc_four_wb    <= 32'b0; func3_wb    <= 3'b0;
                addr_lo_wb    <= 2'b0;  rd_addr_wb  <= 5'b0;
                rd_wren_wb    <= 1'b0;  wb_sel_wb   <= 2'b0;
                insn_vld_wb   <= 1'b0;  is_io_wb    <= 1'b0;
                io_rdata_wb   <= 32'b0;
            end else begin
                alu_result_wb <= alu_result_m;      imm_wb       <= imm_m;
                pc_four_wb    <= pc_four_m;         func3_wb     <= func3_m;
                addr_lo_wb    <= alu_result_m[1:0]; rd_addr_wb   <= rd_addr_mem;
                rd_wren_wb    <= rd_wren_mem;       wb_sel_wb    <= wb_sel_mem;
                insn_vld_wb   <= insn_vld_mem;      is_io_wb     <= is_io_mem;
                io_rdata_wb   <= io_rdata_mem;
            end
        end
    end

    //------------------------------------------------------------------
    // IO Registers — synchronous active-high reset
    //------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_reset) begin
            ledr_r <= 32'b0; ledg_r <= 32'b0;
            hexl_r <= 32'b0; hexh_r <= 32'b0;
            lcd_r  <= 32'b0; sw_r   <= 32'b0;
        end else begin
            sw_r <= i_io_sw;
            if (mem_wren_mem && is_io_mem && alu_result_m[31:16] == IO_BASE0) begin
                case (alu_result_m[15:12])
                    4'h0: begin  // LEDR
                        case (func3_m)
                            3'b000: case (alu_result_m[1:0])
                                2'b00: ledr_r[ 7: 0] <= rs2_data_m[7:0];
                                2'b01: ledr_r[15: 8] <= rs2_data_m[7:0];
                                2'b10: ledr_r[23:16] <= rs2_data_m[7:0];
                                2'b11: ledr_r[31:24] <= rs2_data_m[7:0];
                            endcase
                            3'b001: if (alu_result_m[1]) ledr_r[31:16] <= rs2_data_m[15:0];
                                    else                 ledr_r[15: 0] <= rs2_data_m[15:0];
                            3'b010: ledr_r <= rs2_data_m;
                            default: begin end
                        endcase
                    end
                    4'h1: begin  // LEDG
                        case (func3_m)
                            3'b000: case (alu_result_m[1:0])
                                2'b00: ledg_r[ 7: 0] <= rs2_data_m[7:0];
                                2'b01: ledg_r[15: 8] <= rs2_data_m[7:0];
                                2'b10: ledg_r[23:16] <= rs2_data_m[7:0];
                                2'b11: ledg_r[31:24] <= rs2_data_m[7:0];
                            endcase
                            3'b001: if (alu_result_m[1]) ledg_r[31:16] <= rs2_data_m[15:0];
                                    else                 ledg_r[15: 0] <= rs2_data_m[15:0];
                            3'b010: ledg_r <= rs2_data_m;
                            default: begin end
                        endcase
                    end
                    4'h2: begin  // HEXL
                        case (func3_m)
                            3'b000: case (alu_result_m[1:0])
                                2'b00: hexl_r[ 7: 0] <= rs2_data_m[7:0];
                                2'b01: hexl_r[15: 8] <= rs2_data_m[7:0];
                                2'b10: hexl_r[23:16] <= rs2_data_m[7:0];
                                2'b11: hexl_r[31:24] <= rs2_data_m[7:0];
                            endcase
                            3'b001: if (alu_result_m[1]) hexl_r[31:16] <= rs2_data_m[15:0];
                                    else                 hexl_r[15: 0] <= rs2_data_m[15:0];
                            3'b010: hexl_r <= rs2_data_m;
                            default: begin end
                        endcase
                    end
                    4'h3: begin  // HEXH
                        case (func3_m)
                            3'b000: case (alu_result_m[1:0])
                                2'b00: hexh_r[ 7: 0] <= rs2_data_m[7:0];
                                2'b01: hexh_r[15: 8] <= rs2_data_m[7:0];
                                2'b10: hexh_r[23:16] <= rs2_data_m[7:0];
                                2'b11: hexh_r[31:24] <= rs2_data_m[7:0];
                            endcase
                            3'b001: if (alu_result_m[1]) hexh_r[31:16] <= rs2_data_m[15:0];
                                    else                 hexh_r[15: 0] <= rs2_data_m[15:0];
                            3'b010: hexh_r <= rs2_data_m;
                            default: begin end
                        endcase
                    end
                    4'h4: begin  // LCD
                        if (func3_m == 3'b010) lcd_r <= rs2_data_m;
                    end
                    default: begin end
                endcase
            end
        end
    end

    //------------------------------------------------------------------
    // VPU Config Pending — latch rd_addr at dispatch of vsetvl*
    //------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_reset) begin
            vpu_cfg_pending_r <= 1'b0;
            vpu_cfg_rd_r      <= 5'b0;
        end else if (is_cfg_exe && vpu_ready_i && !vpu_disp_done_r) begin
            vpu_cfg_rd_r      <= rd_addr_exe;
            vpu_cfg_pending_r <= 1'b1;
        end else if (vpu_cfg_done_i) begin
            vpu_cfg_pending_r <= 1'b0;
        end
    end

    //------------------------------------------------------------------
    // PC Debug Output (MEM-stage PC, one cycle delayed)
    //------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_reset) o_pc_debug <= 32'b0;
        else         o_pc_debug <= pcm;
    end

endmodule
