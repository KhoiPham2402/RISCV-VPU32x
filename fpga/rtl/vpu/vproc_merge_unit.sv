// Module merge 32-bit theo mask v0 đã phân bố cho từng lane.
// - Input: 2 nguồn dữ liệu 32-bit (vs1_data, vs2_data)
// - v0_lane_bits: 32 bit mask của lane (được tách từ v0 128-bit ở top)
// - sew quyết định độ rộng phần tử:
//     sew=0 (8-bit)  : dùng v0_lane_bits[3:0] cho 4 byte
//     sew=1 (16-bit) : dùng v0_lane_bits[1:0] cho 2 halfword
//     sew=2 (32-bit) : dùng v0_lane_bits[0]   cho 1 word
// Quy ước chọn:
//   v0 bit = 1 -> lấy từ vs1_data
//   v0 bit = 0 -> lấy từ vs2_data

module vproc_merge_unit (
    input  [31:0] vs1_data,
    input  [31:0] vs2_data,
    input  [31:0] v0_lane_bits,
    input  [2:0]  sew,
    output reg [31:0] merge_out
);

    always_comb begin
        case (sew)
            3'd0: begin
                merge_out[7:0]   = v0_lane_bits[0] ? vs1_data[7:0]   : vs2_data[7:0];
                merge_out[15:8]  = v0_lane_bits[1] ? vs1_data[15:8]  : vs2_data[15:8];
                merge_out[23:16] = v0_lane_bits[2] ? vs1_data[23:16] : vs2_data[23:16];
                merge_out[31:24] = v0_lane_bits[3] ? vs1_data[31:24] : vs2_data[31:24];
            end
            3'd1: begin
                merge_out[15:0]  = v0_lane_bits[0] ? vs1_data[15:0]  : vs2_data[15:0];
                merge_out[31:16] = v0_lane_bits[1] ? vs1_data[31:16] : vs2_data[31:16];
            end
            3'd2: begin
                merge_out = v0_lane_bits[0] ? vs1_data : vs2_data;
            end
            default: begin
                merge_out = v0_lane_bits[0] ? vs1_data : vs2_data;
            end
        endcase
    end

endmodule

