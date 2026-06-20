// Mask helper 4 lane.
// Chọn cửa sổ từ v0_flat[127:0] theo mask_cycle_idx (kiểu case/offset), rồi mux theo sew.
// v0_flat = {lane3_v0, lane2_v0, lane1_v0, lane0_v0} (wrapper).

module vproc_mask_enable (
    input  wire [127:0] v0_flat,
    input  wire [2:0]   sew,
    input  wire [2:0]   mask_cycle_idx,
    input  wire         vm,
    output wire [15:0]  mask16_window,
    output wire [3:0]   lane0_mask,
    output wire [3:0]   lane1_mask,
    output wire [3:0]   lane2_mask,
    output wire [3:0]   lane3_mask,
    output wire [3:0]   lane0_we,
    output wire [3:0]   lane1_we,
    output wire [3:0]   lane2_we,
    output wire [3:0]   lane3_we,
    // v0 slice (theo sew/cycle) cho ADC/SBC carry-in — luôn từ raw, không ép 4'hF khi vm=0
    output wire [3:0]   lane0_v0_carry,
    output wire [3:0]   lane1_v0_carry,
    output wire [3:0]   lane2_v0_carry,
    output wire [3:0]   lane3_v0_carry
);

    wire [1:0] sew_sel = (sew == 3'd2) ? 2'd2 :
                         (sew == 3'd1) ? 2'd1 : 2'd0;

    // --- SEW=8: mỗi offset một khối 16 bit (lane0 = [3:0], lane1 = [7:4], ...) ---
    reg [15:0] sew8_r;
    always_comb begin
        case (mask_cycle_idx)
            3'd0: sew8_r = v0_flat[15:0];
            3'd1: sew8_r = v0_flat[31:16];
            3'd2: sew8_r = v0_flat[47:32];
            3'd3: sew8_r = v0_flat[63:48];
            3'd4: sew8_r = v0_flat[79:64];
            3'd5: sew8_r = v0_flat[95:80];
            3'd6: sew8_r = v0_flat[111:96];
            3'd7: sew8_r = v0_flat[127:112];
            default: sew8_r = 16'b0;
        endcase
    end
    wire [15:0] sew8_out = sew8_r;

    // --- SEW=16: mỗi offset 8 bit mask ---
    reg [7:0] sew16_r;
    always_comb begin
        case (mask_cycle_idx)
            3'd0: sew16_r = v0_flat[7:0];
            3'd1: sew16_r = v0_flat[15:8];
            3'd2: sew16_r = v0_flat[23:16];
            3'd3: sew16_r = v0_flat[31:24];
            3'd4: sew16_r = v0_flat[39:32];
            3'd5: sew16_r = v0_flat[47:40];
            3'd6: sew16_r = v0_flat[55:48];
            3'd7: sew16_r = v0_flat[63:56];
            default: sew16_r = 8'b0;
        endcase
    end
    wire [7:0] sew16_out = sew16_r;

    // --- SEW=32: mỗi offset 4 bit mask ---
    reg [3:0] sew32_r;
    always_comb begin
        case (mask_cycle_idx)
            3'd0: sew32_r = v0_flat[3:0];
            3'd1: sew32_r = v0_flat[7:4];
            3'd2: sew32_r = v0_flat[11:8];
            3'd3: sew32_r = v0_flat[15:12];
            3'd4: sew32_r = v0_flat[19:16];
            3'd5: sew32_r = v0_flat[23:20];
            3'd6: sew32_r = v0_flat[27:24];
            3'd7: sew32_r = v0_flat[31:28];
            default: sew32_r = 4'b0;
        endcase
    end
    wire [3:0] sew32_out = sew32_r;

    assign mask16_window = (sew == 3'd2) ? {12'b0, sew32_out} :
                           (sew == 3'd1) ? {8'b0, sew16_out} :
                                           sew8_out;

    wire [3:0] lane0_raw;
    wire [3:0] lane1_raw;
    wire [3:0] lane2_raw;
    wire [3:0] lane3_raw;

    vproc_mux4to1_w4 u_lane0 (
        .i0 (sew8_out[3:0]),
        .i1 ({2'b0, sew16_out[1:0]}),
        .i2 ({3'b0, sew32_out[0]}),
        .i3 (4'b0),
        .sel(sew_sel),
        .y  (lane0_raw)
    );
    vproc_mux4to1_w4 u_lane1 (
        .i0 (sew8_out[7:4]),
        .i1 ({2'b0, sew16_out[3:2]}),
        .i2 ({3'b0, sew32_out[1]}),
        .i3 (4'b0),
        .sel(sew_sel),
        .y  (lane1_raw)
    );
    vproc_mux4to1_w4 u_lane2 (
        .i0 (sew8_out[11:8]),
        .i1 ({2'b0, sew16_out[5:4]}),
        .i2 ({3'b0, sew32_out[2]}),
        .i3 (4'b0),
        .sel(sew_sel),
        .y  (lane2_raw)
    );
    vproc_mux4to1_w4 u_lane3 (
        .i0 (sew8_out[15:12]),
        .i1 ({2'b0, sew16_out[7:6]}),
        .i2 ({3'b0, sew32_out[3]}),
        .i3 (4'b0),
        .sel(sew_sel),
        .y  (lane3_raw)
    );

    assign lane0_mask = vm ? 4'hF : lane0_raw;
    assign lane1_mask = vm ? 4'hF : lane1_raw;
    assign lane2_mask = vm ? 4'hF : lane2_raw;
    assign lane3_mask = vm ? 4'hF : lane3_raw;

    assign lane0_v0_carry = lane0_raw;
    assign lane1_v0_carry = lane1_raw;
    assign lane2_v0_carry = lane2_raw;
    assign lane3_v0_carry = lane3_raw;

    assign lane0_we = (sew == 3'd2) ? {4{lane0_mask[0]}} :
                       (sew == 3'd1) ? {{2{lane0_mask[1]}}, {2{lane0_mask[0]}}} :
                                        lane0_mask;

    assign lane1_we = (sew == 3'd2) ? {4{lane1_mask[0]}} :
                       (sew == 3'd1) ? {{2{lane1_mask[1]}}, {2{lane1_mask[0]}}} :
                                        lane1_mask;

    assign lane2_we = (sew == 3'd2) ? {4{lane2_mask[0]}} :
                       (sew == 3'd1) ? {{2{lane2_mask[1]}}, {2{lane2_mask[0]}}} :
                                        lane2_mask;

    assign lane3_we = (sew == 3'd2) ? {4{lane3_mask[0]}} :
                       (sew == 3'd1) ? {{2{lane3_mask[1]}}, {2{lane3_mask[0]}}} :
                                        lane3_mask;

endmodule
