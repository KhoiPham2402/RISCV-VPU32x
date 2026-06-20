// Ô mux dùng chung cho mask path (structural: 8:1 = cây 2:1).

module vproc_mux2to1 (
    input  wire a,
    input  wire b,
    input  wire sel,
    output wire y
);
    assign y = sel ? b : a;
endmodule

module vproc_mux8to1 (
    input  wire       i0,
    input  wire       i1,
    input  wire       i2,
    input  wire       i3,
    input  wire       i4,
    input  wire       i5,
    input  wire       i6,
    input  wire       i7,
    input  wire [2:0] sel,
    output wire       y
);
    wire s00, s01, s02, s03;
    wire s10, s11;

    vproc_mux2to1 u00 (.a(i0), .b(i1), .sel(sel[0]), .y(s00));
    vproc_mux2to1 u01 (.a(i2), .b(i3), .sel(sel[0]), .y(s01));
    vproc_mux2to1 u02 (.a(i4), .b(i5), .sel(sel[0]), .y(s02));
    vproc_mux2to1 u03 (.a(i6), .b(i7), .sel(sel[0]), .y(s03));
    vproc_mux2to1 u10 (.a(s00), .b(s01), .sel(sel[1]), .y(s10));
    vproc_mux2to1 u11 (.a(s02), .b(s03), .sel(sel[1]), .y(s11));
    vproc_mux2to1 u20 (.a(s10), .b(s11), .sel(sel[2]), .y(y));
endmodule

// Mux tổng 4 nguồn × 4 bit (chọn đường SEW=8 / 16 / 32); i3 dự phòng.
module vproc_mux4to1_w4 (
    input  wire [3:0] i0,
    input  wire [3:0] i1,
    input  wire [3:0] i2,
    input  wire [3:0] i3,
    input  wire [1:0] sel,
    output wire [3:0] y
);
    assign y = (sel == 2'd0) ? i0 :
                (sel == 2'd1) ? i1 :
                (sel == 2'd2) ? i2 : i3;
endmodule
