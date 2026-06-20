module barrel_shifter_32bit(
    input  logic [31:0] data,
    input  logic [4:0]  amt,
    input  logic        is_arithmetic,  // 1 = SRA, 0 = SRL
    output logic [31:0] out
);

    logic fill_bit;
    assign fill_bit = is_arithmetic ? data[31] : 1'b0;

    always_comb begin
        case (amt)
            5'd0:  out = data;
            5'd1:  out = {fill_bit, data[31:1]};
            5'd2:  out = {{2{fill_bit}}, data[31:2]};
            5'd3:  out = {{3{fill_bit}}, data[31:3]};
            5'd4:  out = {{4{fill_bit}}, data[31:4]};
            5'd5:  out = {{5{fill_bit}}, data[31:5]};
            5'd6:  out = {{6{fill_bit}}, data[31:6]};
            5'd7:  out = {{7{fill_bit}}, data[31:7]};
            5'd8:  out = {{8{fill_bit}}, data[31:8]};
            5'd9:  out = {{9{fill_bit}}, data[31:9]};
            5'd10: out = {{10{fill_bit}}, data[31:10]};
            5'd11: out = {{11{fill_bit}}, data[31:11]};
            5'd12: out = {{12{fill_bit}}, data[31:12]};
            5'd13: out = {{13{fill_bit}}, data[31:13]};
            5'd14: out = {{14{fill_bit}}, data[31:14]};
            5'd15: out = {{15{fill_bit}}, data[31:15]};
            5'd16: out = {{16{fill_bit}}, data[31:16]};
            5'd17: out = {{17{fill_bit}}, data[31:17]};
            5'd18: out = {{18{fill_bit}}, data[31:18]};
            5'd19: out = {{19{fill_bit}}, data[31:19]};
            5'd20: out = {{20{fill_bit}}, data[31:20]};
            5'd21: out = {{21{fill_bit}}, data[31:21]};
            5'd22: out = {{22{fill_bit}}, data[31:22]};
            5'd23: out = {{23{fill_bit}}, data[31:23]};
            5'd24: out = {{24{fill_bit}}, data[31:24]};
            5'd25: out = {{25{fill_bit}}, data[31:25]};
            5'd26: out = {{26{fill_bit}}, data[31:26]};
            5'd27: out = {{27{fill_bit}}, data[31:27]};
            5'd28: out = {{28{fill_bit}}, data[31:28]};
            5'd29: out = {{29{fill_bit}}, data[31:29]};
            5'd30: out = {{30{fill_bit}}, data[31:30]};
            5'd31: out = {{31{fill_bit}}, data[31]};
            default: out = 32'd0;
        endcase
    end

endmodule
