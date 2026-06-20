module register (
    input  logic [31:0] D,
    input  logic        en,
    input  logic        clk,
    input  logic        rst_n,
    output logic [31:0] Q
);

    d_ff DFF0  (.D(D[0]),  .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[0]));
    d_ff DFF1  (.D(D[1]),  .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[1]));
    d_ff DFF2  (.D(D[2]),  .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[2]));
    d_ff DFF3  (.D(D[3]),  .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[3]));
    d_ff DFF4  (.D(D[4]),  .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[4]));
    d_ff DFF5  (.D(D[5]),  .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[5]));
    d_ff DFF6  (.D(D[6]),  .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[6]));
    d_ff DFF7  (.D(D[7]),  .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[7]));
    d_ff DFF8  (.D(D[8]),  .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[8]));
    d_ff DFF9  (.D(D[9]),  .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[9]));
    d_ff DFF10 (.D(D[10]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[10]));
    d_ff DFF11 (.D(D[11]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[11]));
    d_ff DFF12 (.D(D[12]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[12]));
    d_ff DFF13 (.D(D[13]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[13]));
    d_ff DFF14 (.D(D[14]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[14]));
    d_ff DFF15 (.D(D[15]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[15]));
    d_ff DFF16 (.D(D[16]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[16]));
    d_ff DFF17 (.D(D[17]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[17]));
    d_ff DFF18 (.D(D[18]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[18]));
    d_ff DFF19 (.D(D[19]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[19]));
    d_ff DFF20 (.D(D[20]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[20]));
    d_ff DFF21 (.D(D[21]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[21]));
    d_ff DFF22 (.D(D[22]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[22]));
    d_ff DFF23 (.D(D[23]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[23]));
    d_ff DFF24 (.D(D[24]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[24]));
    d_ff DFF25 (.D(D[25]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[25]));
    d_ff DFF26 (.D(D[26]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[26]));
    d_ff DFF27 (.D(D[27]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[27]));
    d_ff DFF28 (.D(D[28]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[28]));
    d_ff DFF29 (.D(D[29]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[29]));
    d_ff DFF30 (.D(D[30]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[30]));
    d_ff DFF31 (.D(D[31]), .clk(clk), .en(en), .rst_n(rst_n), .Q(Q[31]));

endmodule
