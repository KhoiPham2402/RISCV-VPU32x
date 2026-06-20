// Pipelined VPU system wrapper.
//
// One pipeline register is inserted between VRF read and the execution lane:
//
//   VRF (async read) ──► p1_reg (FF) ──► processor_lane ──► VRF (sync write)
//
// This cuts the critical path  VRF_read → MUL → VRF_write  in half,
// targeting ~2× Fmax improvement.
//
// Key timing rule:
//   Cycle T   : addr_gen outputs vs1_eff[T]; VRF reads rs1_data[T] combinationally;
//               p1_reg captures rs1_data[T] at posedge T+1.
//   Cycle T+1 : lane computes wb_lane[T] from p1_reg; VRF write commits at posedge T+2.
//
// ST_DRAIN (from vproc_fsm_p) provides the extra 1-cycle slot needed to write
// the last element after counter_done.
// ST_DRAIN_MASK similarly flushes the last mask result into the mask-write-buffer
// before ST_FINAL_MASKING commits it to VRF.
//
// Bypass paths (VLSU, final_masking, reduction) are unchanged and do not pass
// through the pipeline register.

module vproc_system_wrapper_p #(
    parameter NUM_REGS   = 32,
    parameter ADDR_WIDTH = 5,
    parameter CTRL_WIDTH = 49
) (
    input                   clk,
    input                   rst_n,

    input                   instr_valid,
    input  [31:0]           instruction,
    input  [31:0]           rs1_scalar_data,
    input  [31:0]           rs2_scalar_data,

    input                   vrf_commit_en,

    output [3:0]            cycles,
    output [15:0]           vmask16,
    output                  fifo_full,
    output                  busy,
    output [3:0]            fsm_state,
    output [31:0]           wb_result_lane0,
    output [31:0]           wb_result_lane1,
    output [31:0]           wb_result_lane2,
    output [31:0]           wb_result_lane3,

    output                  vpu_ready,
    output                  vpu_cfg_done,
    output [31:0]           vpu_vl_remain,

    output [31:0]           csr_vl_o,
    output [31:0]           csr_vtype_o,
    output [31:0]           csr_vlenb_o,

    input  [11:0]           scalar_csr_addr,
    output [31:0]           scalar_csr_rdata,

    output                  vlsu_mem_req,
    output                  vlsu_mem_we,
    output [31:0]           vlsu_mem_addr,
    output [ 3:0]           vlsu_mem_be,
    output [31:0]           vlsu_mem_wdata,
    input  [31:0]           vlsu_mem_rdata,
    input                   vlsu_mem_ready,

    output                  vlsu_busy_o
);

    // ===== Decoder → FIFO =====
    wire [CTRL_WIDTH-1:0] dec_ctrl_bus;
    wire                  dec_valid;
    wire [31:0]           dec_imm_out;

    wire [CTRL_WIDTH-1:0] fifo_ctrl_out;
    wire [31:0]           fifo_rs1_out;
    wire [31:0]           fifo_imm_out;
    wire                  fifo_data_valid;

    // ===== FSM signals =====
    wire fsm_latch_ctrl_en;
    wire fsm_csr_cfg_en;
    wire fsm_counter_start;
    wire fsm_vrf_wren;
    wire fsm_widen_sel;
    wire fsm_s_offset_en;
    wire fsm_d_offset_en;
    wire fsm_offset_reset;
    wire fsm_pop_ready;
    wire fsm_reduction_start;
    wire fsm_reduction_en;
    wire red_busy;

    // ===== Latched instruction context =====
    reg [CTRL_WIDTH-1:0] ctrl_r;
    reg [31:0]           rs1_latched_r;
    reg [31:0]           imm_latched_r;

    // ctrl_r field extraction
    wire [ADDR_WIDTH-1:0] vs1_addr_base_r = ctrl_r[4:0];
    wire [ADDR_WIDTH-1:0] vs2_addr_base_r = ctrl_r[9:5];
    wire [ADDR_WIDTH-1:0] vd_addr_base_r  = ctrl_r[14:10];
    wire [5:0]            funct6_r         = ctrl_r[20:15];
    wire                  is_widen_r       = ctrl_r[21];
    wire                  is_u_vs1_r       = ctrl_r[22];
    wire                  is_u_vs2_r       = ctrl_r[23];
    wire                  sub_r            = ctrl_r[24];
    wire                  use_imm_r        = ctrl_r[25];
    wire                  use_rs1_r        = ctrl_r[26];
    wire                  is_mulh_r        = ctrl_r[27];
    wire                  vm_r             = ctrl_r[31];
    wire [7:0]            vtype_enc_r      = ctrl_r[39:32];
    wire                  is_carry_r       = ctrl_r[40];
    wire                  is_mask_carry_r  = ctrl_r[41];
    wire                  is_masking_r     = ctrl_r[42];
    wire                  is_final_masking_r = ctrl_r[43];
    wire                  is_reverse_sub_r = ctrl_r[44];
    wire                  minmax_is_min_r  = ctrl_r[45];
    wire                  minmax_is_unsign_r = ctrl_r[46];
    wire                  is_reduction_r   = ctrl_r[47];

    // ===== CFG encoder outputs =====
    wire [31:0] cfg_vl;
    wire [31:0] cfg_vlmax;
    wire [2:0]  cfg_sew;
    wire        cfg_vill;
    wire [31:0] cfg_avl_remain;

    // ===== Cycle counter =====
    wire        counter_done;
    wire [3:0]  cycles_left_dbg;
    wire [7:0]  elems_curr_cycle_dbg;
    wire [15:0] cycle_mask16_dbg;
    wire [3:0]  mask_cycle_idx;

    // ===== VRF read data (combinational, direct from VRF) =====
    wire [31:0] rs1_data_lane0, rs2_data_lane0;
    wire [31:0] rs1_data_lane1, rs2_data_lane1;
    wire [31:0] rs1_data_lane2, rs2_data_lane2;
    wire [31:0] rs1_data_lane3, rs2_data_lane3;
    wire [31:0] mask_data_lane0, mask_data_lane1, mask_data_lane2, mask_data_lane3;
    wire [127:0] v0_mask_flat = {mask_data_lane3, mask_data_lane2,
                                  mask_data_lane1, mask_data_lane0};

    // ===== Lane outputs =====
    wire [31:0] wb_lane0, wb_lane1, wb_lane2, wb_lane3;
    wire [3:0]  lane_mask_result0, lane_mask_result1, lane_mask_result2, lane_mask_result3;

    // ===== Mask enable outputs =====
    wire [3:0]  lane_mask0, lane_mask1, lane_mask2, lane_mask3;
    wire [3:0]  lane_we0, lane_we1, lane_we2, lane_we3;
    wire [3:0]  lane0_v0_carry, lane1_v0_carry, lane2_v0_carry, lane3_v0_carry;

    wire [ADDR_WIDTH-1:0] vs1_addr_eff, vs2_addr_eff, vd_addr_eff;
    wire [31:0] imm_elem_vec;
    wire [31:0] rs1_elem_vec;
    wire        is_compare_r = (funct6_r[5:3] == 3'b011);
    wire [127:0] mask_buffer_data;
    wire [6:0]   mask_wr_ptr_dbg;

    // Bypass commit signals (unchanged from non-pipelined version)
    wire final_masking_commit = (fsm_state == 4'd6) && is_final_masking_r;
    wire reduction_commit     = (fsm_state == 4'd8) && is_reduction_r;

    wire [127:0] rs1_vec_flat = {rs1_data_lane3, rs1_data_lane2, rs1_data_lane1, rs1_data_lane0};
    wire [127:0] rs2_vec_flat = {rs2_data_lane3, rs2_data_lane2, rs2_data_lane1, rs2_data_lane0};
    wire [31:0]  reduction_result;
    wire         reduction_wb_valid;
    reg [3:0]    reduction_operation;
    localparam [3:0] RED_SUM  = 4'd0, RED_MAX  = 4'd1, RED_MAXU = 4'd2;
    localparam [3:0] RED_MIN  = 4'd3, RED_MINU = 4'd4, RED_AND  = 4'd5;
    localparam [3:0] RED_OR   = 4'd6, RED_XOR  = 4'd7;

    // =========================================================================
    // Pipeline register — VRF read → execution lane
    // =========================================================================
    // p1_en: capture during ALU/WIDEN/MASKING execution cycles.
    // During ST_DRAIN / ST_DRAIN_MASK: p1 holds last captured data (enable=0).
    localparam [3:0] PS_EXEC    = 4'd2;
    localparam [3:0] PS_WIDENL  = 4'd3;
    localparam [3:0] PS_WIDENH  = 4'd4;
    localparam [3:0] PS_MASKING = 4'd5;

    wire p1_en = (fsm_state == PS_EXEC)   || (fsm_state == PS_WIDENL) ||
                 (fsm_state == PS_WIDENH) || (fsm_state == PS_MASKING);

    reg [31:0] p1_rs1_lane0, p1_rs2_lane0;
    reg [31:0] p1_rs1_lane1, p1_rs2_lane1;
    reg [31:0] p1_rs1_lane2, p1_rs2_lane2;
    reg [31:0] p1_rs1_lane3, p1_rs2_lane3;
    reg [3:0]  p1_lane_mask0, p1_lane_mask1, p1_lane_mask2, p1_lane_mask3;
    reg [3:0]  p1_lane_we0,   p1_lane_we1,   p1_lane_we2,   p1_lane_we3;
    reg [3:0]  p1_v0_carry0,  p1_v0_carry1,  p1_v0_carry2,  p1_v0_carry3;
    reg [4:0]  p1_vd_addr;
    reg [15:0] p1_cycle_mask16;
    reg        p1_vrf_wren;     // delayed fsm_vrf_wren; gates ALU VRF write
    reg        p1_widen_sel;
    reg [7:0]  p1_elems_curr;
    reg        p1_mask_valid;   // delayed (fsm_s_offset_en && is_masking_r)

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p1_rs1_lane0   <= 32'd0; p1_rs2_lane0   <= 32'd0;
            p1_rs1_lane1   <= 32'd0; p1_rs2_lane1   <= 32'd0;
            p1_rs1_lane2   <= 32'd0; p1_rs2_lane2   <= 32'd0;
            p1_rs1_lane3   <= 32'd0; p1_rs2_lane3   <= 32'd0;
            p1_lane_mask0  <= 4'b0;  p1_lane_mask1  <= 4'b0;
            p1_lane_mask2  <= 4'b0;  p1_lane_mask3  <= 4'b0;
            p1_lane_we0    <= 4'b0;  p1_lane_we1    <= 4'b0;
            p1_lane_we2    <= 4'b0;  p1_lane_we3    <= 4'b0;
            p1_v0_carry0   <= 4'b0;  p1_v0_carry1   <= 4'b0;
            p1_v0_carry2   <= 4'b0;  p1_v0_carry3   <= 4'b0;
            p1_vd_addr     <= 5'd0;
            p1_cycle_mask16<= 16'd0;
            p1_vrf_wren    <= 1'b0;
            p1_widen_sel   <= 1'b0;
            p1_elems_curr  <= 8'd0;
            p1_mask_valid  <= 1'b0;
        end else begin
            // p1_mask_valid tracks whether the PREVIOUS cycle was a masking cycle
            // with a valid source advance — updated unconditionally every cycle.
            p1_mask_valid <= fsm_s_offset_en && is_masking_r;

            // Clear p1_vrf_wren at the end of ST_DRAIN so it cannot cause spurious
            // writes to the VRF in subsequent ST_IDLE cycles.  The combinational
            // vrf_we*_eff already uses p1_vrf_wren=1 during the DRAIN cycle itself
            // (evaluated before this posedge), so the final ALU write is unaffected.
            if (fsm_state == 4'd9) begin   // ST_DRAIN: safe to clear after drain commit
                p1_vrf_wren <= 1'b0;
            end else if (p1_en) begin
                p1_rs1_lane0    <= rs1_data_lane0;  p1_rs2_lane0    <= rs2_data_lane0;
                p1_rs1_lane1    <= rs1_data_lane1;  p1_rs2_lane1    <= rs2_data_lane1;
                p1_rs1_lane2    <= rs1_data_lane2;  p1_rs2_lane2    <= rs2_data_lane2;
                p1_rs1_lane3    <= rs1_data_lane3;  p1_rs2_lane3    <= rs2_data_lane3;
                p1_lane_mask0   <= lane_mask0;       p1_lane_mask1   <= lane_mask1;
                p1_lane_mask2   <= lane_mask2;       p1_lane_mask3   <= lane_mask3;
                p1_lane_we0     <= lane_we0;         p1_lane_we1     <= lane_we1;
                p1_lane_we2     <= lane_we2;         p1_lane_we3     <= lane_we3;
                p1_v0_carry0    <= lane0_v0_carry;   p1_v0_carry1    <= lane1_v0_carry;
                p1_v0_carry2    <= lane2_v0_carry;   p1_v0_carry3    <= lane3_v0_carry;
                p1_vd_addr      <= vd_addr_eff;
                p1_cycle_mask16 <= cycle_mask16_dbg;
                p1_vrf_wren     <= fsm_vrf_wren;
                p1_widen_sel    <= fsm_widen_sel;
                p1_elems_curr   <= elems_curr_cycle_dbg;
            end
        end
    end

    // ===== Pipelined lane write enables =====
    wire [3:0] p1_lane_we0_mux = p1_lane_we0 & p1_cycle_mask16[3:0];
    wire [3:0] p1_lane_we1_mux = p1_lane_we1 & p1_cycle_mask16[7:4];
    wire [3:0] p1_lane_we2_mux = p1_lane_we2 & p1_cycle_mask16[11:8];
    wire [3:0] p1_lane_we3_mux = p1_lane_we3 & p1_cycle_mask16[15:12];

    // ===== Mask buffer write control (pipelined) =====
    // in_valid fires during the cycle AFTER each masking-loop cycle (via p1_mask_valid),
    // and also during ST_DRAIN_MASK to flush the last element.
    wire mask_buf_in_valid = p1_mask_valid &&
                             ((fsm_state == 4'd5) || (fsm_state == 4'd10));
    // 4'd5=ST_MASKING, 4'd10=ST_DRAIN_MASK

    // =========================================================================
    // VLSU hazard signals (same as non-pipelined)
    // =========================================================================
    wire is_vls_load_raw   = (instruction[6:2] == 5'b00001);
    wire is_vls_store_raw  = (instruction[6:2] == 5'b01001);
    wire is_vls_unit_stride= (instruction[27:26] == 2'b00);
    wire is_vls_regular    = (instruction[24:20] == 5'b00000);
    wire is_vls_insn       = (is_vls_load_raw || is_vls_store_raw) && is_vls_unit_stride && is_vls_regular;

    reg [1:0] vls_sew_dec;
    always @(*) begin
        case (instruction[14:12])
            3'b000:  vls_sew_dec = 2'd0;
            3'b101:  vls_sew_dec = 2'd1;
            3'b110:  vls_sew_dec = 2'd2;
            default: vls_sew_dec = 2'd2;
        endcase
    end

    wire vlsu_busy_int;
    wire vlsu_busy_store_int;
    wire fifo_or_fsm_busy = fifo_data_valid || busy;

    wire [4:0] pending_vd_addr = busy ? vd_addr_eff : fifo_ctrl_out[14:10];
    wire load_waw_stall = instr_valid && is_vls_load_raw
                          && is_vls_unit_stride && is_vls_regular
                          && (busy || fifo_data_valid)
                          && (pending_vd_addr == instruction[11:7]);

    wire vls_fire = instr_valid && is_vls_insn && !vlsu_busy_int
                    && (!is_vls_store_raw || !fifo_or_fsm_busy)
                    && !load_waw_stall;

    reg vlsu_is_load_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)         vlsu_is_load_r <= 1'b1;
        else if (vls_fire)  vlsu_is_load_r <= is_vls_load_raw;
    end

    wire        vlsu_vrf_we;
    wire [4:0]  vlsu_vrf_waddr;

    reg [31:0] vrf_busy_r;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vrf_busy_r <= 32'b0;
        end else begin
            if (vls_fire && is_vls_load_raw)
                vrf_busy_r[instruction[11:7]] <= 1'b1;
            if (vlsu_vrf_we)
                vrf_busy_r[vlsu_vrf_waddr] <= 1'b0;
        end
    end

    wire [4:0] fifo_vs1_addr = fifo_ctrl_out[4:0];
    wire [4:0] fifo_vs2_addr = fifo_ctrl_out[9:5];
    wire [4:0] load_vd_addr  = instruction[11:7];

    wire cur_load_raw = vls_fire && is_vls_load_raw &&
                        (load_vd_addr == fifo_vs1_addr ||
                         load_vd_addr == fifo_vs2_addr);

    wire raw_stall = fifo_data_valid &&
                     (vrf_busy_r[fifo_vs1_addr] ||
                      vrf_busy_r[fifo_vs2_addr] ||
                      cur_load_raw);

    wire [31:0] vlsu_vrf_wdata_l0, vlsu_vrf_wdata_l1;
    wire [31:0] vlsu_vrf_wdata_l2, vlsu_vrf_wdata_l3;

    wire [4:0]  vlsu_vrf_raddr_int;
    wire [4:0]  vs2_addr_to_vrf = (vlsu_busy_int && !vlsu_is_load_r)
                                    ? vlsu_vrf_raddr_int : vs2_addr_eff;

    // =========================================================================
    // VRF write port — pipelined ALU path uses p1_* signals.
    // Bypass paths (VLSU, final_masking, reduction) use current-cycle signals.
    // =========================================================================
    wire [4:0]  vrf_waddr_eff  = vlsu_vrf_we ? vlsu_vrf_waddr
                               : (final_masking_commit || reduction_commit) ? vd_addr_eff
                               : p1_vd_addr;

    wire [31:0] vrf_wdata0_eff = vlsu_vrf_we        ? vlsu_vrf_wdata_l0
                               : final_masking_commit ? mask_buffer_data[31:0]
                               : reduction_commit     ? reduction_result
                               : wb_lane0;

    wire [31:0] vrf_wdata1_eff = vlsu_vrf_we        ? vlsu_vrf_wdata_l1
                               : final_masking_commit ? mask_buffer_data[63:32]
                               : wb_lane1;

    wire [31:0] vrf_wdata2_eff = vlsu_vrf_we        ? vlsu_vrf_wdata_l2
                               : final_masking_commit ? mask_buffer_data[95:64]
                               : wb_lane2;

    wire [31:0] vrf_wdata3_eff = vlsu_vrf_we        ? vlsu_vrf_wdata_l3
                               : final_masking_commit ? mask_buffer_data[127:96]
                               : wb_lane3;

    // ALU write enable: use p1_vrf_wren (1-cycle delayed from FSM vrf_wren).
    // Bypass writes override with their own enables.
    wire [3:0] vrf_we0_eff = vlsu_vrf_we        ? 4'b1111
                           : final_masking_commit ? (vrf_commit_en ? 4'b1111 : 4'b0000)
                           : reduction_commit     ? (vrf_commit_en ? 4'b1111 : 4'b0000)
                           : (vrf_commit_en && p1_vrf_wren) ? p1_lane_we0_mux : 4'b0000;

    wire [3:0] vrf_we1_eff = vlsu_vrf_we        ? 4'b1111
                           : final_masking_commit ? (vrf_commit_en ? 4'b1111 : 4'b0000)
                           : reduction_commit     ? 4'b0000
                           : (vrf_commit_en && p1_vrf_wren) ? p1_lane_we1_mux : 4'b0000;

    wire [3:0] vrf_we2_eff = vlsu_vrf_we        ? 4'b1111
                           : final_masking_commit ? (vrf_commit_en ? 4'b1111 : 4'b0000)
                           : reduction_commit     ? 4'b0000
                           : (vrf_commit_en && p1_vrf_wren) ? p1_lane_we2_mux : 4'b0000;

    wire [3:0] vrf_we3_eff = vlsu_vrf_we        ? 4'b1111
                           : final_masking_commit ? (vrf_commit_en ? 4'b1111 : 4'b0000)
                           : reduction_commit     ? 4'b0000
                           : (vrf_commit_en && p1_vrf_wren) ? p1_lane_we3_mux : 4'b0000;

    // ===== Decoder =====
    vproc_vdecoder #(
        .BASE_ADDR (ADDR_WIDTH),
        .CTRL_WIDTH(CTRL_WIDTH)
    ) decoder_inst (
        .instruction(instruction),
        .rs2_data   (rs2_scalar_data),
        .ctrl_bus   (dec_ctrl_bus),
        .imm_out    (dec_imm_out),
        .valid      (dec_valid)
    );

    // ===== FIFO =====
    vproc_fifo #(
        .CTRL_WIDTH(CTRL_WIDTH),
        .RS1_WIDTH (32),
        .IMM_WIDTH (32),
        .DEPTH     (8),
        .ADDR_W    (3)
    ) fifo_inst (
        .clk       (clk),
        .rst_n     (rst_n),
        .push_valid(instr_valid && dec_valid &&
                    (dec_ctrl_bus[28] ? ~fifo_full : vpu_ready)),
        .ctrl_in   (dec_ctrl_bus),
        .rs1_in    (rs1_scalar_data),
        .imm_in    (dec_imm_out),
        .full      (fifo_full),
        .ctrl_out  (fifo_ctrl_out),
        .rs1_out   (fifo_rs1_out),
        .imm_out   (fifo_imm_out),
        .data_valid(fifo_data_valid),
        .pop_ready (fsm_pop_ready)
    );

    wire is_store_stall = instr_valid && is_vls_store_raw
                          && is_vls_unit_stride && is_vls_regular
                          && fifo_or_fsm_busy;
    assign vpu_ready    = ~fifo_full && ~vlsu_busy_int
                          && ~is_store_stall && ~load_waw_stall;
    assign vlsu_busy_o  = vlsu_busy_int;
    assign vpu_cfg_done = fsm_csr_cfg_en;
    assign vpu_vl_remain = cfg_vl;

    // ===== FSM (pipelined variant) =====
    vproc_fsm_p fsm_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .instr_valid   (fifo_data_valid && !raw_stall),
        .is_config     (fifo_ctrl_out[28]),
        .is_masking    (fifo_ctrl_out[42]),
        .is_widen      (fifo_ctrl_out[21]),
        .is_reduction  (fifo_ctrl_out[47]),
        .counter_done  (counter_done),
        .reduction_done(reduction_wb_valid),
        .reduction_busy(red_busy),
        .latch_ctrl_en (fsm_latch_ctrl_en),
        .csr_cfg_en    (fsm_csr_cfg_en),
        .counter_start (fsm_counter_start),
        .vrf_wren      (fsm_vrf_wren),
        .widen_sel     (fsm_widen_sel),
        .s_offset_en   (fsm_s_offset_en),
        .d_offset_en   (fsm_d_offset_en),
        .offset_reset  (fsm_offset_reset),
        .pop_ready     (fsm_pop_ready),
        .reduction_start(fsm_reduction_start),
        .reduction_en  (fsm_reduction_en),
        .busy          (busy),
        .state_out     (fsm_state)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_r        <= {CTRL_WIDTH{1'b0}};
            rs1_latched_r <= 32'd0;
            imm_latched_r <= 32'd0;
        end else if (fsm_latch_ctrl_en) begin
            ctrl_r        <= fifo_ctrl_out;
            rs1_latched_r <= fifo_rs1_out;
            imm_latched_r <= fifo_imm_out;
        end
    end

    vproc_scalar_expand imm_expand_inst (
        .data_in (imm_latched_r),
        .sew     (cfg_sew),
        .data_out(imm_elem_vec)
    );

    vproc_scalar_expand rs1_expand_inst (
        .data_in (rs1_latched_r),
        .sew     (cfg_sew),
        .data_out(rs1_elem_vec)
    );

    wire [7:0]  vtype_active = ctrl_r[28] ? vtype_enc_r : csr_vtype_o[7:0];
    wire [31:0] cfg_avl_src  = ctrl_r[48] ? {27'b0, ctrl_r[4:0]} : rs1_latched_r;

    // ===== Config encoder =====
    vproc_cfg_encoder cfg_enc_inst (
        .vtype_enc  (vtype_active),
        .avl        (cfg_avl_src),
        .vl         (cfg_vl),
        .vlmax      (cfg_vlmax),
        .avl_remain (cfg_avl_remain),
        .sew        (cfg_sew),
        .vill       (cfg_vill)
    );

    // ===== Cycle counter =====
    vproc_cycle_counter cycle_counter_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (fsm_counter_start),
        .enable          (fsm_s_offset_en),
        .vl              (csr_vl_o),
        .vsew            (vtype_active[5:3]),
        .vlmul           (vtype_active[2:0]),
        .cycles_total    (cycles),
        .cycles_left     (cycles_left_dbg),
        .elems_curr_cycle(elems_curr_cycle_dbg),
        .cycle_mask16    (cycle_mask16_dbg),
        .cycle_index     (mask_cycle_idx),
        .done            (counter_done)
    );

    // ===== VRF address generator =====
    vproc_vrf_addr_gen #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) vrf_addr_gen_inst (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_offset_enable(fsm_s_offset_en),
        .d_offset_enable(fsm_d_offset_en),
        .offset_clear   (fsm_offset_reset),
        .vs1_base       (vs1_addr_base_r),
        .vs2_base       (vs2_addr_base_r),
        .vd_base        (vd_addr_base_r),
        .vs1_addr       (vs1_addr_eff),
        .vs2_addr       (vs2_addr_eff),
        .vd_addr        (vd_addr_eff)
    );

    // ===== CSR =====
    vproc_vcsr vcsr_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .cfg_en       (fsm_csr_cfg_en),
        .vl_in        (cfg_vl),
        .vtype_enc_in (vtype_enc_r),
        .csr_addr     (scalar_csr_addr),
        .csr_rdata    (scalar_csr_rdata),
        .vl_o         (csr_vl_o),
        .vtype_o      (csr_vtype_o),
        .vlenb_o      (csr_vlenb_o)
    );

    // ===== Mask enable =====
    vproc_mask_enable mask_enable_inst (
        .v0_flat        (v0_mask_flat),
        .sew            (cfg_sew),
        .mask_cycle_idx (mask_cycle_idx[2:0]),
        .vm             (vm_r),
        .mask16_window  (vmask16),
        .lane0_mask     (lane_mask0),
        .lane1_mask     (lane_mask1),
        .lane2_mask     (lane_mask2),
        .lane3_mask     (lane_mask3),
        .lane0_we       (lane_we0),
        .lane1_we       (lane_we1),
        .lane2_we       (lane_we2),
        .lane3_we       (lane_we3),
        .lane0_v0_carry (lane0_v0_carry),
        .lane1_v0_carry (lane1_v0_carry),
        .lane2_v0_carry (lane2_v0_carry),
        .lane3_v0_carry (lane3_v0_carry)
    );

    // ===== v0 merge bits (stable per instruction, no pipelining needed) =====
    wire [31:0] lane0_v0_merge_bits, lane1_v0_merge_bits, lane2_v0_merge_bits, lane3_v0_merge_bits;
    reg [31:0] lane0_v0_merge_bits_r, lane1_v0_merge_bits_r, lane2_v0_merge_bits_r, lane3_v0_merge_bits_r;
    integer i;
    always @(*) begin
        lane0_v0_merge_bits_r = 32'b0;
        lane1_v0_merge_bits_r = 32'b0;
        lane2_v0_merge_bits_r = 32'b0;
        lane3_v0_merge_bits_r = 32'b0;
        case (cfg_sew)
            3'd0: begin
                for (i = 0; i < 32; i = i + 1) begin
                    lane0_v0_merge_bits_r[i] = v0_mask_flat[(i * 4) + 0];
                    lane1_v0_merge_bits_r[i] = v0_mask_flat[(i * 4) + 1];
                    lane2_v0_merge_bits_r[i] = v0_mask_flat[(i * 4) + 2];
                    lane3_v0_merge_bits_r[i] = v0_mask_flat[(i * 4) + 3];
                end
            end
            3'd1: begin
                for (i = 0; i < 16; i = i + 1) begin
                    lane0_v0_merge_bits_r[(2*i)+0] = v0_mask_flat[(i * 8) + 0];
                    lane0_v0_merge_bits_r[(2*i)+1] = v0_mask_flat[(i * 8) + 1];
                    lane1_v0_merge_bits_r[(2*i)+0] = v0_mask_flat[(i * 8) + 2];
                    lane1_v0_merge_bits_r[(2*i)+1] = v0_mask_flat[(i * 8) + 3];
                    lane2_v0_merge_bits_r[(2*i)+0] = v0_mask_flat[(i * 8) + 4];
                    lane2_v0_merge_bits_r[(2*i)+1] = v0_mask_flat[(i * 8) + 5];
                    lane3_v0_merge_bits_r[(2*i)+0] = v0_mask_flat[(i * 8) + 6];
                    lane3_v0_merge_bits_r[(2*i)+1] = v0_mask_flat[(i * 8) + 7];
                end
            end
            default: begin
                for (i = 0; i < 32; i = i + 1) begin
                    lane0_v0_merge_bits_r[i] = v0_mask_flat[(i * 4) + 0];
                    lane1_v0_merge_bits_r[i] = v0_mask_flat[(i * 4) + 1];
                    lane2_v0_merge_bits_r[i] = v0_mask_flat[(i * 4) + 2];
                    lane3_v0_merge_bits_r[i] = v0_mask_flat[(i * 4) + 3];
                end
            end
        endcase
    end
    assign lane0_v0_merge_bits = vm_r ? 32'hFFFF_FFFF : lane0_v0_merge_bits_r;
    assign lane1_v0_merge_bits = vm_r ? 32'hFFFF_FFFF : lane1_v0_merge_bits_r;
    assign lane2_v0_merge_bits = vm_r ? 32'hFFFF_FFFF : lane2_v0_merge_bits_r;
    assign lane3_v0_merge_bits = vm_r ? 32'hFFFF_FFFF : lane3_v0_merge_bits_r;

    // ===== Reduction =====
    always @(*) begin
        case (funct6_r)
            6'b001100: reduction_operation = RED_SUM;
            6'b001101: reduction_operation = RED_MAX;
            6'b001110: reduction_operation = RED_MAXU;
            6'b001111: reduction_operation = RED_MIN;
            6'b010100: reduction_operation = RED_MINU;
            6'b011100: reduction_operation = RED_AND;
            6'b011101: reduction_operation = RED_OR;
            6'b011110: reduction_operation = RED_XOR;
            default:   reduction_operation = RED_SUM;
        endcase
    end

    vproc_reduction reduction_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (fsm_reduction_start && is_reduction_r),
        .valid        (fsm_reduction_en && is_reduction_r),
        .vec0_128     (rs2_vec_flat),
        .vec1_128     (rs1_vec_flat),
        .mask_sel_128 (v0_mask_flat),
        .sew          (cfg_sew),
        .operation    (reduction_operation),
        .done         (fsm_reduction_en && is_reduction_r && counter_done),
        .result_out   (reduction_result),
        .wb_valid     (reduction_wb_valid),
        .busy         (red_busy)
    );

    // ===== Mask write buffer =====
    // in_valid is the pipelined version of (s_offset_en && is_masking).
    // elems_curr_cycle is the captured value from the same execution cycle.
    vproc_mask_write_buffer mask_write_buffer_inst (
        .clk              (clk),
        .rst_n            (rst_n),
        .clear            (fsm_offset_reset),
        .in_valid         (mask_buf_in_valid),
        .sew              (cfg_sew),
        .elems_curr_cycle (p1_elems_curr),
        .index            (2'b00),
        .lane0_mask_in    (lane_mask_result0),
        .lane1_mask_in    (lane_mask_result1),
        .lane2_mask_in    (lane_mask_result2),
        .lane3_mask_in    (lane_mask_result3),
        .buffer_out       (mask_buffer_data),
        .wr_ptr_dbg       (mask_wr_ptr_dbg)
    );

    // ===== VLSU =====
    vproc_vec_lsu #(
        .VLEN      (128),
        .REG_AWIDTH(ADDR_WIDTH)
    ) vlsu_inst (
        .clk              (clk),
        .rst_n            (rst_n),
        .vls_valid        (vls_fire),
        .vls_is_load      (is_vls_load_raw),
        .vls_sew          (vls_sew_dec),
        .vls_vl           (csr_vl_o),
        .vls_vd_addr      (instruction[11:7]),
        .rs1_data         (rs1_scalar_data),
        .vm_i             (instruction[25]),
        .v0_flat_i        (v0_mask_flat),
        .vrf_lane0_rdata  (rs2_data_lane0),
        .vrf_lane1_rdata  (rs2_data_lane1),
        .vrf_lane2_rdata  (rs2_data_lane2),
        .vrf_lane3_rdata  (rs2_data_lane3),
        .vlsu_vrf_raddr   (vlsu_vrf_raddr_int),
        .mem_req          (vlsu_mem_req),
        .mem_we           (vlsu_mem_we),
        .mem_addr         (vlsu_mem_addr),
        .mem_be           (vlsu_mem_be),
        .mem_wdata        (vlsu_mem_wdata),
        .mem_rdata        (vlsu_mem_rdata),
        .mem_ready        (vlsu_mem_ready),
        .vrf_we           (vlsu_vrf_we),
        .vrf_waddr        (vlsu_vrf_waddr),
        .vrf_wdata_l0     (vlsu_vrf_wdata_l0),
        .vrf_wdata_l1     (vlsu_vrf_wdata_l1),
        .vrf_wdata_l2     (vlsu_vrf_wdata_l2),
        .vrf_wdata_l3     (vlsu_vrf_wdata_l3),
        .vlsu_busy        (vlsu_busy_int),
        .vlsu_busy_store  (vlsu_busy_store_int),
        .vls_done         ()
    );

    // ===== 4× VRF instances =====
    vproc_vregfile #(.NUM_REGS(NUM_REGS), .ADDR_WIDTH(ADDR_WIDTH)) vrf_lane0 (
        .clk      (clk),       .rst_n    (rst_n),
        .vs1      (vs1_addr_eff),
        .vs2      (vs2_addr_to_vrf),
        .vd       (vrf_waddr_eff),
        .write_en (vrf_we0_eff),
        .wdata    (vrf_wdata0_eff),
        .rs1_data (rs1_data_lane0),
        .rs2_data (rs2_data_lane0),
        .mask_data(mask_data_lane0)
    );

    vproc_vregfile #(.NUM_REGS(NUM_REGS), .ADDR_WIDTH(ADDR_WIDTH)) vrf_lane1 (
        .clk      (clk),       .rst_n    (rst_n),
        .vs1      (vs1_addr_eff),
        .vs2      (vs2_addr_to_vrf),
        .vd       (vrf_waddr_eff),
        .write_en (vrf_we1_eff),
        .wdata    (vrf_wdata1_eff),
        .rs1_data (rs1_data_lane1),
        .rs2_data (rs2_data_lane1),
        .mask_data(mask_data_lane1)
    );

    vproc_vregfile #(.NUM_REGS(NUM_REGS), .ADDR_WIDTH(ADDR_WIDTH)) vrf_lane2 (
        .clk      (clk),       .rst_n    (rst_n),
        .vs1      (vs1_addr_eff),
        .vs2      (vs2_addr_to_vrf),
        .vd       (vrf_waddr_eff),
        .write_en (vrf_we2_eff),
        .wdata    (vrf_wdata2_eff),
        .rs1_data (rs1_data_lane2),
        .rs2_data (rs2_data_lane2),
        .mask_data(mask_data_lane2)
    );

    vproc_vregfile #(.NUM_REGS(NUM_REGS), .ADDR_WIDTH(ADDR_WIDTH)) vrf_lane3 (
        .clk      (clk),       .rst_n    (rst_n),
        .vs1      (vs1_addr_eff),
        .vs2      (vs2_addr_to_vrf),
        .vd       (vrf_waddr_eff),
        .write_en (vrf_we3_eff),
        .wdata    (vrf_wdata3_eff),
        .rs1_data (rs1_data_lane3),
        .rs2_data (rs2_data_lane3),
        .mask_data(mask_data_lane3)
    );

    // ===== 4× Execution lanes (fed from pipeline register p1_*) =====
    // Per-cycle signals: vs1_data, vs2_data, vmask, v0_carry, widen_sel ← from p1.
    // Stable per-instruction: funct6, sew, sub, use_rs1/imm, etc. ← direct from ctrl_r.
    vproc_processor_lane lane0 (
        .vs1_data        (p1_rs1_lane0),
        .vs2_data        (p1_rs2_lane0),
        .immediate       (imm_elem_vec),
        .rs1_data        (rs1_elem_vec),
        .funct6          (funct6_r),
        .sew             (cfg_sew),
        .vmask           (p1_lane_mask0),
        .v0_carry        (p1_v0_carry0),
        .v0_merge_bits   (lane0_v0_merge_bits),
        .reverse_sub     (is_reverse_sub_r),
        .sub             (sub_r),
        .widen_sel       (p1_widen_sel),
        .use_rs1         (use_rs1_r),
        .use_imm         (use_imm_r),
        .is_carry        (is_carry_r),
        .is_mask_carry   (is_mask_carry_r),
        .is_compare      (is_compare_r),
        .minmax_is_min   (minmax_is_min_r),
        .minmax_is_unsign(minmax_is_unsign_r),
        .is_unsigned_vs1 (is_u_vs1_r),
        .is_unsigned_vs2 (is_u_vs2_r),
        .is_mulh         (is_mulh_r),
        .wb_result       (wb_lane0),
        .mask_result_out (lane_mask_result0)
    );

    vproc_processor_lane lane1 (
        .vs1_data        (p1_rs1_lane1),
        .vs2_data        (p1_rs2_lane1),
        .immediate       (imm_elem_vec),
        .rs1_data        (rs1_elem_vec),
        .funct6          (funct6_r),
        .sew             (cfg_sew),
        .vmask           (p1_lane_mask1),
        .v0_carry        (p1_v0_carry1),
        .v0_merge_bits   (lane1_v0_merge_bits),
        .reverse_sub     (is_reverse_sub_r),
        .sub             (sub_r),
        .widen_sel       (p1_widen_sel),
        .use_rs1         (use_rs1_r),
        .use_imm         (use_imm_r),
        .is_carry        (is_carry_r),
        .is_mask_carry   (is_mask_carry_r),
        .is_compare      (is_compare_r),
        .minmax_is_min   (minmax_is_min_r),
        .minmax_is_unsign(minmax_is_unsign_r),
        .is_unsigned_vs1 (is_u_vs1_r),
        .is_unsigned_vs2 (is_u_vs2_r),
        .is_mulh         (is_mulh_r),
        .wb_result       (wb_lane1),
        .mask_result_out (lane_mask_result1)
    );

    vproc_processor_lane lane2 (
        .vs1_data        (p1_rs1_lane2),
        .vs2_data        (p1_rs2_lane2),
        .immediate       (imm_elem_vec),
        .rs1_data        (rs1_elem_vec),
        .funct6          (funct6_r),
        .sew             (cfg_sew),
        .vmask           (p1_lane_mask2),
        .v0_carry        (p1_v0_carry2),
        .v0_merge_bits   (lane2_v0_merge_bits),
        .reverse_sub     (is_reverse_sub_r),
        .sub             (sub_r),
        .widen_sel       (p1_widen_sel),
        .use_rs1         (use_rs1_r),
        .use_imm         (use_imm_r),
        .is_carry        (is_carry_r),
        .is_mask_carry   (is_mask_carry_r),
        .is_compare      (is_compare_r),
        .minmax_is_min   (minmax_is_min_r),
        .minmax_is_unsign(minmax_is_unsign_r),
        .is_unsigned_vs1 (is_u_vs1_r),
        .is_unsigned_vs2 (is_u_vs2_r),
        .is_mulh         (is_mulh_r),
        .wb_result       (wb_lane2),
        .mask_result_out (lane_mask_result2)
    );

    vproc_processor_lane lane3 (
        .vs1_data        (p1_rs1_lane3),
        .vs2_data        (p1_rs2_lane3),
        .immediate       (imm_elem_vec),
        .rs1_data        (rs1_elem_vec),
        .funct6          (funct6_r),
        .sew             (cfg_sew),
        .vmask           (p1_lane_mask3),
        .v0_carry        (p1_v0_carry3),
        .v0_merge_bits   (lane3_v0_merge_bits),
        .reverse_sub     (is_reverse_sub_r),
        .sub             (sub_r),
        .widen_sel       (p1_widen_sel),
        .use_rs1         (use_rs1_r),
        .use_imm         (use_imm_r),
        .is_carry        (is_carry_r),
        .is_mask_carry   (is_mask_carry_r),
        .is_compare      (is_compare_r),
        .minmax_is_min   (minmax_is_min_r),
        .minmax_is_unsign(minmax_is_unsign_r),
        .is_unsigned_vs1 (is_u_vs1_r),
        .is_unsigned_vs2 (is_u_vs2_r),
        .is_mulh         (is_mulh_r),
        .wb_result       (wb_lane3),
        .mask_result_out (lane_mask_result3)
    );

    assign wb_result_lane0 = wb_lane0;
    assign wb_result_lane1 = wb_lane1;
    assign wb_result_lane2 = wb_lane2;
    assign wb_result_lane3 = wb_lane3;

endmodule
