// Module combine kết quả compare từ 4 lane, mỗi lane đưa vào 4 bit
// kết quả (giống output của vproc_compare).
//
// Ý tưởng:
//   - input: cmp0..cmp3 là kết quả 4-bit của 4 lane:
//       + với sew = 0: chỉ dùng cmpX[0] (so sánh 32-bit)
//       + với sew = 1: dùng cmpX[1:0]  (2 phần tử 16-bit)
//       + với sew = 2: dùng cmpX[3:0]  (4 phần tử  8-bit)
//   - output: một bus duy nhất cmp_eq_out[15:0] chứa toàn bộ bit compare
//     của 4 lane, được "dãn ra" theo sew.
//
// Mapping bit kết quả (cmp_eq_out):
//   - sew = 0 (32-bit):
//       cmp_eq_out[0] : lane 0 (cmp0[0])
//       cmp_eq_out[1] : lane 1 (cmp1[0])
//       cmp_eq_out[2] : lane 2 (cmp2[0])
//       cmp_eq_out[3] : lane 3 (cmp3[0])
//       [15:4] = 0
//   - sew = 1 (16-bit):
//       lane 0: cmp_eq_out[1:0]  = cmp0[1:0]
//       lane 1: cmp_eq_out[3:2]  = cmp1[1:0]
//       lane 2: cmp_eq_out[5:4]  = cmp2[1:0]
//       lane 3: cmp_eq_out[7:6]  = cmp3[1:0]
//       [15:8] = 0
//   - sew = 2 (8-bit):
//       lane 0: cmp_eq_out[3:0]    = cmp0[3:0]
//       lane 1: cmp_eq_out[7:4]    = cmp1[3:0]
//       lane 2: cmp_eq_out[11:8]   = cmp2[3:0]
//       lane 3: cmp_eq_out[15:12]  = cmp3[3:0]
//
// Viết theo Verilog cũ, behavioral, thân thiện FPGA.

module vproc_compare_combine (
    input  [3:0] cmp0,   // kết quả 4-bit từ lane 0
    input  [3:0] cmp1,   // kết quả 4-bit từ lane 1
    input  [3:0] cmp2,   // kết quả 4-bit từ lane 2
    input  [3:0] cmp3,   // kết quả 4-bit từ lane 3
    input  [2:0] sew,
    output [15:0] cmp_eq_out
);

    reg [15:0] cmp_eq_out_r;
    assign cmp_eq_out = cmp_eq_out_r;

    always_comb begin
        // mặc định
        cmp_eq_out_r = 16'b0;

        case (sew)
            3'd0: begin
                // 32-bit: mỗi lane 1 bit
                cmp_eq_out_r[0] = cmp0[0];
                cmp_eq_out_r[1] = cmp1[0];
                cmp_eq_out_r[2] = cmp2[0];
                cmp_eq_out_r[3] = cmp3[0];
            end

            3'd1: begin
                // 2x16-bit per lane, 4 lane -> 8 bit
                // lane 0
                cmp_eq_out_r[1:0] = cmp0[1:0];
                // lane 1
                cmp_eq_out_r[3:2] = cmp1[1:0];
                // lane 2
                cmp_eq_out_r[5:4] = cmp2[1:0];
                // lane 3
                cmp_eq_out_r[7:6] = cmp3[1:0];
            end

            3'd2: begin
                // 4x8-bit per lane, 4 lane -> 16 bit
                // lane 0
                cmp_eq_out_r[3:0]   = cmp0[3:0];
                // lane 1
                cmp_eq_out_r[7:4]   = cmp1[3:0];
                // lane 2
                cmp_eq_out_r[11:8]  = cmp2[3:0];
                // lane 3
                cmp_eq_out_r[15:12] = cmp3[3:0];
            end

            default: begin
                cmp_eq_out_r = 16'b0;
            end
        endcase
    end

endmodule

