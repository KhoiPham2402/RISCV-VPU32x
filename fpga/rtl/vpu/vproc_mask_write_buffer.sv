// MaskWriteBuffer đơn giản để gom mask result từ 4 lane.
// - Mỗi chu kỳ ghi số bit phụ thuộc sew:
//     sew=0 -> ghi 16 bit (4 bit/lane, tương ứng SEW=8)
//     sew=1 -> ghi  8 bit (2 bit/lane, tương ứng SEW=16)
//     sew=2 -> ghi  4 bit (1 bit/lane, tương ứng SEW=32)
// - elems_curr_cycle: chỉ giữ đúng số bit mask tương ứng phần tử active (VL tail);
//   chunk cuối không ghi thừa (vd: VL=13 e16 -> 8+5 bit, thấp 13 bit = 0x1FFF nếu toàn 1).
// - Con trỏ ghi tự tăng đúng số bit đã ghi mỗi lần in_valid.
// - Không dùng done: module chỉ ghi khi in_valid=1, FSM tự quyết định khi nào dừng.
//
// Ý nghĩa theo sew (theo mapping bạn yêu cầu):
//   sew=0: lấy toàn bộ [3:0] của mỗi lane
//   sew=1: lấy [1:0] của mỗi lane
//   sew=2: chỉ lấy [0] của mỗi lane
//
module vproc_mask_write_buffer (
    input         clk,
    input         rst_n,
    input         clear,

    input         in_valid,   // ghi dữ liệu input vào buffer

    input  [2:0]  sew,
    input  [7:0]  elems_curr_cycle, // số phần tử active trong chunk hiện tại (từ cycle_counter)

    input  [1:0]  index,      // giữ lại để tương thích interface hiện tại (chưa dùng trong bản đơn giản)

    input  [3:0]  lane0_mask_in,
    input  [3:0]  lane1_mask_in,
    input  [3:0]  lane2_mask_in,
    input  [3:0]  lane3_mask_in,

    output [127:0] buffer_out,
    output [6:0]   wr_ptr_dbg
);

    reg [127:0] buffer_r;
    reg [6:0]   wr_ptr_r;

    assign buffer_out = buffer_r;
    assign wr_ptr_dbg = wr_ptr_r;

    reg [15:0] write_data;
    reg [15:0] chunk_bit_mask; // mask bit theo elems trong chunk (1 bit / phần tử carry)
    reg [31:0] chunk_mask32;   // tránh shift 16-bit overflow khi tính (1<<e)-1

    // Trích dữ liệu cần ghi theo sew.
    always @(*) begin
        write_data     = 16'b0;
        case (sew)
            3'd0: begin
                write_data     = {lane3_mask_in[3:0], lane2_mask_in[3:0], lane1_mask_in[3:0], lane0_mask_in[3:0]};
            end
            3'd1: begin
                write_data     = {8'b0, lane3_mask_in[1:0], lane2_mask_in[1:0], lane1_mask_in[1:0], lane0_mask_in[1:0]};
            end
            3'd2: begin
                write_data     = {12'b0, lane3_mask_in[0], lane2_mask_in[0], lane1_mask_in[0], lane0_mask_in[0]};
            end
            default: begin
                write_data     = 16'b0;
            end
        endcase
    end

    // Giữ đúng elems_curr_cycle bit thấp trong chunk (1 bit / phần tử); chunk đầy = toàn 1 trong độ rộng chunk.
    always @(*) begin
        chunk_bit_mask = 16'h0000;
        case (sew)
            3'd0: begin // toi da 16 bit / lan ghi
                if (elems_curr_cycle >= 8'd16)
                    chunk_bit_mask = 16'hFFFF;
                else if (elems_curr_cycle == 8'd0)
                    chunk_bit_mask = 16'h0000;
                else begin
                    chunk_mask32 = (32'd1 << elems_curr_cycle[4:0]) - 32'd1;
                    chunk_bit_mask = chunk_mask32[15:0];
                end
            end
            3'd1: begin // toi da 8 bit / lan ghi
                if (elems_curr_cycle >= 8'd8)
                    chunk_bit_mask = 16'h00FF;
                else if (elems_curr_cycle == 8'd0)
                    chunk_bit_mask = 16'h0000;
                else
                    chunk_bit_mask = {8'h00, (8'h01 << elems_curr_cycle[2:0]) - 8'h01};
            end
            3'd2: begin // toi da 4 bit / lan ghi
                if (elems_curr_cycle >= 8'd4)
                    chunk_bit_mask = 16'h000F;
                else if (elems_curr_cycle == 8'd0)
                    chunk_bit_mask = 16'h0000;
                else
                    chunk_bit_mask = {12'h000, (4'h1 << elems_curr_cycle[1:0]) - 4'h1};
            end
            default: chunk_bit_mask = 16'h0000;
        endcase
    end

    wire [15:0] write_data_masked = write_data & chunk_bit_mask;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buffer_r  <= 128'b0;
            wr_ptr_r  <= 7'd0;
        end else if (clear) begin
            buffer_r  <= 128'b0;
            wr_ptr_r  <= 7'd0;
        end else begin
            if (in_valid) begin
                case (sew)
                    3'd0: begin
                        if (wr_ptr_r <= 7'd112) begin
                            buffer_r <= (buffer_r & ~(128'hFFFF << wr_ptr_r)) |
                                        ({112'b0, write_data_masked} << wr_ptr_r);
                            wr_ptr_r <= wr_ptr_r + 7'd16;
                        end
                    end
                    3'd1: begin
                        if (wr_ptr_r <= 7'd120) begin
                            buffer_r <= (buffer_r & ~(128'hFF << wr_ptr_r)) |
                                        ({120'b0, write_data_masked[7:0]} << wr_ptr_r);
                            wr_ptr_r <= wr_ptr_r + 7'd8;
                        end
                    end
                    3'd2: begin
                        if (wr_ptr_r <= 7'd124) begin
                            buffer_r <= (buffer_r & ~(128'hF << wr_ptr_r)) |
                                        ({124'b0, write_data_masked[3:0]} << wr_ptr_r);
                            wr_ptr_r <= wr_ptr_r + 7'd4;
                        end
                    end
                    default: begin
                        wr_ptr_r <= wr_ptr_r;
                    end
                endcase
            end
        end
    end

endmodule

