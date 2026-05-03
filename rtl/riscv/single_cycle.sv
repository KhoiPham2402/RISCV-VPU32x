//----------------------------------------------------------------------//
//  Design Note
//----------------------------------------------------------------------//
//  1. Instruction Memory Depth (IMEM): At least 8 kB to run the "isa_1b.hex" or "isa_4b.hex"
//  2. Data        Memory Depth (DMEM): At least 2 kB (0x0000_0000 - 0x0000_07FF)
//  3. IMEM and DMEM are separate memory blocks (Harvard-like structure).


module single_cycle (
    input  logic         i_clk     ,
    input  logic         i_reset   ,
    input  logic [31:0]  i_io_sw   ,
    output logic [31:0]  o_io_ledr ,
    output logic [31:0]  o_io_ledg ,   
    output logic [31:0]  o_io_lcd  ,
    output logic [ 6:0]  o_io_hex0 ,
    output logic [ 6:0]  o_io_hex1 ,
    output logic [ 6:0]  o_io_hex2 ,
    output logic [ 6:0]  o_io_hex3 ,
    output logic [ 6:0]  o_io_hex4 ,
    output logic [ 6:0]  o_io_hex5 ,
    output logic [ 6:0]  o_io_hex6 ,
    output logic [ 6:0]  o_io_hex7 ,
    output logic [31:0]  o_pc_debug,
    output logic         o_insn_vld,

    // VPU interface
    input  logic         i_vpu_ready,
    input  logic         i_vpu_cfg_done,
    input  logic [31:0]  i_vpu_vl_remain,
    output logic         o_vpu_insn_vld,
    output logic [31:0]  o_vpu_insn,
    output logic [31:0]  o_vpu_rs1_data,
    output logic [31:0]  o_vpu_rs2_data,

    // CSRR*: địa chỉ CSR = inst[31:20], dữ liệu đọc từ khối VCSR (qua top)
    output wire  [11:0]  o_csr_addr,
    input  logic [31:0]  i_csr_rdata,

    // ── VLSU shared DMEM port (threaded from lsu.sv secondary port) ──────
    input  logic         i_vlsu_mem_req,
    input  logic         i_vlsu_mem_we,
    input  logic [31:0]  i_vlsu_mem_addr,
    input  logic [ 3:0]  i_vlsu_mem_be,
    input  logic [31:0]  i_vlsu_mem_wdata,
    output logic [31:0]  o_vlsu_mem_rdata
);


	logic [31:0] inst;     // instruction từ imem
	logic [31:0] pc;
	logic [31:0] pc_four;
	logic [31:0] pc_next;
	logic [31:0] alu_data;
	logic        br_equal;     // branch equal  (rs1 == rs2)
	logic        br_less;     // branch less    (rs1 <  rs2)  – đã có
	logic [31:0] mem_data;
	logic [31:0] imm;

	logic        pc_sel;        // chọn next-pc
	logic			 func7;
	logic [2:0]  ImmSel;       // chọn immediate format
	logic        br_un;         // so sánh signed hay unsigned
	logic [1:0]	opa_sel;         // chọn opA (rs1 hay PC)
	logic        opb_sel;         // chọn opB (rs2 hay imm)
	logic [3:0]  alu_op;       // chọn phép tính ALU
	logic        mem_wren;        // read/write memory
	logic        rd_wren;       // enable ghi vào register file
	logic [1:0]  wb_sel;        // chọn dữ liệu write-back
	logic        insn_vld;     // instruction hợp lệ
	logic        csr_rd_wb;    // control: write-back từ cổng đọc CSR
	logic [31:0] wb_data_mux;
	logic	[31:0] wb_data;
	logic	[31:0] rs1;
	logic	[31:0] rs2;
	logic	[31:0] operand_a;
	logic	[31:0] operand_b;
	logic        vpu_insn_vld;
	logic        is_vpu_config;
	logic        vpu_stall;

	// Config pending: set on first cycle of vsetvli, clear when VPU cfg_done
	logic        vpu_cfg_pending_r;
	wire         vpu_cfg_start = vpu_insn_vld & is_vpu_config & ~vpu_cfg_pending_r;

	always @(posedge i_clk or negedge i_reset) begin
		if (!i_reset)
			vpu_cfg_pending_r <= 1'b0;
		else if (i_vpu_cfg_done)
			vpu_cfg_pending_r <= 1'b0;
		else if (vpu_cfg_start)
			vpu_cfg_pending_r <= 1'b1;
	end

	wire vpu_cfg_stall = vpu_cfg_start | (vpu_cfg_pending_r & ~i_vpu_cfg_done);
	assign vpu_stall   = (vpu_insn_vld & ~i_vpu_ready) | vpu_cfg_stall;

	// Writeback override: when cfg_done, write vl_remain to rd
	wire        rd_wren_eff  = i_vpu_cfg_done | rd_wren;
	wire [31:0] wb_data_eff  = i_vpu_cfg_done ? i_vpu_vl_remain : wb_data;

	assign o_csr_addr = inst[31:20];
	assign wb_data    = csr_rd_wb ? i_csr_rdata : wb_data_mux;

	control_unit u_control_unit (
					.instr({inst[30],inst[14:12],inst[6:2]}),
					.rd_addr(inst[11:7]),
					.br_less(br_less),
					.br_equal(br_equal),
					.pc_sel(pc_sel),
					.Immsel(ImmSel),
					.alu_op(alu_op),
					.wb_sel(wb_sel),
					.br_un(br_un),
					.opa_sel(opa_sel),
					.opb_sel(opb_sel),
					.mem_wren(mem_wren),
					.rd_wren(rd_wren),
					.csr_rd_wb(csr_rd_wb),
					.insn_vld(insn_vld),
					.func7(func7),
					.vpu_insn_vld(vpu_insn_vld),
					.is_vpu_config(is_vpu_config)
					);
										
	adder	PC4	(	.i_operand_a(pc),
						.i_operand_b(32'd4),
						.cin(1'b0),
						.o_sum_data(pc_four));
										
	mux2to1  MUXPC	(	.in0(pc_four),
							.in1(alu_data),
							.sel(pc_sel),
							.out(pc_next));
										
	register	PC	(	.D(pc_next),
						.clk(i_clk),
						.en(~vpu_stall),
						.rst_n(i_reset),
						.Q(pc));	
						
	imem	IMEM	(	.pc(pc),
						.instr(inst));
	
	register_file #(
		.DATA_W(32),
		.ADDR_W(5)
		) u_register_file (
		.i_clk(i_clk),
		.i_rst(i_reset),
		.i_rs1_addr(inst[19:15]),
		.i_rs2_addr(inst[24:20]),
		.i_rd_data(wb_data_eff),
		.i_rd_addr(inst[11:7]),
		.i_rd_wren(rd_wren_eff),
		.o_rs1_data(rs1),
		.o_rs2_data(rs2)
		);
		
	immgen u_immgen (
    .instr  (inst[31:7]),  
    .Immsel (ImmSel),   
    .imm    (imm)    
	);
	
	brc u_brc (
		.i_rs1_data (rs1),
		.i_rs2_data (rs2),
		.i_br_un (br_un),
		.o_br_less (br_less),
		.o_br_equal (br_equal)
		);
		
	mux4to1 MUXOP1 (	.in0(rs1),
							.in1(pc),
							.in2(32'd0),
							.sel(opa_sel),
							.out(operand_a)
						);
	
	mux2to1 MUXOP2 (	.in0(rs2),
							.in1(imm),
							.sel(opb_sel),
							.out(operand_b)
						);
	
	alu alu_u (
    .i_operand_a    (operand_a),
    .i_operand_b    (operand_b),
    .i_alu_op       (alu_op),
    .func7          (func7),
    .o_alu_data     (alu_data)
	 );
	 
	 //================ LSU ======================
	lsu lsu_u (
    // System global
    .i_clk        (i_clk),
    .i_reset      (i_reset),

    // Scalar Load/Store
    .i_lsu_addr   (alu_data),
    .i_st_data    (rs2),
    .i_lsu_wren   (mem_wren),
    .o_ld_data    (mem_data),
    .i_lsu_op     (inst[14:12]),

    // IO Output
    .o_io_ledr    (o_io_ledr),
    .o_io_ledg    (o_io_ledg),
    .o_io_hex0    (o_io_hex0),
    .o_io_hex1    (o_io_hex1),
    .o_io_hex2    (o_io_hex2),
    .o_io_hex3    (o_io_hex3),
    .o_io_hex4    (o_io_hex4),
    .o_io_hex5    (o_io_hex5),
    .o_io_hex6    (o_io_hex6),
    .o_io_hex7    (o_io_hex7),
    .o_io_lcd     (o_io_lcd),

    // IO Input
    .i_io_sw      (i_io_sw),

    // VLSU secondary DMEM port
    .i_ext_req    (i_vlsu_mem_req),
    .i_ext_we     (i_vlsu_mem_we),
    .i_ext_addr   (i_vlsu_mem_addr),
    .i_ext_be     (i_vlsu_mem_be),
    .i_ext_wdata  (i_vlsu_mem_wdata),
    .o_ext_rdata  (o_vlsu_mem_rdata)
	 );
	 
	mux4to1 u_mux4to1_32 (
    .in0   (mem_data),   // 32-bit
    .in1   (alu_data),   // 32-bit
    .in2   (pc_four),   // 32-bit
    .in3   (imm),   // 32-bit
    .sel   (wb_sel),   // 2-bit
    .out   (wb_data_mux)
);
	d_ff u_vld	(	.D(insn_vld),
						.clk(i_clk),
						.rst_n(i_reset),
						.en(1'b1),
						.Q(o_insn_vld));
	register DEBUG	(	.D(pc),
						.clk(i_clk),
						.rst_n(i_reset),
						.en(1'b1),
						.Q(o_pc_debug));

	// ===== VPU interface =====
	assign o_vpu_insn_vld  = vpu_insn_vld & ~vpu_cfg_pending_r;
	assign o_vpu_insn      = inst;
	assign o_vpu_rs1_data  = rs1;
	assign o_vpu_rs2_data  = rs2;
endmodule










