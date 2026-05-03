module Regfile (
    input  logic [31:0] D,      // dữ liệu ghi vào (1 data bus)
    input  logic [31:0] en,     // 32-bit enable, mỗi bit enable 1 register
    input  logic        clk,
    input  logic        rst_n,
    
    output logic [31:0] q0,
    output logic [31:0] q1,
    output logic [31:0] q2,
    output logic [31:0] q3,
    output logic [31:0] q4,
    output logic [31:0] q5,
    output logic [31:0] q6,
    output logic [31:0] q7,
    output logic [31:0] q8,
    output logic [31:0] q9,
    output logic [31:0] q10,
    output logic [31:0] q11,
    output logic [31:0] q12,
    output logic [31:0] q13,
    output logic [31:0] q14,
    output logic [31:0] q15,
    output logic [31:0] q16,
    output logic [31:0] q17,
    output logic [31:0] q18,
    output logic [31:0] q19,
    output logic [31:0] q20,
    output logic [31:0] q21,
    output logic [31:0] q22,
    output logic [31:0] q23,
    output logic [31:0] q24,
    output logic [31:0] q25,
    output logic [31:0] q26,
    output logic [31:0] q27,
    output logic [31:0] q28,
    output logic [31:0] q29,
    output logic [31:0] q30,
    output logic [31:0] q31
);

    register R0  (.D(D), .en(en[0]),  .clk(clk), .rst_n(rst_n), .Q(q0));
    register R1  (.D(D), .en(en[1]),  .clk(clk), .rst_n(rst_n), .Q(q1));
    register R2  (.D(D), .en(en[2]),  .clk(clk), .rst_n(rst_n), .Q(q2));
    register R3  (.D(D), .en(en[3]),  .clk(clk), .rst_n(rst_n), .Q(q3));
    register R4  (.D(D), .en(en[4]),  .clk(clk), .rst_n(rst_n), .Q(q4));
    register R5  (.D(D), .en(en[5]),  .clk(clk), .rst_n(rst_n), .Q(q5));
    register R6  (.D(D), .en(en[6]),  .clk(clk), .rst_n(rst_n), .Q(q6));
    register R7  (.D(D), .en(en[7]),  .clk(clk), .rst_n(rst_n), .Q(q7));
    register R8  (.D(D), .en(en[8]),  .clk(clk), .rst_n(rst_n), .Q(q8));
    register R9  (.D(D), .en(en[9]),  .clk(clk), .rst_n(rst_n), .Q(q9));
    register R10 (.D(D), .en(en[10]), .clk(clk), .rst_n(rst_n), .Q(q10));
    register R11 (.D(D), .en(en[11]), .clk(clk), .rst_n(rst_n), .Q(q11));
    register R12 (.D(D), .en(en[12]), .clk(clk), .rst_n(rst_n), .Q(q12));
    register R13 (.D(D), .en(en[13]), .clk(clk), .rst_n(rst_n), .Q(q13));
    register R14 (.D(D), .en(en[14]), .clk(clk), .rst_n(rst_n), .Q(q14));
    register R15 (.D(D), .en(en[15]), .clk(clk), .rst_n(rst_n), .Q(q15));
    register R16 (.D(D), .en(en[16]), .clk(clk), .rst_n(rst_n), .Q(q16));
    register R17 (.D(D), .en(en[17]), .clk(clk), .rst_n(rst_n), .Q(q17));
    register R18 (.D(D), .en(en[18]), .clk(clk), .rst_n(rst_n), .Q(q18));
    register R19 (.D(D), .en(en[19]), .clk(clk), .rst_n(rst_n), .Q(q19));
    register R20 (.D(D), .en(en[20]), .clk(clk), .rst_n(rst_n), .Q(q20));
    register R21 (.D(D), .en(en[21]), .clk(clk), .rst_n(rst_n), .Q(q21));
    register R22 (.D(D), .en(en[22]), .clk(clk), .rst_n(rst_n), .Q(q22));
    register R23 (.D(D), .en(en[23]), .clk(clk), .rst_n(rst_n), .Q(q23));
    register R24 (.D(D), .en(en[24]), .clk(clk), .rst_n(rst_n), .Q(q24));
    register R25 (.D(D), .en(en[25]), .clk(clk), .rst_n(rst_n), .Q(q25));
    register R26 (.D(D), .en(en[26]), .clk(clk), .rst_n(rst_n), .Q(q26));
    register R27 (.D(D), .en(en[27]), .clk(clk), .rst_n(rst_n), .Q(q27));
    register R28 (.D(D), .en(en[28]), .clk(clk), .rst_n(rst_n), .Q(q28));
    register R29 (.D(D), .en(en[29]), .clk(clk), .rst_n(rst_n), .Q(q29));
    register R30 (.D(D), .en(en[30]), .clk(clk), .rst_n(rst_n), .Q(q30));
    register R31 (.D(D), .en(en[31]), .clk(clk), .rst_n(rst_n), .Q(q31));

endmodule
