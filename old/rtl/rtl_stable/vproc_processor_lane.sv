// Wrapper module: vproc_processor_lane
// Tích hợp các execution units (adder, mul, logic, shifter, compare).
// Nhận operand từ VRF + tín hiệu điều khiển, xuất wb_result được mux theo funct6.
//
// Các tín hiệu shift/compare control được derive nội bộ từ funct6,
// giảm port và tránh mismatch với decoder.
//
// widen_sel (từ FSM counter): chọn result_lo (cycle 1) hay result_hi (cycle 2)
// trong multicycle widening writeback.

module vproc_processor_lane (
    input  [31:0] vs1_data,
    input  [31:0] vs2_data,
    input  [31:0] immediate,
    input  [31:0] rs1_data,

    // Tín hiệu điều khiển (từ ctrl_bus / FSM)
    input  [5:0]  funct6,
    input  [2:0]  sew,
    input  [3:0]  vmask,             // mask predication cho 1 lane (AND wb_result)
    input  [3:0]  v0_carry,          // bit v0 cho ADC/SBC carry-in (khác vmask khi vm=0)
    input  [31:0] v0_merge_bits,     // mask v0 32-bit đã tách cho lane (dùng cho VMERGE)
    input         reverse_sub,       // 1=vrsub.*: minuend/subtrahend đảo so với vsub
    input         sub,               // 0=add, 1=sub (từ decoder is_subtraction)
    input         widen_sel,         // từ FSM: 0=result_lo, 1=result_hi
    input         use_rs1,
    input         use_imm,
    input         is_carry,
    input         is_mask_carry,
    input         is_compare,
    input         minmax_is_min,
    input         minmax_is_unsign,
    input         is_unsigned_vs1,
    input         is_unsigned_vs2,
    input         is_mulh,

    output reg [31:0] wb_result,
    output [3:0]      mask_result_out
);

    // ===== Định nghĩa các mã funct6 =====
    localparam [5:0] VADD    = 6'b000000;
    localparam [5:0] VSUB    = 6'b000010;
    localparam [5:0] VRSUB   = 6'b000011;
    localparam [5:0] VMUL    = 6'b100101;
    localparam [5:0] VMULH   = 6'b100111;
    localparam [5:0] VMULHU  = 6'b100100;
    localparam [5:0] VMULHSU = 6'b100110;
    localparam [5:0] VAND    = 6'b001001;
    localparam [5:0] VOR     = 6'b001010;
    localparam [5:0] VXOR    = 6'b001011;
    localparam [5:0] VSLL    = 6'b010101;
    localparam [5:0] VMERGE  = 6'b010111;
    localparam [5:0] VSRL    = 6'b010000;
    localparam [5:0] VSRA    = 6'b010010;
    localparam [5:0] VMADC   = 6'b010001;
    localparam [5:0] VMSBC   = 6'b010011;
    localparam [5:0] VCMPEQ  = 6'b011000;
    localparam [5:0] VCMPLT  = 6'b011011;
    localparam [5:0] VCMPLTU = 6'b011010;
    localparam [5:0] VMINU   = 6'b000100;
    localparam [5:0] VMIN    = 6'b000101;
    localparam [5:0] VMAXU   = 6'b000110;
    localparam [5:0] VMAX    = 6'b000111;

    // Widening operations
    localparam [5:0] VADDW   = 6'b110001;
    localparam [5:0] VADDWU  = 6'b110000;
    localparam [5:0] VSUBW   = 6'b110011;
    localparam [5:0] VSUBWU  = 6'b110010;
    localparam [5:0] VMULWU  = 6'b111000;
    localparam [5:0] VMULW   = 6'b111011;
    localparam [5:0] VMULWSU = 6'b111010;

    // ===== Derive control từ funct6 =====
    wire shift_right = (funct6 == VSRL) || (funct6 == VSRA);
    wire shift_arith = (funct6 == VSRA);
    wire cmp_is_lt   = (funct6 == VCMPLT) || (funct6 == VCMPLTU);
    wire cmp_is_unsign = (funct6 == VCMPLTU);
    // ===== Operand B mux (đường logic / mul / shift; adder dùng thêm reverse_sub) =====
    reg [31:0] op_b;
    always @(*) begin
        if (use_rs1)
            op_b = rs1_data;
        else if (use_imm)
            op_b = immediate;
        else
            op_b = vs1_data;
    end

    // Adder: mặc định op_a=vs2, op_b=op_b (vs1/rs1/imm) → sub ? vs2-op_b : vs2+op_b
    // reverse_sub: vrsub — đảo minuend/subtrahend (vs1-rs2, imm-rs2, rs1-rs2)
    reg [31:0] add_op_a;
    reg [31:0] add_op_b;
    always @(*) begin
        if (reverse_sub) begin
            if (use_rs1) begin
                add_op_a = rs1_data;
                add_op_b = vs2_data;
            end else if (use_imm) begin
                add_op_a = immediate;
                add_op_b = vs2_data;
            end else begin
                add_op_a = vs1_data;
                add_op_b = vs2_data;
            end
        end else begin
            add_op_a = vs2_data;
            add_op_b = op_b;
        end
    end

    // ===== Output từ các execution units =====
    wire [31:0] adder_lo, adder_hi;
    wire [3:0]  carry_mask_out;
    wire [31:0] mul_lo, mul_hi;
    wire [31:0] and_result, or_result, xor_result;
    wire [31:0] shift_result;
    wire [31:0] merge_result;
    wire [3:0]  cmp_result;
    wire [31:0] minmax_result;

    // ===== Instantiate vproc_adder =====
    vproc_adder adder_inst (
        .op_a          (add_op_a),
        .op_b          (add_op_b),
        .use_carry     (is_carry || is_mask_carry),
        .use_mask_carry(is_mask_carry),
        .carry_in      (v0_carry),
        .sub           (sub),
        .sew           (sew),
        .unsign        (is_unsigned_vs1),
        .result_lo     (adder_lo),
        .result_hi     (adder_hi),
        .carry_mask_out(carry_mask_out)
    );

    // ===== Instantiate vproc_mul =====
    vproc_mul mul_inst (
        .op_a     (vs2_data),
        .op_b     (op_b),
        .sew      (sew),
        .unsign_a (is_unsigned_vs1),
        .unsign_b (is_unsigned_vs2),
        .result_lo(mul_lo),
        .result_hi(mul_hi)
    );

    // ===== Instantiate vproc_logic =====
    vproc_logic logic_inst (
        .op_a      (vs2_data),
        .op_b      (op_b),
        .result_and(and_result),
        .result_or (or_result),
        .result_xor(xor_result)
    );

    // ===== Instantiate vproc_shifter =====
    vproc_shifter shifter_inst (
        .op_in   (vs2_data),
        .shamt_in(op_b),
        .sew     (sew),
        .ctrl    (shift_right),
        .arith   (shift_arith),
        .result  (shift_result)
    );

    // ===== Instantiate vproc_merge_unit =====
    // v0_merge_bits là mask lane đã tách từ v0 128-bit ở top.
    vproc_merge_unit merge_inst (
        .vs1_data (op_b),
        .vs2_data (vs2_data),
        .v0_lane_bits(v0_merge_bits),
        .sew      (sew),
        .merge_out(merge_result)
    );

    // ===== Instantiate vproc_compare =====
    vproc_compare compare_inst (
        .op_a        (vs2_data),
        .op_b        (op_b),
        .sew         (sew),
        .is_less_than(cmp_is_lt),
        .is_unsign   (cmp_is_unsign),
        .cmp_result  (cmp_result)
    );
    // ===== Instantiate vproc_minmax =====
    vproc_minmax minmax_inst (
        .op_a     (vs2_data),
        .op_b     (op_b),
        .sew      (sew),
        .is_min   (minmax_is_min),
        .is_unsign(minmax_is_unsign),
        .result   (minmax_result)
    );

    // ===== Result selection cho widening =====
    // widen_sel = 0: lấy phần lo (normal / widening cycle 1)
    // widen_sel = 1: lấy phần hi (widening cycle 2)
    wire [31:0] result_addsub = widen_sel ? adder_hi : adder_lo;
    wire [31:0] result_mul    = (is_mulh || widen_sel) ? mul_hi : mul_lo;
    assign mask_result_out = is_mask_carry ? carry_mask_out :
                             (is_compare ? cmp_result : 4'b0000);

    // ===== Mux kết quả trước mask theo funct6 =====
    reg [31:0] wb_unmasked;
    always @(*) begin
        case (funct6)
            VADD, VADDW, VADDWU:                wb_unmasked = result_addsub;
            VSUB, VRSUB, VSUBW, VSUBWU:         wb_unmasked = result_addsub;
            VMUL, VMULW, VMULWU, VMULWSU:       wb_unmasked = result_mul;
            VMULH, VMULHU, VMULHSU:             wb_unmasked = result_mul;
            VAND:                               wb_unmasked = and_result;
            VOR:                                wb_unmasked = or_result;
            VXOR:                               wb_unmasked = xor_result;
            VMERGE:                             wb_unmasked = merge_result;
            VSLL:                               wb_unmasked = shift_result;
            VSRL, VSRA:                         wb_unmasked = is_carry ? result_addsub : shift_result;
            VMADC, VMSBC:                       wb_unmasked = is_mask_carry ? {28'b0, carry_mask_out} : 32'b0;
            VCMPEQ, VCMPLT, VCMPLTU:            wb_unmasked = {28'b0, cmp_result};
            VMINU, VMIN, VMAXU, VMAX:           wb_unmasked = minmax_result;
            default:                            wb_unmasked = 32'b0;
        endcase
    end

    // ===== Áp vmask theo sew =====
    // Mapping bit mask:
    //   sew=0 (8b) : dùng vmask[3:0] cho 4 byte
    //   sew=1 (16b): dùng vmask[1:0] cho 2 halfword
    //   sew=2 (32b): dùng vmask[0]
    reg [31:0] lane_mask_32;
    always @(*) begin
        case (sew)
            3'd0:   lane_mask_32 = {{8{vmask[3]}}, {8{vmask[2]}}, {8{vmask[1]}}, {8{vmask[0]}}};
            3'd1:   lane_mask_32 = {{16{vmask[1]}}, {16{vmask[0]}}};
            3'd2:   lane_mask_32 = {32{vmask[0]}};
            default: lane_mask_32 = {32{vmask[0]}};
        endcase
    end

    always @(*) begin
        wb_result = wb_unmasked & lane_mask_32;
    end

endmodule
