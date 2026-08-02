// Vector instruction decoder – đồng bộ syntax với các module vproc_* (wire/reg, always_comb)
// - Lệnh config: opcode = OP-V (0x57) và funct3 = 3'b111 (vsetvl / vsetvli).
// - Output gói gọn trong 1 tín hiệu đa bit ctrl_bus làm input cho FIFO phía sau.
// - Đồng thời giải mã và đưa ra trường vtype encoded (từ immediate của lệnh config).
//
// Mặc định CTRL_WIDTH = 49 để chứa đầy đủ vtype[7:0] + control + cfg_is_vsetivli[48]:
// Layout ctrl_bus (LSB first):
//   [4:0]    vs1_addr
//   [9:5]    vs2_addr
//   [14:10]  vd_addr
//   [20:15]  funct6
//   [21]     is_widen
//   [22]     is_unsigned_vs1
//   [23]     is_unsigned_vs2
//   [24]     is_subtraction
//   [25]     is_immediate
//   [26]     is_rs1
//   [27]     is_mulh
//   [28]     is_config     (vector op + funct3 == 111)
//   [29]     is_vector     (opcode = OP-V)
//   [30]     cfg_is_vsetvli (1 nếu lệnh config lấy vtype từ immediate)
//   [31]     vm bit từ instruction[25]
//   [39:32]  vtype_enc     (8-bit: {vma, vta, vsew[2:0], vlmul[2:0]})
//   [40]     is_carry       (vadc / vsbc)
//   [41]     is_mask_carry  (vmadc / vmsbc)
//   [42]     is_masking     (toàn bộ lệnh tạo mask)
//   [43]     is_final_masking (lệnh cần pha FINAL_MASKING để commit buffer)
//   [44]     is_reverse_sub (vrsub.*: cùng sub=1, đảo minuend/subtrahend vào adder)
//   [45]     minmax_is_min  (1=min, 0=max)
//   [46]     minmax_is_unsign (1=unsigned, 0=signed)
//   [47]     is_reduction    (vred*)
//   [48]     cfg_is_vsetivli (1 nếu AVL là uimm5 = vs1_addr[4:0], không phải rs1_data)

module vproc_vdecoder #(
    parameter BASE_ADDR  = 5,
    parameter CTRL_WIDTH = 49
) (
    input  [31:0] instruction,
    input  [31:0] rs2_data,   // dữ liệu scalar rs2 (dùng cho vsetvl đọc vtype từ rs2, nếu cần ở block sau)

    // 1 tín hiệu đa bit làm input cho FIFO phía sau
    output [CTRL_WIDTH-1:0] ctrl_bus,
    output [31:0]           imm_out,   // immediate đã sign-extend từ instruction[19:15]

    // valid = 1 khi có lệnh vector hoặc config hợp lệ, dùng để push ctrl_bus vào FIFO
    output valid
);

    wire [6:0]  opcode    = instruction[6:0];
    wire [2:0]  funct3    = instruction[14:12];
    wire [5:0]  funct6    = instruction[31:26];
    wire [4:0]  vs1_raw   = instruction[19:15];
    wire [4:0]  vs2_raw   = instruction[24:20];
    wire [4:0]  vd_raw    = instruction[11:7];
    // vsetvli immediate dùng zimm[10:0] ở instruction[30:20]
    // zimm[7:0] chứa vtype_enc = {vma, vta, vsew[2:0], vlmul[2:0]}
    wire [10:0] zimm11    = instruction[30:20];
    wire [7:0]  vtype_imm = zimm11[7:0];

    localparam [6:0] OPCODE_OPV = 7'b101_0111;  // OP-V
    localparam [2:0] F3_CONFIG = 3'b111;       // lệnh config

    // ALU operation codes (funct6)
    localparam [5:0] VADD    = 6'b000000;
    localparam [5:0] VSUB    = 6'b000010;
    localparam [5:0] VRSUB   = 6'b000011;  // vrsub.vv / .vx / .vi — trừ với minuend/subtrahend đảo
    localparam [5:0] VADDW   = 6'b110001;
    localparam [5:0] VADDWU  = 6'b110000;
    localparam [5:0] VSUBW   = 6'b110011;
    localparam [5:0] VSUBWU  = 6'b110010;
    localparam [5:0] VMUL    = 6'b100101;
    localparam [5:0] VMULH   = 6'b100111;
    localparam [5:0] VMULHU  = 6'b100100;
    localparam [5:0] VMULHSU = 6'b100110;
    localparam [5:0] VMULW   = 6'b111011;
    localparam [5:0] VMULWSU = 6'b111010;
    localparam [5:0] VMULWU  = 6'b111000;
    localparam [5:0] VAND    = 6'b001001;
    localparam [5:0] VOR     = 6'b001010;
    localparam [5:0] VXOR    = 6'b001011;
    localparam [5:0] VSLL    = 6'b010101;
    localparam [5:0] VSRL    = 6'b010000;
    localparam [5:0] VSRA    = 6'b010010;
    localparam [5:0] VADC    = 6'b010000;
    localparam [5:0] VSBC    = 6'b010010;
    localparam [5:0] VMADC   = 6'b010001;
    localparam [5:0] VMSBC   = 6'b010011;
    localparam [5:0] VCMPEQ  = 6'b011000;
    localparam [5:0] VCMPLT  = 6'b011011;  // thêm mã funct6 cho compare less than
    localparam [5:0] VCMPLTU = 6'b011010;  // thêm mã funct6 cho compare less than unsigned
    localparam [5:0] VMINU   = 6'b000100;
    localparam [5:0] VMIN    = 6'b000101;
    localparam [5:0] VMAXU   = 6'b000110;
    localparam [5:0] VMAX    = 6'b000111;
    localparam [5:0] VREDSUM = 6'b000000;  // RVV 1.0 §14.1: funct6[5:3]=000, funct3=010 (OPMVV)
    localparam [5:0] VREDAND = 6'b000001;
    localparam [5:0] VREDOR  = 6'b000010;
    localparam [5:0] VREDXOR = 6'b000011;
    localparam [5:0] VREDMINU= 6'b000100;
    localparam [5:0] VREDMIN = 6'b000101;
    localparam [5:0] VREDMAXU= 6'b000110;
    localparam [5:0] VREDMAX = 6'b000111;

    // funct3: 000 OPIVV, 011 OPIVI, 100 OPIVX, 111 config
    wire is_vector = (opcode == OPCODE_OPV);
    wire is_config = is_vector && (funct3 == F3_CONFIG);
    wire vm_bit    = instruction[25];
    // Phân loại 3 loại lệnh config (RVV 1.0):
    //   - vsetvli  [31]=0         : vtype từ zimm[10:0]=inst[30:20], AVL từ rs1.
    //   - vsetivli [31:30]=11     : vtype từ zimm[9:0]=inst[29:20], AVL là uimm5=inst[19:15].
    //   - vsetvl   [31]=1,[30]=0  : vtype từ rs2_data, AVL từ rs1.
    // cfg_is_vsetvli=1 cho cả vsetvli và vsetivli vì cả hai đều lấy vtype từ immediate.
    // cfg_is_vsetivli=1 thêm thông tin AVL là immediate (vs1_addr[4:0]), không phải giá trị rs1.
    wire cfg_is_vsetivli = is_config && (instruction[31:30] == 2'b11);
    wire cfg_is_vsetvli  = is_config && ((instruction[31] == 1'b0) || cfg_is_vsetivli);
    wire cfg_is_vsetvl   = is_config && !cfg_is_vsetvli;

    reg is_widen;
    reg is_unsigned_vs1;
    reg is_unsigned_vs2;
    reg is_subtraction;
    reg is_mulh;
    reg is_carry;
    reg is_mask_carry;
    reg is_masking;
    reg is_final_masking;
    reg is_reverse_sub;
    reg minmax_is_min;
    reg minmax_is_unsign;
    reg is_reduction;

    always_comb begin
        case (funct6)
            VADDW, VADDWU, VSUBW, VSUBWU, VMULWU, VMULW, VMULWSU: is_widen = 1'b1;
            default:                      is_widen = 1'b0;
        endcase
    end

    always_comb begin
        case (funct6)
            VSUB, VRSUB, VSUBW, VSUBWU, VSBC, VMSBC: is_subtraction = 1'b1;
            default:                                 is_subtraction = 1'b0;
        endcase
    end

    always_comb begin
        is_reverse_sub = (funct6 == VRSUB);
    end
    always_comb begin
        case (funct6)
            VMINU, VMIN: minmax_is_min = is_vector && !is_config;
            VMAXU, VMAX: minmax_is_min = 1'b0;
            default:     minmax_is_min = 1'b0;
        endcase
    end
    always_comb begin
        case (funct6)
            VMINU, VMAXU: minmax_is_unsign = is_vector && !is_config;
            VMIN, VMAX:   minmax_is_unsign = 1'b0;
            default:      minmax_is_unsign = 1'b0;
        endcase
    end
    always_comb begin
        case (funct6)
            VADDWU, VSUBWU, VMULHU, VMULWU: is_unsigned_vs1 = 1'b1;  // vwmulu: vs1 unsigned
            default:                        is_unsigned_vs1 = 1'b0;
        endcase
    end

    always_comb begin
        case (funct6)
            VADDWU, VSUBWU, VMULHU, VMULHSU, VMULWU: is_unsigned_vs2 = 1'b1;  // vwmulu/vwmulsu: vs2 unsigned
            default:                                         is_unsigned_vs2 = 1'b0;
        endcase
    end

    always_comb begin
        case (funct6)
            VMULH, VMULHU, VMULHSU: is_mulh = 1'b1;
            default:                is_mulh = 1'b0;
        endcase
    end
    // Nhóm add/sub có carry-in từ mask register: vadc / vsbc.
    always_comb begin
        case (funct6)
            VADC, VSBC: is_carry = is_vector && !is_config && (vm_bit == 1'b0) && (funct3 != 3'b011);
            default:    is_carry = 1'b0;
        endcase
    end

    // Nhóm xuất mask carry/borrow: vmadc / vmsbc.
    always_comb begin
        case (funct6)
            VMADC, VMSBC: is_mask_carry = is_vector && !is_config && (vm_bit == 1'b0) && (funct3 != 3'b011);
            default:      is_mask_carry = 1'b0;
        endcase
    end
    // Nhóm lệnh tạo mask (ghi kết quả dạng mask):
    // - compare mask: vmseq/vmslt/vmsltu (map vào VCMPEQ/VCMPLT/VCMPLTU)
    // - carry/borrow mask: vmadc/vmsbc
    always_comb begin
        case (funct6)
            VCMPEQ, VCMPLT, VCMPLTU: is_masking = is_vector && !is_config;
            VMADC, VMSBC:            is_masking = is_vector && !is_config && (vm_bit == 1'b0) && (funct3 != 3'b011);
            default:                 is_masking = 1'b0;
        endcase
    end
    // Lệnh có commit pha cuối từ mask buffer.
    always_comb begin
        case (funct6)
            VCMPEQ, VCMPLT, VCMPLTU: is_final_masking = is_vector && !is_config;
            VMADC, VMSBC:            is_final_masking = is_vector && !is_config && (vm_bit == 1'b0) && (funct3 != 3'b011);
            default:                 is_final_masking = 1'b0;
        endcase
    end
    // RVV 1.0 §14.1: reductions use funct3=010 (OPMVV) + funct6[5:3]=000.
    // Cannot use case(funct6) because funct6=000000 collides with VADD (OPIVV).
    always_comb begin
        is_reduction = is_vector && !is_config && (funct3 == 3'b010) && (funct6[5:3] == 3'b000);
    end
    wire is_immediate    = (funct3 == 3'b011);
    // OPIVX (100): vadd.vx, vsub.vx, vsll.vx, etc.
    // OPMVX (110): vmul.vx, vmulh.vx, vmulhu.vx, vmulhsu.vx
    wire is_rs1          = (funct3 == 3'b100) || (funct3 == 3'b110);
    // vtype_enc 8-bit: chọn nguồn từ immediate hoặc rs2_data[7:0].
    wire [7:0] vtype_enc = cfg_is_vsetvli ? vtype_imm :
                           (cfg_is_vsetvl ? rs2_data[7:0] : 8'd0);
    // Địa chỉ cắt theo BASE_ADDR (thường 5)
    wire [BASE_ADDR-1:0] vs1_addr = vs1_raw[BASE_ADDR-1:0];
    wire [BASE_ADDR-1:0] vs2_addr = vs2_raw[BASE_ADDR-1:0];
    wire [BASE_ADDR-1:0] vd_addr  = vd_raw[BASE_ADDR-1:0];

    // Gói toàn bộ vào ctrl_bus cho FIFO
    assign ctrl_bus = {
        {CTRL_WIDTH-49{1'b0}},  // nếu CTRL_WIDTH > 49 thì padding ở bit cao
        cfg_is_vsetivli,        // [48] — AVL là uimm5 = vs1_addr[4:0], không phải rs1_data
        is_reduction,           // [47]
        minmax_is_unsign,       // [46]
        minmax_is_min,          // [45]
        is_reverse_sub,         // [44]
        is_final_masking,       // [43]
        is_masking,             // [42]
        is_mask_carry,          // [41]
        is_carry,               // [40]
        vtype_enc,              // [39:32] – vtype 8-bit encoded
        vm_bit,                 // [31]
        cfg_is_vsetvli,         // [30]
        is_vector,              // [29]
        is_config,              // [28]
        is_mulh,                // [27]
        is_rs1,                 // [26]
        is_immediate,           // [25]
        is_subtraction,         // [24]
        is_unsigned_vs2,        // [23]
        is_unsigned_vs1,        // [22]
        is_widen,               // [21]
        funct6,                 // [20:15]
        vd_addr,                // [14:10]
        vs2_addr,               // [9:5]
        vs1_addr                // [4:0]
    };

    // OPIVI dùng immediate 5-bit signed tại instruction[19:15].
    // Luôn decode sẵn để FIFO lưu cùng ctrl/rs1; datapath chỉ dùng khi is_immediate=1.
    assign imm_out = {{27{instruction[19]}}, instruction[19:15]};

    assign valid = is_vector;

endmodule
