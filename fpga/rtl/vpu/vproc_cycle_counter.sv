// Runtime cycle counter cho VPU.
//
// Chức năng:
// 1) Tính tổng số chu kì cần xử lý từ vlmul (KHÔNG nhân đôi cho widen).
// 2) Đếm số chu kì còn lại trong lúc EXEC/WIDEN.
// 3) Tính số phần tử còn xử lý ở chu kì hiện tại.
// 4) So sánh cycles_left <= 0 để assert done.

module vproc_cycle_counter (
    input         clk,
    input         rst_n,
    input         start,            // pulse khi nhận lệnh mới (latch_ctrl_en)
    input         enable,           // active trong EXEC/WIDEN
    input  [31:0] vl,               // số element cần xử lý
    input  [2:0]  vsew,             // 000=8b, 001=16b, 010=32b
    input  [2:0]  vlmul,            // RVV vlmul encoding
    output [3:0]  cycles_total,     // tổng chu kì cần chạy
    output [3:0]  cycles_left,      // chu kì còn lại
    output [7:0]  elems_curr_cycle, // số element cần xử lý ở chu kì hiện tại
    output [15:0] cycle_mask16,     // mask byte-enable cho chu kì hiện tại
    output [3:0]  cycle_index,      // chỉ số chunk LMUL (0..7), 0 khi không chạy — cho mux mask v0
    output        done
);

    reg  [3:0] cycles_base_r;
    reg  [4:0] cycles_total_w;
    reg  [7:0] elems_per_cycle_r;
    reg  [7:0] elems_left_r;
    reg  [3:0] cycles_left_r;
    reg        running_r;
    reg  [15:0] cycle_mask16_r;
    reg  [5:0] active_bytes_r;
    reg  [3:0] cycles_total_latched_r;
    wire [7:0] vl_8b = (vl > 32'd255) ? 8'hFF : vl[7:0];

    always_comb begin
        cycles_base_r = 4'd0;

        case (vlmul)
            3'b000: begin // m1
                cycles_base_r = 4'd1;
            end
            3'b001: begin // m2
                cycles_base_r = 4'd2;
            end
            3'b010: begin // m4
                cycles_base_r = 4'd4;
            end
            3'b011: begin // m8
                cycles_base_r = 4'd8;
            end
            3'b101: begin // mf8
                cycles_base_r = 4'd1;
            end
            3'b110: begin // mf4
                cycles_base_r = 4'd1;
            end
            3'b111: begin // mf2
                cycles_base_r = 4'd1;
            end
            default: begin // 3'b100 reserved
                cycles_base_r = 4'd0;
            end
        endcase
    end

    always_comb begin
        case (vsew)
            3'b000: elems_per_cycle_r = 8'd16; // 128/8
            3'b001: elems_per_cycle_r = 8'd8;  // 128/16
            3'b010: elems_per_cycle_r = 8'd4;  // 128/32
            default: elems_per_cycle_r = 8'd16;
        endcase
    end

    always_comb begin
        cycles_total_w = {1'b0, cycles_base_r};
    end

    // Runtime countdown registers
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycles_left_r <= 4'd0;
            elems_left_r  <= 8'd0;
            running_r     <= 1'b0;
            cycles_total_latched_r <= 4'd0;
        end else if (start) begin
            cycles_total_latched_r <= (cycles_total_w > 5'd15) ? 4'd15 : cycles_total_w[3:0];
            cycles_left_r <= (cycles_total_w == 5'd0) ? 4'd0 :
                             ((cycles_total_w > 5'd15) ? 4'd15 : (cycles_total_w[3:0] - 4'd1));
            elems_left_r  <= vl_8b;
            running_r     <= (cycles_total_w != 5'd0);
        end else if (enable && running_r) begin
            if (elems_left_r > elems_per_cycle_r)
                elems_left_r <= elems_left_r - elems_per_cycle_r;
            else
                elems_left_r <= 8'd0;

            if (cycles_left_r != 4'd0) begin
                cycles_left_r <= cycles_left_r - 4'd1;
            end else begin
                // Đã xử lý cycle cuối cùng: hạ running để done bật.
                running_r <= 1'b0;
            end
        end
    end

    assign cycles_total = (cycles_total_w > 5'd15) ? 4'd15 : cycles_total_w[3:0];
    assign cycles_left  = cycles_left_r;
    assign elems_curr_cycle = (elems_left_r >= elems_per_cycle_r) ? elems_per_cycle_r : elems_left_r;
    
    // Combinational mask theo elems_curr_cycle + vsew
    // - Nếu full cycle: mask = FFFF
    // - Nếu partial: bật đúng số byte tương ứng với số element hiện tại
    always_comb begin
        active_bytes_r = 6'd0;

        if (elems_curr_cycle >= elems_per_cycle_r) begin
            cycle_mask16_r = 16'hFFFF;
        end else begin
            case (vsew)
                3'b000: active_bytes_r = (elems_curr_cycle > 8'd16) ? 6'd16 : elems_curr_cycle[5:0];         // 1B/elem
                3'b001: active_bytes_r = (elems_curr_cycle > 8'd8 ) ? 6'd16 : {elems_curr_cycle[4:0], 1'b0}; // 2B/elem
                3'b010: active_bytes_r = (elems_curr_cycle > 8'd4 ) ? 6'd16 : {elems_curr_cycle[3:0], 2'b00}; // 4B/elem
                default: active_bytes_r = 6'd16;
            endcase

            if (active_bytes_r == 6'd0)
                cycle_mask16_r = 16'h0000;
            else if (active_bytes_r >= 6'd16)
                cycle_mask16_r = 16'hFFFF;
            else
                cycle_mask16_r = (16'h0001 << active_bytes_r) - 16'h0001;
        end
    end

    assign cycle_mask16 = cycle_mask16_r;
    assign cycle_index = running_r ?
        ((cycles_total_latched_r == 4'd0) ? 4'd0 :
         (cycles_total_latched_r - 4'd1) - cycles_left_r) : 4'd0;
    assign done = (cycles_left_r == 4'd0) && running_r;

endmodule
