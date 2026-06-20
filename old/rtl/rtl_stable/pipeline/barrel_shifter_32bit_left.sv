module barrel_shifter_32bit_left(
    input logic [31:0] data,
    input logic [4:0] amt,
    output logic [31:0] out
);

    always_comb begin
        case (amt)
            5'd0: out = data;
            5'd1: out = {data[30:0], 1'd0}; // Dịch trái 1 bit, thêm 0 vào cuối
            5'd2: out = {data[29:0], 2'd0}; // Dịch trái 2 bit, thêm 0 vào cuối
            5'd3: out = {data[28:0], 3'd0}; // ...
            5'd4: out = {data[27:0], 4'd0};
            5'd5: out = {data[26:0], 5'd0};
            5'd6: out = {data[25:0], 6'd0};
            5'd7: out = {data[24:0], 7'd0};
            5'd8: out = {data[23:0], 8'd0};
            5'd9: out = {data[22:0], 9'd0};
            5'd10: out = {data[21:0], 10'd0};
            5'd11: out = {data[20:0], 11'd0};
            5'd12: out = {data[19:0], 12'd0};
            5'd13: out = {data[18:0], 13'd0};
            5'd14: out = {data[17:0], 14'd0};
            5'd15: out = {data[16:0], 15'd0};
            5'd16: out = {data[15:0], 16'd0};
            5'd17: out = {data[14:0], 17'd0};
            5'd18: out = {data[13:0], 18'd0};
            5'd19: out = {data[12:0], 19'd0};
            5'd20: out = {data[11:0], 20'd0};
            5'd21: out = {data[10:0], 21'd0};
            5'd22: out = {data[9:0], 22'd0};
            5'd23: out = {data[8:0], 23'd0};
            5'd24: out = {data[7:0], 24'd0};
            5'd25: out = {data[6:0], 25'd0};
            5'd26: out = {data[5:0], 26'd0};
            5'd27: out = {data[4:0], 27'd0};
            5'd28: out = {data[3:0], 28'd0};
            5'd29: out = {data[2:0], 29'd0};
            5'd30: out = {data[1:0], 30'd0};
            5'd31: out = {data[0], 31'd0};
            default: out = 32'd0; // Xử lý trường hợp không hợp lệ
        endcase
    end
endmodule 