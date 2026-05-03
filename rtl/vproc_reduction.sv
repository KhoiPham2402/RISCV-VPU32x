// Reduction unit cho nhóm lệnh vred*.
// - Xử lý tập trung trên 2 bus 128-bit (không tách lane).
// - Dùng 1 thanh ghi tích lũy 32-bit nội bộ (acc_r).
// - Mỗi chu kỳ valid=1: duyệt các phần tử trong chunk 128-bit theo sew,
//   chọn phần tử từ vec0/vec1 theo mask_sel_128, rồi reduce dồn vào acc_r.
// - done=1: chốt kết quả cuối vào result_out và phát wb_valid=1 (1 chu kỳ).
//
// sew:
//   3'd0 -> thao tác theo từng phần tử 8-bit
//   3'd1 -> thao tác theo từng phần tử 16-bit
//   3'd2 -> thao tác 32-bit
//
// operation:
//   4'd0 : RED_SUM
//   4'd1 : RED_MAX   (signed)
//   4'd2 : RED_MAXU  (unsigned)
//   4'd3 : RED_MIN   (signed)
//   4'd4 : RED_MINU  (unsigned)
//   4'd5 : RED_AND
//   4'd6 : RED_OR
//   4'd7 : RED_XOR

module vproc_reduction (
    input         clk,
    input         rst_n,
    input         start,          // bắt đầu lệnh reduction mới
    input         valid,          // chunk 128-bit hiện tại hợp lệ
    input  [127:0] vec0_128,     // nguồn 0
    input  [127:0] vec1_128,     // nguồn 1
    input  [127:0] mask_sel_128, // bit=1 chọn vec1, bit=0 chọn vec0
    input  [2:0]  sew,
    input  [3:0]  operation,
    input         done,        // báo chunk/cuối lệnh: xuất result + wb_valid
    output reg [31:0] result_out,
    output reg        wb_valid
);

    localparam [3:0] RED_SUM  = 4'd0;
    localparam [3:0] RED_MAX  = 4'd1;
    localparam [3:0] RED_MAXU = 4'd2;
    localparam [3:0] RED_MIN  = 4'd3;
    localparam [3:0] RED_MINU = 4'd4;
    localparam [3:0] RED_AND  = 4'd5;
    localparam [3:0] RED_OR   = 4'd6;
    localparam [3:0] RED_XOR  = 4'd7;

    reg [31:0] acc_r;
    reg [31:0] chunk_reduce_next;
    reg [31:0] acc0, acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8;
    reg [31:0] acc9, acc10, acc11, acc12, acc13, acc14, acc15, acc16;
    reg [31:0] e0_u, e1_u, e2_u, e3_u, e4_u, e5_u, e6_u, e7_u;
    reg [31:0] e8_u, e9_u, e10_u, e11_u, e12_u, e13_u, e14_u, e15_u;
    reg [31:0] e0_s, e1_s, e2_s, e3_s, e4_s, e5_s, e6_s, e7_s;
    reg [31:0] e8_s, e9_s, e10_s, e11_s, e12_s, e13_s, e14_s, e15_s;

    always @(*) begin
        acc0  = acc_r;
        acc1  = acc0;
        acc2  = acc0;
        acc3  = acc0;
        acc4  = acc0;
        acc5  = acc0;
        acc6  = acc0;
        acc7  = acc0;
        acc8  = acc0;
        acc9  = acc0;
        acc10 = acc0;
        acc11 = acc0;
        acc12 = acc0;
        acc13 = acc0;
        acc14 = acc0;
        acc15 = acc0;
        acc16 = acc0;

        case (sew)
            3'd0: begin
                e0_u  = mask_sel_128[0]  ? {24'b0, vec1_128[7:0]}      : {24'b0, vec0_128[7:0]};
                e1_u  = mask_sel_128[1]  ? {24'b0, vec1_128[15:8]}     : {24'b0, vec0_128[15:8]};
                e2_u  = mask_sel_128[2]  ? {24'b0, vec1_128[23:16]}    : {24'b0, vec0_128[23:16]};
                e3_u  = mask_sel_128[3]  ? {24'b0, vec1_128[31:24]}    : {24'b0, vec0_128[31:24]};
                e4_u  = mask_sel_128[4]  ? {24'b0, vec1_128[39:32]}    : {24'b0, vec0_128[39:32]};
                e5_u  = mask_sel_128[5]  ? {24'b0, vec1_128[47:40]}    : {24'b0, vec0_128[47:40]};
                e6_u  = mask_sel_128[6]  ? {24'b0, vec1_128[55:48]}    : {24'b0, vec0_128[55:48]};
                e7_u  = mask_sel_128[7]  ? {24'b0, vec1_128[63:56]}    : {24'b0, vec0_128[63:56]};
                e8_u  = mask_sel_128[8]  ? {24'b0, vec1_128[71:64]}    : {24'b0, vec0_128[71:64]};
                e9_u  = mask_sel_128[9]  ? {24'b0, vec1_128[79:72]}    : {24'b0, vec0_128[79:72]};
                e10_u = mask_sel_128[10] ? {24'b0, vec1_128[87:80]}    : {24'b0, vec0_128[87:80]};
                e11_u = mask_sel_128[11] ? {24'b0, vec1_128[95:88]}    : {24'b0, vec0_128[95:88]};
                e12_u = mask_sel_128[12] ? {24'b0, vec1_128[103:96]}   : {24'b0, vec0_128[103:96]};
                e13_u = mask_sel_128[13] ? {24'b0, vec1_128[111:104]}  : {24'b0, vec0_128[111:104]};
                e14_u = mask_sel_128[14] ? {24'b0, vec1_128[119:112]}  : {24'b0, vec0_128[119:112]};
                e15_u = mask_sel_128[15] ? {24'b0, vec1_128[127:120]}  : {24'b0, vec0_128[127:120]};
                e0_s  = mask_sel_128[0]  ? {{24{vec1_128[7]}},   vec1_128[7:0]}      : {{24{vec0_128[7]}},   vec0_128[7:0]};
                e1_s  = mask_sel_128[1]  ? {{24{vec1_128[15]}},  vec1_128[15:8]}     : {{24{vec0_128[15]}},  vec0_128[15:8]};
                e2_s  = mask_sel_128[2]  ? {{24{vec1_128[23]}},  vec1_128[23:16]}    : {{24{vec0_128[23]}},  vec0_128[23:16]};
                e3_s  = mask_sel_128[3]  ? {{24{vec1_128[31]}},  vec1_128[31:24]}    : {{24{vec0_128[31]}},  vec0_128[31:24]};
                e4_s  = mask_sel_128[4]  ? {{24{vec1_128[39]}},  vec1_128[39:32]}    : {{24{vec0_128[39]}},  vec0_128[39:32]};
                e5_s  = mask_sel_128[5]  ? {{24{vec1_128[47]}},  vec1_128[47:40]}    : {{24{vec0_128[47]}},  vec0_128[47:40]};
                e6_s  = mask_sel_128[6]  ? {{24{vec1_128[55]}},  vec1_128[55:48]}    : {{24{vec0_128[55]}},  vec0_128[55:48]};
                e7_s  = mask_sel_128[7]  ? {{24{vec1_128[63]}},  vec1_128[63:56]}    : {{24{vec0_128[63]}},  vec0_128[63:56]};
                e8_s  = mask_sel_128[8]  ? {{24{vec1_128[71]}},  vec1_128[71:64]}    : {{24{vec0_128[71]}},  vec0_128[71:64]};
                e9_s  = mask_sel_128[9]  ? {{24{vec1_128[79]}},  vec1_128[79:72]}    : {{24{vec0_128[79]}},  vec0_128[79:72]};
                e10_s = mask_sel_128[10] ? {{24{vec1_128[87]}},  vec1_128[87:80]}    : {{24{vec0_128[87]}},  vec0_128[87:80]};
                e11_s = mask_sel_128[11] ? {{24{vec1_128[95]}},  vec1_128[95:88]}    : {{24{vec0_128[95]}},  vec0_128[95:88]};
                e12_s = mask_sel_128[12] ? {{24{vec1_128[103]}}, vec1_128[103:96]}   : {{24{vec0_128[103]}}, vec0_128[103:96]};
                e13_s = mask_sel_128[13] ? {{24{vec1_128[111]}}, vec1_128[111:104]}  : {{24{vec0_128[111]}}, vec0_128[111:104]};
                e14_s = mask_sel_128[14] ? {{24{vec1_128[119]}}, vec1_128[119:112]}  : {{24{vec0_128[119]}}, vec0_128[119:112]};
                e15_s = mask_sel_128[15] ? {{24{vec1_128[127]}}, vec1_128[127:120]}  : {{24{vec0_128[127]}}, vec0_128[127:120]};
                case (operation)
                    RED_SUM: begin
                        acc1 = acc0 + e0_u;   acc2 = acc1 + e1_u;   acc3 = acc2 + e2_u;   acc4 = acc3 + e3_u;
                        acc5 = acc4 + e4_u;   acc6 = acc5 + e5_u;   acc7 = acc6 + e6_u;   acc8 = acc7 + e7_u;
                        acc9 = acc8 + e8_u;   acc10 = acc9 + e9_u;  acc11 = acc10 + e10_u; acc12 = acc11 + e11_u;
                        acc13 = acc12 + e12_u; acc14 = acc13 + e13_u; acc15 = acc14 + e14_u; acc16 = acc15 + e15_u;
                    end
                    RED_AND: begin
                        acc1 = acc0 & e0_u;   acc2 = acc1 & e1_u;   acc3 = acc2 & e2_u;   acc4 = acc3 & e3_u;
                        acc5 = acc4 & e4_u;   acc6 = acc5 & e5_u;   acc7 = acc6 & e6_u;   acc8 = acc7 & e7_u;
                        acc9 = acc8 & e8_u;   acc10 = acc9 & e9_u;  acc11 = acc10 & e10_u; acc12 = acc11 & e11_u;
                        acc13 = acc12 & e12_u; acc14 = acc13 & e13_u; acc15 = acc14 & e14_u; acc16 = acc15 & e15_u;
                    end
                    RED_OR: begin
                        acc1 = acc0 | e0_u;   acc2 = acc1 | e1_u;   acc3 = acc2 | e2_u;   acc4 = acc3 | e3_u;
                        acc5 = acc4 | e4_u;   acc6 = acc5 | e5_u;   acc7 = acc6 | e6_u;   acc8 = acc7 | e7_u;
                        acc9 = acc8 | e8_u;   acc10 = acc9 | e9_u;  acc11 = acc10 | e10_u; acc12 = acc11 | e11_u;
                        acc13 = acc12 | e12_u; acc14 = acc13 | e13_u; acc15 = acc14 | e14_u; acc16 = acc15 | e15_u;
                    end
                    RED_XOR: begin
                        acc1 = acc0 ^ e0_u;   acc2 = acc1 ^ e1_u;   acc3 = acc2 ^ e2_u;   acc4 = acc3 ^ e3_u;
                        acc5 = acc4 ^ e4_u;   acc6 = acc5 ^ e5_u;   acc7 = acc6 ^ e6_u;   acc8 = acc7 ^ e7_u;
                        acc9 = acc8 ^ e8_u;   acc10 = acc9 ^ e9_u;  acc11 = acc10 ^ e10_u; acc12 = acc11 ^ e11_u;
                        acc13 = acc12 ^ e12_u; acc14 = acc13 ^ e13_u; acc15 = acc14 ^ e14_u; acc16 = acc15 ^ e15_u;
                    end
                    RED_MAXU: begin
                        acc1 = (acc0 < e0_u) ? e0_u : acc0;   acc2 = (acc1 < e1_u) ? e1_u : acc1;
                        acc3 = (acc2 < e2_u) ? e2_u : acc2;   acc4 = (acc3 < e3_u) ? e3_u : acc3;
                        acc5 = (acc4 < e4_u) ? e4_u : acc4;   acc6 = (acc5 < e5_u) ? e5_u : acc5;
                        acc7 = (acc6 < e6_u) ? e6_u : acc6;   acc8 = (acc7 < e7_u) ? e7_u : acc7;
                        acc9 = (acc8 < e8_u) ? e8_u : acc8;   acc10 = (acc9 < e9_u) ? e9_u : acc9;
                        acc11 = (acc10 < e10_u) ? e10_u : acc10; acc12 = (acc11 < e11_u) ? e11_u : acc11;
                        acc13 = (acc12 < e12_u) ? e12_u : acc12; acc14 = (acc13 < e13_u) ? e13_u : acc13;
                        acc15 = (acc14 < e14_u) ? e14_u : acc14; acc16 = (acc15 < e15_u) ? e15_u : acc15;
                    end
                    RED_MINU: begin
                        acc1 = (acc0 < e0_u) ? acc0 : e0_u;   acc2 = (acc1 < e1_u) ? acc1 : e1_u;
                        acc3 = (acc2 < e2_u) ? acc2 : e2_u;   acc4 = (acc3 < e3_u) ? acc3 : e3_u;
                        acc5 = (acc4 < e4_u) ? acc4 : e4_u;   acc6 = (acc5 < e5_u) ? acc5 : e5_u;
                        acc7 = (acc6 < e6_u) ? acc6 : e6_u;   acc8 = (acc7 < e7_u) ? acc7 : e7_u;
                        acc9 = (acc8 < e8_u) ? acc8 : e8_u;   acc10 = (acc9 < e9_u) ? acc9 : e9_u;
                        acc11 = (acc10 < e10_u) ? acc10 : e10_u; acc12 = (acc11 < e11_u) ? acc11 : e11_u;
                        acc13 = (acc12 < e12_u) ? acc12 : e12_u; acc14 = (acc13 < e13_u) ? acc13 : e13_u;
                        acc15 = (acc14 < e14_u) ? acc14 : e14_u; acc16 = (acc15 < e15_u) ? acc15 : e15_u;
                    end
                    RED_MAX: begin
                        acc1 = ($signed(acc0) < $signed(e0_s)) ? e0_u : acc0;   acc2 = ($signed(acc1) < $signed(e1_s)) ? e1_u : acc1;
                        acc3 = ($signed(acc2) < $signed(e2_s)) ? e2_u : acc2;   acc4 = ($signed(acc3) < $signed(e3_s)) ? e3_u : acc3;
                        acc5 = ($signed(acc4) < $signed(e4_s)) ? e4_u : acc4;   acc6 = ($signed(acc5) < $signed(e5_s)) ? e5_u : acc5;
                        acc7 = ($signed(acc6) < $signed(e6_s)) ? e6_u : acc6;   acc8 = ($signed(acc7) < $signed(e7_s)) ? e7_u : acc7;
                        acc9 = ($signed(acc8) < $signed(e8_s)) ? e8_u : acc8;   acc10 = ($signed(acc9) < $signed(e9_s)) ? e9_u : acc9;
                        acc11 = ($signed(acc10) < $signed(e10_s)) ? e10_u : acc10; acc12 = ($signed(acc11) < $signed(e11_s)) ? e11_u : acc11;
                        acc13 = ($signed(acc12) < $signed(e12_s)) ? e12_u : acc12; acc14 = ($signed(acc13) < $signed(e13_s)) ? e13_u : acc13;
                        acc15 = ($signed(acc14) < $signed(e14_s)) ? e14_u : acc14; acc16 = ($signed(acc15) < $signed(e15_s)) ? e15_u : acc15;
                    end
                    RED_MIN: begin
                        acc1 = ($signed(acc0) < $signed(e0_s)) ? acc0 : e0_u;   acc2 = ($signed(acc1) < $signed(e1_s)) ? acc1 : e1_u;
                        acc3 = ($signed(acc2) < $signed(e2_s)) ? acc2 : e2_u;   acc4 = ($signed(acc3) < $signed(e3_s)) ? acc3 : e3_u;
                        acc5 = ($signed(acc4) < $signed(e4_s)) ? acc4 : e4_u;   acc6 = ($signed(acc5) < $signed(e5_s)) ? acc5 : e5_u;
                        acc7 = ($signed(acc6) < $signed(e6_s)) ? acc6 : e6_u;   acc8 = ($signed(acc7) < $signed(e7_s)) ? acc7 : e7_u;
                        acc9 = ($signed(acc8) < $signed(e8_s)) ? acc8 : e8_u;   acc10 = ($signed(acc9) < $signed(e9_s)) ? acc9 : e9_u;
                        acc11 = ($signed(acc10) < $signed(e10_s)) ? acc10 : e10_u; acc12 = ($signed(acc11) < $signed(e11_s)) ? acc11 : e11_u;
                        acc13 = ($signed(acc12) < $signed(e12_s)) ? acc12 : e12_u; acc14 = ($signed(acc13) < $signed(e13_s)) ? acc13 : e13_u;
                        acc15 = ($signed(acc14) < $signed(e14_s)) ? acc14 : e14_u; acc16 = ($signed(acc15) < $signed(e15_s)) ? acc15 : e15_u;
                    end
                    default: begin
                        acc1 = acc0; acc2 = acc0; acc3 = acc0; acc4 = acc0; acc5 = acc0; acc6 = acc0; acc7 = acc0; acc8 = acc0;
                        acc9 = acc0; acc10 = acc0; acc11 = acc0; acc12 = acc0; acc13 = acc0; acc14 = acc0; acc15 = acc0; acc16 = acc0;
                    end
                endcase
                    chunk_reduce_next = acc16;
            end
            3'd1: begin
                e0_u = mask_sel_128[0] ? {16'b0, vec1_128[15:0]}    : {16'b0, vec0_128[15:0]};
                e1_u = mask_sel_128[1] ? {16'b0, vec1_128[31:16]}   : {16'b0, vec0_128[31:16]};
                e2_u = mask_sel_128[2] ? {16'b0, vec1_128[47:32]}   : {16'b0, vec0_128[47:32]};
                e3_u = mask_sel_128[3] ? {16'b0, vec1_128[63:48]}   : {16'b0, vec0_128[63:48]};
                e4_u = mask_sel_128[4] ? {16'b0, vec1_128[79:64]}   : {16'b0, vec0_128[79:64]};
                e5_u = mask_sel_128[5] ? {16'b0, vec1_128[95:80]}   : {16'b0, vec0_128[95:80]};
                e6_u = mask_sel_128[6] ? {16'b0, vec1_128[111:96]}  : {16'b0, vec0_128[111:96]};
                e7_u = mask_sel_128[7] ? {16'b0, vec1_128[127:112]} : {16'b0, vec0_128[127:112]};
                e0_s = mask_sel_128[0] ? {{16{vec1_128[15]}}, vec1_128[15:0]}    : {{16{vec0_128[15]}}, vec0_128[15:0]};
                e1_s = mask_sel_128[1] ? {{16{vec1_128[31]}}, vec1_128[31:16]}   : {{16{vec0_128[31]}}, vec0_128[31:16]};
                e2_s = mask_sel_128[2] ? {{16{vec1_128[47]}}, vec1_128[47:32]}   : {{16{vec0_128[47]}}, vec0_128[47:32]};
                e3_s = mask_sel_128[3] ? {{16{vec1_128[63]}}, vec1_128[63:48]}   : {{16{vec0_128[63]}}, vec0_128[63:48]};
                e4_s = mask_sel_128[4] ? {{16{vec1_128[79]}}, vec1_128[79:64]}   : {{16{vec0_128[79]}}, vec0_128[79:64]};
                e5_s = mask_sel_128[5] ? {{16{vec1_128[95]}}, vec1_128[95:80]}   : {{16{vec0_128[95]}}, vec0_128[95:80]};
                e6_s = mask_sel_128[6] ? {{16{vec1_128[111]}}, vec1_128[111:96]} : {{16{vec0_128[111]}}, vec0_128[111:96]};
                e7_s = mask_sel_128[7] ? {{16{vec1_128[127]}}, vec1_128[127:112]}: {{16{vec0_128[127]}}, vec0_128[127:112]};
                case (operation)
                    RED_SUM:  begin acc1=acc0+e0_u; acc2=acc1+e1_u; acc3=acc2+e2_u; acc4=acc3+e3_u; acc5=acc4+e4_u; acc6=acc5+e5_u; acc7=acc6+e6_u; acc8=acc7+e7_u; end
                    RED_AND:  begin acc1=acc0&e0_u; acc2=acc1&e1_u; acc3=acc2&e2_u; acc4=acc3&e3_u; acc5=acc4&e4_u; acc6=acc5&e5_u; acc7=acc6&e6_u; acc8=acc7&e7_u; end
                    RED_OR:   begin acc1=acc0|e0_u; acc2=acc1|e1_u; acc3=acc2|e2_u; acc4=acc3|e3_u; acc5=acc4|e4_u; acc6=acc5|e5_u; acc7=acc6|e6_u; acc8=acc7|e7_u; end
                    RED_XOR:  begin acc1=acc0^e0_u; acc2=acc1^e1_u; acc3=acc2^e2_u; acc4=acc3^e3_u; acc5=acc4^e4_u; acc6=acc5^e5_u; acc7=acc6^e6_u; acc8=acc7^e7_u; end
                    RED_MAXU: begin acc1=(acc0<e0_u)?e0_u:acc0; acc2=(acc1<e1_u)?e1_u:acc1; acc3=(acc2<e2_u)?e2_u:acc2; acc4=(acc3<e3_u)?e3_u:acc3; acc5=(acc4<e4_u)?e4_u:acc4; acc6=(acc5<e5_u)?e5_u:acc5; acc7=(acc6<e6_u)?e6_u:acc6; acc8=(acc7<e7_u)?e7_u:acc7; end
                    RED_MINU: begin acc1=(acc0<e0_u)?acc0:e0_u; acc2=(acc1<e1_u)?acc1:e1_u; acc3=(acc2<e2_u)?acc2:e2_u; acc4=(acc3<e3_u)?acc3:e3_u; acc5=(acc4<e4_u)?acc4:e4_u; acc6=(acc5<e5_u)?acc5:e5_u; acc7=(acc6<e6_u)?acc6:e6_u; acc8=(acc7<e7_u)?acc7:e7_u; end
                    RED_MAX:  begin acc1=($signed(acc0)<$signed(e0_s))?e0_u:acc0; acc2=($signed(acc1)<$signed(e1_s))?e1_u:acc1; acc3=($signed(acc2)<$signed(e2_s))?e2_u:acc2; acc4=($signed(acc3)<$signed(e3_s))?e3_u:acc3; acc5=($signed(acc4)<$signed(e4_s))?e4_u:acc4; acc6=($signed(acc5)<$signed(e5_s))?e5_u:acc5; acc7=($signed(acc6)<$signed(e6_s))?e6_u:acc6; acc8=($signed(acc7)<$signed(e7_s))?e7_u:acc7; end
                    RED_MIN:  begin acc1=($signed(acc0)<$signed(e0_s))?acc0:e0_u; acc2=($signed(acc1)<$signed(e1_s))?acc1:e1_u; acc3=($signed(acc2)<$signed(e2_s))?acc2:e2_u; acc4=($signed(acc3)<$signed(e3_s))?acc3:e3_u; acc5=($signed(acc4)<$signed(e4_s))?acc4:e4_u; acc6=($signed(acc5)<$signed(e5_s))?acc5:e5_u; acc7=($signed(acc6)<$signed(e6_s))?acc6:e6_u; acc8=($signed(acc7)<$signed(e7_s))?acc7:e7_u; end
                    default:  begin acc1=acc0; acc2=acc0; acc3=acc0; acc4=acc0; acc5=acc0; acc6=acc0; acc7=acc0; acc8=acc0; end
                endcase
                chunk_reduce_next = acc8;
            end
            default: begin
                e0_u = mask_sel_128[0] ? vec1_128[31:0]   : vec0_128[31:0];
                e1_u = mask_sel_128[1] ? vec1_128[63:32]  : vec0_128[63:32];
                e2_u = mask_sel_128[2] ? vec1_128[95:64]  : vec0_128[95:64];
                e3_u = mask_sel_128[3] ? vec1_128[127:96] : vec0_128[127:96];
                e0_s = e0_u; e1_s = e1_u; e2_s = e2_u; e3_s = e3_u;
                case (operation)
                    RED_SUM:  begin acc1=acc0+e0_u; acc2=acc1+e1_u; acc3=acc2+e2_u; acc4=acc3+e3_u; end
                    RED_AND:  begin acc1=acc0&e0_u; acc2=acc1&e1_u; acc3=acc2&e2_u; acc4=acc3&e3_u; end
                    RED_OR:   begin acc1=acc0|e0_u; acc2=acc1|e1_u; acc3=acc2|e2_u; acc4=acc3|e3_u; end
                    RED_XOR:  begin acc1=acc0^e0_u; acc2=acc1^e1_u; acc3=acc2^e2_u; acc4=acc3^e3_u; end
                    RED_MAXU: begin acc1=(acc0<e0_u)?e0_u:acc0; acc2=(acc1<e1_u)?e1_u:acc1; acc3=(acc2<e2_u)?e2_u:acc2; acc4=(acc3<e3_u)?e3_u:acc3; end
                    RED_MINU: begin acc1=(acc0<e0_u)?acc0:e0_u; acc2=(acc1<e1_u)?acc1:e1_u; acc3=(acc2<e2_u)?acc2:e2_u; acc4=(acc3<e3_u)?acc3:e3_u; end
                    RED_MAX:  begin acc1=($signed(acc0)<$signed(e0_s))?e0_u:acc0; acc2=($signed(acc1)<$signed(e1_s))?e1_u:acc1; acc3=($signed(acc2)<$signed(e2_s))?e2_u:acc2; acc4=($signed(acc3)<$signed(e3_s))?e3_u:acc3; end
                    RED_MIN:  begin acc1=($signed(acc0)<$signed(e0_s))?acc0:e0_u; acc2=($signed(acc1)<$signed(e1_s))?acc1:e1_u; acc3=($signed(acc2)<$signed(e2_s))?acc2:e2_u; acc4=($signed(acc3)<$signed(e3_s))?acc3:e3_u; end
                    default:  begin acc1=acc0; acc2=acc0; acc3=acc0; acc4=acc0; end
                endcase
                chunk_reduce_next = acc4;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_r      <= 32'b0;
            result_out <= 32'b0;
            wb_valid   <= 1'b0;
        end else begin
            wb_valid <= 1'b0;

            if (start)
                acc_r <= 32'b0;

            if (valid)
                acc_r <= chunk_reduce_next;

            if (done) begin
                result_out <= valid ? chunk_reduce_next : acc_r;
                wb_valid   <= 1'b1;
            end
        end
    end

endmodule

