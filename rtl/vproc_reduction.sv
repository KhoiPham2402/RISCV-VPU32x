// Reduction unit: vred* instructions.
// Processes ONE element per clock cycle to avoid deep combinational chains.
// Interface is unchanged except for the added 'busy' output.
//
// Protocol:
//   start=1  : reset accumulator (fires in ST_IDLE, one cycle before first valid)
//   valid=1  : new 128-bit chunk — latch data, begin per-element iteration (busy→1)
//   busy=1   : caller must hold valid=0 and not advance source address
//   done=1   : this chunk is the last — output result_out + wb_valid after iteration
//   wb_valid : pulses 1 cycle when final result is ready → FSM exits ST_REDUCTION

module vproc_reduction (
    input         clk,
    input         rst_n,
    input         start,
    input         valid,
    input  [127:0] vec0_128,
    input  [127:0] vec1_128,
    input  [127:0] mask_sel_128,
    input  [2:0]  sew,
    input  [3:0]  operation,
    input         done,
    output reg [31:0] result_out,
    output reg        wb_valid,
    output wire       busy
);

    localparam [3:0] RED_SUM  = 4'd0;
    localparam [3:0] RED_MAX  = 4'd1;
    localparam [3:0] RED_MAXU = 4'd2;
    localparam [3:0] RED_MIN  = 4'd3;
    localparam [3:0] RED_MINU = 4'd4;
    localparam [3:0] RED_AND  = 4'd5;
    localparam [3:0] RED_OR   = 4'd6;
    localparam [3:0] RED_XOR  = 4'd7;

    // Latched chunk state
    reg [127:0] vec0_r, vec1_r, mask_r;
    reg [2:0]   sew_r;
    reg [3:0]   op_r;
    reg         done_r;

    // Iteration state
    reg        active;
    reg [3:0]  elem_cnt;
    reg [31:0] acc_r;

    assign busy = active;

    // Last element index for current sew (latched)
    wire [3:0] last_elem = (sew_r == 3'd0) ? 4'd15 :
                           (sew_r == 3'd1) ? 4'd7  : 4'd3;

    // Bit-base address of current element (shift instead of multiply → no multiplier)
    wire [6:0] base8  = {elem_cnt[3:0], 3'b000};       // elem_cnt * 8,  max 120
    wire [6:0] base16 = {elem_cnt[2:0], 4'b0000};      // elem_cnt * 16, max 112
    wire [6:0] base32 = {elem_cnt[1:0], 5'b00000};     // elem_cnt * 32, max 96

    // MSB indices for sign extension
    wire [6:0] sign8  = {elem_cnt[3:0], 3'b111};       // base8  + 7
    wire [6:0] sign16 = {elem_cnt[2:0], 4'b1111};      // base16 + 15

    wire mask_bit = mask_r[elem_cnt];

    // Current element zero-extended to 32 bits
    wire [31:0] cur_u =
        (sew_r == 3'd0) ? (mask_bit ? {24'b0, vec1_r[base8  +: 8]}  : {24'b0, vec0_r[base8  +: 8]}) :
        (sew_r == 3'd1) ? (mask_bit ? {16'b0, vec1_r[base16 +: 16]} : {16'b0, vec0_r[base16 +: 16]}) :
                          (mask_bit ?         vec1_r[base32 +: 32]  :         vec0_r[base32 +: 32]);

    // Current element sign-extended to 32 bits (for signed comparisons)
    wire [31:0] cur_s =
        (sew_r == 3'd0) ? (mask_bit ? {{24{vec1_r[sign8]}},  vec1_r[base8  +: 8]}  :
                                      {{24{vec0_r[sign8]}},  vec0_r[base8  +: 8]}) :
        (sew_r == 3'd1) ? (mask_bit ? {{16{vec1_r[sign16]}}, vec1_r[base16 +: 16]} :
                                      {{16{vec0_r[sign16]}}, vec0_r[base16 +: 16]}) :
                          cur_u;

    // Single-cycle operation: accumulator ← op(accumulator, current_element)
    wire [31:0] acc_next =
        (op_r == RED_SUM ) ?  acc_r + cur_u :
        (op_r == RED_AND ) ?  acc_r & cur_u :
        (op_r == RED_OR  ) ?  acc_r | cur_u :
        (op_r == RED_XOR ) ?  acc_r ^ cur_u :
        (op_r == RED_MAXU) ? (acc_r < cur_u                        ? cur_u : acc_r) :
        (op_r == RED_MINU) ? (acc_r < cur_u                        ? acc_r : cur_u) :
        (op_r == RED_MAX ) ? ($signed(acc_r) < $signed(cur_s)      ? cur_u : acc_r) :
        (op_r == RED_MIN ) ? ($signed(acc_r) < $signed(cur_s)      ? acc_r : cur_u) :
                              acc_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active     <= 1'b0;
            elem_cnt   <= 4'd0;
            acc_r      <= 32'b0;
            done_r     <= 1'b0;
            result_out <= 32'b0;
            wb_valid   <= 1'b0;
            vec0_r     <= 128'b0;
            vec1_r     <= 128'b0;
            mask_r     <= 128'b0;
            sew_r      <= 3'd0;
            op_r       <= 4'd0;
        end else begin
            wb_valid <= 1'b0;

            if (start) begin
                acc_r  <= 32'b0;
                active <= 1'b0;
            end else if (valid && !active) begin
                // New chunk arrives — latch and start iterating.
                // RVV spec §14.1: initial accumulator value = vs1[0] (element 0 of vec1).
                vec0_r   <= vec0_128;
                vec1_r   <= vec1_128;
                mask_r   <= mask_sel_128;
                sew_r    <= sew;
                op_r     <= operation;
                done_r   <= done;
                elem_cnt <= 4'd0;
                active   <= 1'b1;
                // Seed accumulator from vs1[0] based on sew
                acc_r    <= (sew == 3'd0) ? {24'b0, vec1_128[7:0]}   :
                            (sew == 3'd1) ? {16'b0, vec1_128[15:0]}  :
                                                    vec1_128[31:0];
            end else if (active) begin
                acc_r <= acc_next;
                if (elem_cnt == last_elem) begin
                    active <= 1'b0;
                    if (done_r) begin
                        result_out <= acc_next;
                        wb_valid   <= 1'b1;
                    end
                end else begin
                    elem_cnt <= elem_cnt + 4'd1;
                end
            end
        end
    end

endmodule
