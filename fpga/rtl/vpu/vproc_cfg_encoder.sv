// Config Encoder – giải mã vtype_enc và tính vl, vlmax cho VPU.
//
// vtype_enc layout (theo RVV spec):
//   [2:0]  vlmul  – 000=1, 001=2, 010=4, 011=8, 111=1/2, 110=1/4, 101=1/8, 100=reserved
//   [5:3]  vsew   – 000=8b, 001=16b, 010=32b, 011+=reserved (ELEN=32)
//   [6]    vta    – tail agnostic
//   [7]    vma    – mask agnostic
//
// avl (Application Vector Length) = rs1_data.
//   avl = 0 → vl = vlmax (convention rs1=x0 trong vsetvli/vsetvl).
//   avl > 0 → vl = min(avl, vlmax).
//
// sew output cho lane modules theo RVV: 0 = 8b, 1 = 16b, 2 = 32b.

module vproc_cfg_encoder #(
    parameter VLEN = 128,
    parameter ELEN = 32
) (
    input  [7:0]  vtype_enc,
    input  [31:0] avl,

    output [31:0] vl,
    output [31:0] vlmax,
    output [31:0] avl_remain, // avl > vlmax ? avl - vlmax : 0
    output [2:0]  sew,        // cho adder/mul/shifter: 0=8b, 1=16b, 2=32b
    output        vill        // cấu hình không hợp lệ
);

    wire [2:0] vlmul_f = vtype_enc[2:0];
    wire [2:0] vsew_f  = vtype_enc[5:3];

    // ── Step 1: số phần tử trên mỗi thanh ghi = VLEN / SEW ──
    reg [7:0] elem_per_reg;
    always @(*) begin
        case (vsew_f)
            3'd0: elem_per_reg = VLEN / 8;    // SEW = 8
            3'd1: elem_per_reg = VLEN / 16;   // SEW = 16
            3'd2: elem_per_reg = VLEN / 32;   // SEW = 32
            default: elem_per_reg = 8'd0;
        endcase
    end

    // ── Step 2: VLMAX = elem_per_reg × LMUL (dùng shift vì LMUL luôn là lũy thừa 2) ──
    reg [10:0] vlmax_r;
    always @(*) begin
        case (vlmul_f)
            3'b000: vlmax_r = {3'b0, elem_per_reg};          // ×1
            3'b001: vlmax_r = {2'b0, elem_per_reg, 1'b0};    // ×2
            3'b010: vlmax_r = {1'b0, elem_per_reg, 2'b0};    // ×4
            3'b011: vlmax_r = {elem_per_reg, 3'b0};           // ×8
            3'b111: vlmax_r = {4'b0, elem_per_reg[7:1]};      // ×1/2
            3'b110: vlmax_r = {5'b0, elem_per_reg[7:2]};      // ×1/4
            3'b101: vlmax_r = {6'b0, elem_per_reg[7:3]};      // ×1/8
            default: vlmax_r = 11'd0;                          // reserved
        endcase
    end

    // ── Step 3: kiểm tra cấu hình hợp lệ ──
    // Ràng buộc RVV: LMUL ≥ SEW / ELEN.  Với ELEN = 32:
    //   SEW = 8  → LMUL ≥ 1/4   (cấm 1/8)
    //   SEW = 16 → LMUL ≥ 1/2   (cấm 1/4, 1/8)
    //   SEW = 32 → LMUL ≥ 1     (cấm mọi fractional)
    reg vill_r;
    always @(*) begin
        vill_r = 1'b0;

        if (vsew_f > 3'd2) begin
            vill_r = 1'b1;
        end else if (vlmul_f == 3'b100) begin
            vill_r = 1'b1;
        end else begin
            case (vsew_f)
                3'd0: begin // SEW = 8
                    if (vlmul_f == 3'b101)
                        vill_r = 1'b1;
                end
                3'd1: begin // SEW = 16
                    if (vlmul_f == 3'b101 || vlmul_f == 3'b110)
                        vill_r = 1'b1;
                end
                3'd2: begin // SEW = 32
                    if (vlmul_f[2])
                        vill_r = 1'b1;
                end
                default: vill_r = 1'b1;
            endcase
        end
    end

    // ── Step 4: sew cho lane modules (giữ đúng mã vsew RVV) ──
    reg [2:0] sew_r;
    always @(*) begin
        case (vsew_f)
            3'd0: sew_r = 3'd0;   // SEW = 8
            3'd1: sew_r = 3'd1;   // SEW = 16
            3'd2: sew_r = 3'd2;   // SEW = 32
            default: sew_r = 3'd0;
        endcase
    end

    // ── Outputs ──
    wire [31:0] vlmax_ext = {21'd0, vlmax_r};

    assign vlmax = vlmax_ext;
    assign sew   = sew_r;
    assign vill  = vill_r;

    // vl: nếu illegal → 0, nếu avl=0 (rs1=x0) → vlmax, ngược lại min(avl, vlmax)
    assign vl = vill_r          ? 32'd0      :
                (avl == 32'd0)  ? vlmax_ext  :
                (avl < vlmax_ext) ? avl      : vlmax_ext;

    assign avl_remain = (avl > vlmax_ext) ? (avl - vlmax_ext) : 32'd0;

endmodule
