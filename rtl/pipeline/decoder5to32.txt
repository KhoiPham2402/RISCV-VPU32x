module decoder5to32 (
    input  logic        en,      // active-high enable
    input  logic [4:0]  in,      // 5-bit input (0..31)
    output logic [31:0] out      // out[0] always = 0
);

    always_comb begin
        if (!en) begin
            out = 32'd0;
        end
        else begin
            case (in)
                5'd0 : out = 32'd0;        // x0 always ZERO
                5'd1 : out = 32'd2;        // bit1
                5'd2 : out = 32'd4;
                5'd3 : out = 32'd8;
                5'd4 : out = 32'd16;
                5'd5 : out = 32'd32;
                5'd6 : out = 32'd64;
                5'd7 : out = 32'd128;
                5'd8 : out = 32'd256;
                5'd9 : out = 32'd512;
                5'd10: out = 32'd1024;
                5'd11: out = 32'd2048;
                5'd12: out = 32'd4096;
                5'd13: out = 32'd8192;
                5'd14: out = 32'd16384;
                5'd15: out = 32'd32768;
                5'd16: out = 32'd65536;
                5'd17: out = 32'd131072;
                5'd18: out = 32'd262144;
                5'd19: out = 32'd524288;
                5'd20: out = 32'd1048576;
                5'd21: out = 32'd2097152;
                5'd22: out = 32'd4194304;
                5'd23: out = 32'd8388608;
                5'd24: out = 32'd16777216;
                5'd25: out = 32'd33554432;
                5'd26: out = 32'd67108864;
                5'd27: out = 32'd134217728;
                5'd28: out = 32'd268435456;
                5'd29: out = 32'd536870912;
                5'd30: out = 32'd1073741824;
                5'd31: out = 32'd2147483648;  // bit31
                default: out = 32'd0;
            endcase
        end
    end

endmodule

