//----------------------------------------------------------------------//
//  Design Note
//----------------------------------------------------------------------//
//  1. Instruction Memory Depth (IMEM): At least 8 kB to run the "isa_1b.hex" or "isa_4b.hex"
//  2. Data        Memory Depth (DMEM): At least 2 kB (0x0000_0000 - 0x0000_07FF)
//  3. IMEM and DMEM are separate memory blocks (Harvard-like structure).

module non_forwarding (
    input  logic         i_clk,
    input  logic         i_reset,          // active-high
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
    output logic         o_ctrl,
    output logic         o_mispred
);

    //==================================================================
    //  Internal Signals
    //==================================================================
    //  Fetch signals
    logic [31:0] pc;
    logic [31:0] pc_four;
    logic [31:0] pc_next;
    logic [31:0] inst;
    logic [31:0] inst_fetch;
    logic [31:0] pc_fetch;
    logic [31:0] pc_four_fetch;

    //  Decode Signals
    logic [31:0] pc_four_d;
    logic [31:0] inst_decode;
    logic [31:0] rs1;
    logic [31:0] rs2;
    logic [31:0] rs1_data_d;
    logic [31:0] rs2_data_d;
    logic [31:0] imm;
    logic [31:0] pcd;
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [2:0]  func3;
    logic        br_taken;
    
    //  Execution Signals
    logic [31:0] pc_four_exe;
    logic [31:0] rs1_data_exe;
    logic [31:0] rs2_data_exe;
    logic [31:0] imm_exe;
    logic [31:0] pce;
    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic [31:0] alu_result;
    logic [2:0]  func3_exe;
    logic [4:0]  rs1_addr_exe;
    logic [4:0]  rs2_addr_exe;

    //  Mem signals
    logic [31:0] pc_four_m;
    logic [31:0] alu_result_m;
    logic [31:0] imm_m;
    logic [31:0] mem_data;      // data read from LSU
    logic [31:0] rs2_data_m;
    logic [31:0] pcm;
    logic [2:0]  func3_m;
    //  Writeback Signals
    logic [31:0] pc_four_wb;
    logic [31:0] alu_result_wb;
    logic [31:0] imm_wb;
    logic [31:0] mem_data_wb;
    logic [31:0] wb_data;       // data write back to regfile


    // Control signals ID/IE
    logic [4:0]  rd_addr;
    logic        br_ctrl;
    logic        j_taken;
    logic [2:0]  ImmSel;
    logic        br_un;
    logic        opa_sel;
    logic        opb_sel;
    logic [3:0]  alu_op;    
    logic        mem_wren;
    logic        rd_wren;
    logic [1:0]  wb_sel;
    logic        o_insn_vld_d;
    logic        func7;
    logic        is_jmp;

    // Tín hiệu sau khi insert bubble (khi stall thì clear hết)
    logic [31:0] rs1_data_exe_in;
    logic [31:0] rs2_data_exe_in;
    logic        br_ctrl_in;
    logic        j_ctrl_in;
    logic        func7_in;
    logic [1:0]  opa_sel_in;
    logic        opb_sel_in;
    logic        mem_wren_in;
    logic        rd_wren_in;
    logic [3:0]  alu_op_in;
    logic [1:0]  wb_sel_in;

    // Control signals IE/IM
    logic        pc_sel;
    logic        br_ctrl_exe;
    logic        j_ctrl_exe;
    logic        br_un_exe;
    logic        opa_sel_exe;
    logic        opb_sel_exe;
    logic [3:0]  alu_op_exe;
    logic        mem_wren_exe;
    logic        rd_wren_exe;
    logic [1:0]  wb_sel_exe;
    logic        o_insn_vld_exe;
    logic        func7_exe;
    logic [4:0]  rd_addr_exe;
    logic        is_jmp_exe;
    // Control signals IM/IWB
    logic        mem_wren_mem;
    logic        rd_wren_mem;
    logic [1:0]  wb_sel_mem;
    logic        o_insn_vld_mem;
    logic [4:0]  rd_addr_mem;
    logic        pc_sel_m;
    logic        is_jmp_mem;
    // Control signals IM/IWB
    logic        rd_wren_wb;
    logic [1:0]  wb_sel_wb;
    logic [4:0]  rd_addr_wb;

     // Hazard Signal
    logic        stall;
    logic        flush;
    logic        hazard;
    logic        rf1_fwd;
    logic        rf2_fwd;

    //Assign logic
	 
    assign rs1_addr = inst_decode[19:15];
    assign rs2_addr = inst_decode[24:20];
    assign rd_addr  = inst_decode[11:7];
    assign func3    = inst_decode[14:12];
    assign pc_sel   = j_ctrl_exe | (br_taken & br_ctrl_exe);

    assign inst_fetch   = flush ? 32'd0 : inst;
    assign pc_fetch     = flush ? 32'd0 : pc;
    assign pc_four_fetch   = flush ? 32'd0 : pc_four;

    assign rs1_data_exe_in  = hazard ? 32'd0 : rs1_data_d;
    assign rs2_data_exe_in  = hazard ? 32'd0 : rs2_data_d;
    assign br_ctrl_in       = hazard ? 1'b0  : br_ctrl;
    assign j_ctrl_in        = hazard ? 1'b0  : j_taken;
    assign func7_in         = hazard ? 1'b0  : func7;
    assign opa_sel_in       = hazard ? 1'b0  : opa_sel;
    assign opb_sel_in       = hazard ? 1'b0  : opb_sel;
    assign mem_wren_in      = hazard ? 1'b0  : mem_wren;
    assign rd_wren_in       = hazard ? 1'b0  : rd_wren;
    assign alu_op_in        = hazard ? 4'd0  : alu_op;
    assign wb_sel_in        = hazard ? 2'd0  : wb_sel;
    assign is_jmp           = j_ctrl_in | br_ctrl_in;
    //==================================================================
    //  Hazard Detection Unit 
    //==================================================================
    assign stall = (rd_wren_exe && (rd_addr_exe != 5'd0) &&
                   ((rs1_addr == rd_addr_exe) || (rs2_addr == rd_addr_exe))) || 
                   (rd_wren_mem && (rd_addr_mem != 5'd0) &&
                   ((rs1_addr == rd_addr_mem) || (rs2_addr == rd_addr_mem)));
    assign flush = pc_sel;
    assign hazard = flush | stall;
    assign rf1_fwd = (rd_wren_wb && (rd_addr_wb != 5'd0) && (rd_addr_wb == rs1_addr));
    assign rf2_fwd = (rd_wren_wb && (rd_addr_wb != 5'd0) && (rd_addr_wb == rs2_addr));
    //==================================================================
    //  IF Stage
    //==================================================================
    imem u_imem (
        .pc   (pc),
        .instr(inst)
    );

    adder pc_add4 (
        .i_operand_a (pc),
        .i_operand_b (32'd4),
        .cin         (1'b0),
        .o_sum_data  (pc_four)
    );

    mux2to1 pc_mux (
        .in0  (pc_four),
        .in1  (alu_result),
        .sel  (pc_sel),
        .out  (pc_next)
    );

    register pc_reg (
        .D     (pc_next),
        .clk   (i_clk),
        .en    (!stall),               // will be pc_write_en later
        .rst_n (i_reset),
        .Q     (pc)
    );

    register pip_instf (
        .D     (inst_fetch),
        .clk   (i_clk),
        .en    (!stall),               // will be pc_write_en later
        .rst_n (i_reset),
        .Q     (inst_decode)
    );
    register pip_pcf (
        .D     (pc_fetch),
        .clk   (i_clk),
        .en    (!stall),               // will be pc_write_en later
        .rst_n (i_reset),
        .Q     (pcd)
    );
    register pip_pc4f (
        .D     (pc_four_fetch),
        .clk   (i_clk),
        .en    (!stall),               // will be pc_write_en later
        .rst_n (i_reset),
        .Q     (pc_four_d)
    );
    //==================================================================
    //  ID Stage
    //==================================================================
    control_unit u_control (
        .instr      ({inst_decode[30], inst_decode[14:12], inst_decode[6:0]}),
        .br_ctrl    (br_ctrl),
        .j_taken    (j_taken),
        .Immsel     (ImmSel),
        .alu_op     (alu_op),
        .wb_sel     (wb_sel),
        .br_un      (br_un),
        .opa_sel    (opa_sel),
        .opb_sel    (opb_sel),
        .mem_wren   (mem_wren),
        .rd_wren    (rd_wren),
        .insn_vld   (o_insn_vld_d),
        .func7      (func7)
    );

    immgen u_immgen (
        .instr  (inst_decode[31:7]),
        .Immsel (ImmSel),
        .imm    (imm)
    );

    register_file #(
        .DATA_W(32),
        .ADDR_W(5)
    ) u_register_file (
        .i_clk       (i_clk),
        .i_rst       (i_reset),
        .i_rs1_addr   (rs1_addr),
        .i_rs2_addr   (rs2_addr),
        .i_rd_addr    (rd_addr_wb),
        .i_rd_data    (wb_data),
        .i_rd_wren    (rd_wren_wb),
        .o_rs1_data   (rs1),
        .o_rs2_data  (rs2)
    );
    mux2to1 bypass1_regfile (
        .in0    (rs1),
        .in1    (wb_data),
        .sel    (rf1_fwd),
        .out    (rs1_data_d)
    );
    mux2to1 bypass2_regfile (
        .in0    (rs2),
        .in1    (wb_data),
        .sel    (rf2_fwd),
        .out    (rs2_data_d)
    );
    register pip_rs1d (
        .D     (rs1_data_exe_in),
        .clk   (i_clk),
        .en    (1'b1),              
        .rst_n (i_reset),
        .Q     (rs1_data_exe)
    );
    register pip_rs2d (
        .D     (rs2_data_exe_in),
        .clk   (i_clk),
        .en    (1'b1),              
        .rst_n (i_reset),
        .Q     (rs2_data_exe)
    );
    register pip_immd (
        .D     (imm),
        .clk   (i_clk),
        .en    (1'b1),              
        .rst_n (i_reset),
        .Q     (imm_exe)
    );
    register pip_pc4d (
        .D     (pc_four_d),
        .clk   (i_clk),
        .en    (1'b1),              
        .rst_n (i_reset),
        .Q     (pc_four_exe)
    );
    register pip_pcd (
        .D     (pcd),
        .clk   (i_clk),
        .en    (!hazard),              
        .rst_n (i_reset),
        .Q     (pce)
    );
    d_ff pip_brtknd (
        .D      (br_ctrl_in),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (br_ctrl_exe)
    );
    d_ff pip_jtknd (
        .D      (j_ctrl_in),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (j_ctrl_exe)
    );
    d_ff pip_func7d (
        .D      (func7_in),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (func7_exe)
    );
    d_ff pip_brund (
        .D      (br_un),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (br_un_exe)
    );
    d_ff pip_opad (
        .D      (opa_sel_in),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (opa_sel_exe)
    );
    d_ff pip_opbd (
        .D      (opb_sel_in),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (opb_sel_exe)
    );
    d_ff ff_alu_op_0     (.D(alu_op_in[0]),    .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(alu_op_exe[0]));
    d_ff ff_alu_op_1     (.D(alu_op_in[1]),    .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(alu_op_exe[1]));
    d_ff ff_alu_op_2     (.D(alu_op_in[2]),    .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(alu_op_exe[2]));
    d_ff ff_alu_op_3     (.D(alu_op_in[3]),    .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(alu_op_exe[3]));
    d_ff pip_memwrend (
        .D      (mem_wren_in),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (mem_wren_exe)
    );
    d_ff pip_rdwrend (
        .D      (rd_wren_in),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (rd_wren_exe)
    );

    d_ff ff_wb_sel_0     (.D(wb_sel_in[0]),    .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(wb_sel_exe[0]));
    d_ff ff_wb_sel_1     (.D(wb_sel_in[1]),    .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(wb_sel_exe[1]));
    
    d_ff pip_instr_vldd (
        .D      (o_insn_vld_d),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (o_insn_vld_exe)
    );
    d_ff pipd_func3_0      (.D(func3[0]),        .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(func3_exe[0]));
    d_ff pipd_func3_1      (.D(func3[1]),        .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(func3_exe[1]));
    d_ff pipd_func3_2      (.D(func3[2]),        .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(func3_exe[2]));
        
    d_ff pipd_rd_0         (.D(rd_addr[0]),      .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(rd_addr_exe[0]));
    d_ff pipd_rd_1         (.D(rd_addr[1]),      .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(rd_addr_exe[1]));
    d_ff pipd_rd_2         (.D(rd_addr[2]),      .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(rd_addr_exe[2]));
    d_ff pipd_rd_3         (.D(rd_addr[3]),      .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(rd_addr_exe[3]));
    d_ff pipd_rd_4         (.D(rd_addr[4]),      .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(rd_addr_exe[4]));
    //==================================================================
    //  EX Stage
    //==================================================================
    brc u_brc (
        .i_rs1_data (rs1_data_exe),
        .i_rs2_data (rs2_data_exe),
        .i_br_un    (br_un_exe),
        .func3      (func3_exe),
        .o_br_taken (br_taken)
    );

    mux2to1 opa_mux (
        .in0   (rs1_data_exe),
        .in1   (pce),
        .sel   (opa_sel_exe),
        .out   (operand_a)
    );

    mux2to1 opb_mux (
        .in0   (rs2_data_exe),
        .in1   (imm_exe),
        .sel   (opb_sel_exe),
        .out   (operand_b)
    );

    alu u_alu (
        .i_operand_a   (operand_a),
        .i_operand_b   (operand_b),
        .i_alu_op      (alu_op_exe),
        .func7         (func7_exe),
        .o_alu_data    (alu_result)
    );
    register pip_pce (
        .D     (pce),
        .clk   (i_clk),
        .en    (1'b1),              
        .rst_n (i_reset),
        .Q     (pcm)
    );
    register pip_alur_exe (
        .D     (alu_result),
        .clk   (i_clk),
        .en    (1'b1),              
        .rst_n (i_reset),
        .Q     (alu_result_m)
    );
    register pip_imm_exe (
        .D     (imm_exe),
        .clk   (i_clk),
        .en    (1'b1),              
        .rst_n (i_reset),
        .Q     (imm_m)
    );
    register pip_rs2_exe (
        .D     (rs2_data_exe),
        .clk   (i_clk),
        .en    (1'b1),              
        .rst_n (i_reset),
        .Q     (rs2_data_m)
    );
    register pip_pc4_exe (
        .D     (pc_four_exe),
        .clk   (i_clk),
        .en    (1'b1),              
        .rst_n (i_reset),
        .Q     (pc_four_m)
    );
    d_ff pip_memwren_exe (
        .D      (mem_wren_exe),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (mem_wren_mem)
    );
    d_ff pip_rdwren_exe (
        .D      (rd_wren_exe),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (rd_wren_mem)
    );
    d_ff pipe_wb_sel_0          (.D(wb_sel_exe[0]), .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(wb_sel_mem[0]));
    d_ff pipe_wb_sel_1          (.D(wb_sel_exe[1]), .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(wb_sel_mem[1]));
    
    d_ff pip_instr_vld_exe (
        .D      (o_insn_vld_exe),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (o_insn_vld_mem)
    );
    d_ff pipe_func3_0           (.D(func3_exe[0]),  .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(func3_m[0]));
    d_ff pipe_func3_1           (.D(func3_exe[1]),  .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(func3_m[1]));
    d_ff pipe_func3_2           (.D(func3_exe[2]),  .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(func3_m[2]));
    
    d_ff pipe_rd_addr_0         (.D(rd_addr_exe[0]),.clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(rd_addr_mem[0]));
    d_ff pipe_rd_addr_1         (.D(rd_addr_exe[1]),.clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(rd_addr_mem[1]));
    d_ff pipe_rd_addr_2         (.D(rd_addr_exe[2]),.clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(rd_addr_mem[2]));
    d_ff pipe_rd_addr_3         (.D(rd_addr_exe[3]),.clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(rd_addr_mem[3]));
    d_ff pipe_rd_addr_4         (.D(rd_addr_exe[4]),.clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(rd_addr_mem[4]));

    //==================================================================
    //  MEM Stage - LSU
    //==================================================================
    lsu u_lsu (
        .i_clk       (i_clk),
        .i_reset     (i_reset),
        .i_lsu_addr  (alu_result_m),
        .i_st_data   (rs2_data_m),
        .i_lsu_wren  (mem_wren_mem),
        .i_lsu_op    (func3_m),
        .o_ld_data   (mem_data),
        .i_io_sw     (i_io_sw),
        .o_io_ledr   (o_io_ledr),
        .o_io_ledg   (o_io_ledg),
        .o_io_lcd    (o_io_lcd),
        .o_io_hex0   (o_io_hex0),
        .o_io_hex1   (o_io_hex1),
        .o_io_hex2   (o_io_hex2),
        .o_io_hex3   (o_io_hex3),
        .o_io_hex4   (o_io_hex4),
        .o_io_hex5   (o_io_hex5),
        .o_io_hex6   (o_io_hex6),
        .o_io_hex7   (o_io_hex7)
    );
    register pip_alur_mem (
        .D     (alu_result_m),
        .clk   (i_clk),
        .en    (1'b1),              
        .rst_n (i_reset),
        .Q     (alu_result_wb)
    );
    register pip_imm_mem (
        .D     (imm_m),
        .clk   (i_clk),
        .en    (1'b1),              
        .rst_n (i_reset),
        .Q     (imm_wb)
    );
    register pip_memd_mem (
        .D     (mem_data),
        .clk   (i_clk),
        .en    (1'b1),              
        .rst_n (i_reset),
        .Q     (mem_data_wb)
    );
    register pip_pc4_mem (
        .D     (pc_four_m),
        .clk   (i_clk),
        .en    (1'b1),              
        .rst_n (i_reset),
        .Q     (pc_four_wb)
    );
    d_ff pip_rdwren_mem (
        .D      (rd_wren_mem),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (rd_wren_wb)
    );
    d_ff pipm_wb_sel_0       (.D(wb_sel_mem[0]),  .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(wb_sel_wb[0]));
    d_ff pipm_wb_sel_1       (.D(wb_sel_mem[1]),  .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(wb_sel_wb[1]));
    
    d_ff pip_instr_vld_mem (
        .D      (o_insn_vld_mem),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (o_insn_vld)
    );
    d_ff pipm_rd_addr_0      (.D(rd_addr_mem[0]), .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(rd_addr_wb[0]));
    d_ff pipm_rd_addr_1      (.D(rd_addr_mem[1]), .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(rd_addr_wb[1]));
    d_ff pipm_rd_addr_2      (.D(rd_addr_mem[2]), .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(rd_addr_wb[2]));
    d_ff pipm_rd_addr_3      (.D(rd_addr_mem[3]), .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(rd_addr_wb[3]));
    d_ff pipm_rd_addr_4      (.D(rd_addr_mem[4]), .clk(i_clk), .en(1'b1), .rst_n(i_reset), .Q(rd_addr_wb[4]));
    //==================================================================
    //  WB Stage
    //==================================================================
    mux4to1 wb_mux (
        .in0   (mem_data_wb),     // load
        .in1   (alu_result_wb),   // alu
        .in2     (pc_four_wb),      // jal/jalr
        .in3   (imm_wb),          // lui, auipc
        .sel   (wb_sel_wb),
        .out   (wb_data)
    );

    //==================================================================
    //  Debug
    //==================================================================

    register u_pc_debug (
        .D     (pcm),
        .clk   (i_clk),
        .en    (1'b1),
        .rst_n (i_reset),
        .Q     (o_pc_debug)
    );
    d_ff pip_o_ctrl_mem (
        .D      (pc_sel),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (pc_sel_m)
    );
    d_ff pip_o_crtl (
        .D      (pc_sel_m),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (o_mispred)
    );
    d_ff pip_jmp_exe (
        .D      (is_jmp),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (is_jmp_exe)
    );
    d_ff pip_jmp_mem (
        .D      (is_jmp_exe),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (is_jmp_mem)
    );
    d_ff pip_jmp (
        .D      (is_jmp_mem),
        .clk    (i_clk),
        .en     (1'b1),
        .rst_n  (i_reset),
        .Q      (o_ctrl)
    );
endmodule