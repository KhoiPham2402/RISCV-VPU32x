// Pipelined VPU FSM — extends vproc_fsm with ST_DRAIN and ST_DRAIN_MASK.
//
// ST_DRAIN      : 1-cycle flush inserted after ST_EXEC / ST_WIDENH.
//                 Lets the pre-lane pipeline register write its last result to VRF.
// ST_DRAIN_MASK : 1-cycle flush inserted after ST_MASKING.
//                 Lets the pre-lane pipeline register write last mask bits to the
//                 mask-write-buffer before ST_FINAL_MASKING commits the buffer.
//
// State diagram (new transitions only):
//   ST_EXEC    ──(counter_done)──► ST_DRAIN      ──► ST_IDLE
//   ST_WIDENH  ──(counter_done)──► ST_DRAIN      ──► ST_IDLE
//   ST_MASKING ──(counter_done)──► ST_DRAIN_MASK ──► ST_FINAL_MASKING ──► ST_IDLE

module vproc_fsm_p (
    input         clk,
    input         rst_n,

    input         instr_valid,
    input         is_config,
    input         is_masking,
    input         is_widen,
    input         is_reduction,

    input         counter_done,
    input         reduction_done,
    input         reduction_busy,

    output logic  latch_ctrl_en,
    output logic  csr_cfg_en,
    output logic  counter_start,
    output logic  vrf_wren,
    output logic  widen_sel,
    output logic  s_offset_en,
    output logic  d_offset_en,
    output logic  offset_reset,
    output logic  pop_ready,
    output logic  reduction_start,
    output logic  reduction_en,

    output        busy,
    output [3:0]  state_out
);

    typedef enum logic [3:0] {
        ST_IDLE           = 4'd0,
        ST_CONFIG         = 4'd1,
        ST_EXEC           = 4'd2,
        ST_WIDENL         = 4'd3,
        ST_WIDENH         = 4'd4,
        ST_MASKING        = 4'd5,
        ST_FINAL_MASKING  = 4'd6,
        ST_REDUCTION      = 4'd7,
        ST_REDUCTION_DONE = 4'd8,
        ST_DRAIN          = 4'd9,   // flush ALU pipeline → VRF write (1 cycle)
        ST_DRAIN_MASK     = 4'd10   // flush mask pipeline → mask buffer write (1 cycle)
    } fsm_state_t;

    fsm_state_t state_r, state_next;
    assign state_out = state_r;
    assign busy      = (state_r != ST_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state_r <= ST_IDLE;
        else        state_r <= state_next;
    end

    always_comb begin
        state_next = state_r;
        unique case (state_r)
            ST_IDLE: begin
                if (instr_valid) begin
                    if      (is_config)    state_next = ST_CONFIG;
                    else if (is_masking)   state_next = ST_MASKING;
                    else if (is_widen)     state_next = ST_WIDENL;
                    else if (is_reduction) state_next = ST_REDUCTION;
                    else                   state_next = ST_EXEC;
                end
            end
            ST_CONFIG:         state_next = ST_IDLE;
            ST_EXEC:           state_next = counter_done ? ST_DRAIN    : ST_EXEC;
            ST_WIDENL:         state_next = ST_WIDENH;
            ST_WIDENH:         state_next = counter_done ? ST_DRAIN    : ST_WIDENL;
            ST_MASKING:        state_next = counter_done ? ST_DRAIN_MASK : ST_MASKING;
            ST_DRAIN:          state_next = ST_IDLE;
            ST_DRAIN_MASK:     state_next = ST_FINAL_MASKING;
            ST_FINAL_MASKING:  state_next = ST_IDLE;
            ST_REDUCTION:      state_next = reduction_done ? ST_REDUCTION_DONE : ST_REDUCTION;
            ST_REDUCTION_DONE: state_next = ST_IDLE;
            default:           state_next = ST_IDLE;
        endcase
    end

    always_comb begin
        latch_ctrl_en   = 1'b0;
        csr_cfg_en      = 1'b0;
        counter_start   = 1'b0;
        vrf_wren        = 1'b0;
        pop_ready       = 1'b0;
        widen_sel       = 1'b0;
        s_offset_en     = 1'b0;
        d_offset_en     = 1'b0;
        offset_reset    = 1'b0;
        reduction_start = 1'b0;
        reduction_en    = 1'b0;

        unique case (state_r)
            ST_IDLE: begin
                offset_reset = 1'b1;
                if (instr_valid) begin
                    latch_ctrl_en = 1'b1;
                    pop_ready     = 1'b1;
                    if (!is_config)    counter_start   = 1'b1;
                    if (is_reduction)  reduction_start = 1'b1;
                end
            end

            ST_CONFIG: begin
                csr_cfg_en = 1'b1;
            end

            ST_EXEC: begin
                // vrf_wren=1 so p1_vrf_wren captures 1 in the pipeline register.
                // The wrapper uses p1_vrf_wren (delayed 1 cycle) for the actual write.
                vrf_wren    = 1'b1;
                s_offset_en = 1'b1;
                d_offset_en = 1'b1;
            end

            ST_WIDENL: begin
                vrf_wren    = 1'b1;
                d_offset_en = 1'b1;
            end

            ST_WIDENH: begin
                vrf_wren    = 1'b1;
                widen_sel   = 1'b1;
                s_offset_en = 1'b1;
                d_offset_en = 1'b1;
            end

            ST_MASKING: begin
                s_offset_en = 1'b1;
            end

            // ST_DRAIN: hold all offsets; wrapper commits last ALU result via p1_vrf_wren.
            ST_DRAIN: begin
            end

            // ST_DRAIN_MASK: hold all offsets; wrapper commits last mask result via p1_mask_valid.
            ST_DRAIN_MASK: begin
            end

            ST_FINAL_MASKING: begin
                vrf_wren = 1'b1;
            end

            ST_REDUCTION: begin
                s_offset_en  = !reduction_busy;
                reduction_en = !reduction_busy;
            end

            ST_REDUCTION_DONE: begin
                vrf_wren = 1'b1;
            end

            default: begin
            end
        endcase
    end

endmodule
