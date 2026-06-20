// Simple VCSR: chỉ giữ 3 thanh ghi
//   - vlenb (read-only, hằng)
//   - vl
//   - vtype (lưu 8-bit encoded ở [7:0])
//
// Ghi dữ liệu khi cfg_en = 1 (từ FSM CONFIG).
//
// Đọc theo địa chỉ CSR chuẩn RISC-V V (trường csr 12-bit trong lệnh SYSTEM):
//   vl, vtype, vlenb — cổng csr_addr / csr_rdata (tổ hợp, không đăng ký).

module vproc_vcsr #(
    parameter XLEN   = 32,
    parameter VLENB  = 16  // số byte mỗi vector register (ví dụ 128-bit => 16 byte)
) (
    input                 clk,
    input                 rst_n,
    input                 cfg_en,
    input       [XLEN-1:0] vl_in,
    input       [7:0]     vtype_enc_in,
    input       [11:0]    csr_addr,   // inst[31:20] từ scalar (CSRR*)
    output logic [XLEN-1:0] csr_rdata,
    output reg  [XLEN-1:0] vl_o,
    output reg  [XLEN-1:0] vtype_o,
    output reg  [XLEN-1:0] vlenb_o
);

    // Địa chỉ CSR vector (user-level, spec V)
    localparam logic [11:0] CSR_ADDR_VL    = 12'hC20;
    localparam logic [11:0] CSR_ADDR_VTYPE = 12'hC21;
    localparam logic [11:0] CSR_ADDR_VLENB = 12'hC22;

    always_comb begin
        unique case (csr_addr)
            CSR_ADDR_VL:    csr_rdata = vl_o;
            CSR_ADDR_VTYPE: csr_rdata = vtype_o;
            CSR_ADDR_VLENB: csr_rdata = vlenb_o;
            default:        csr_rdata = {XLEN{1'b0}};
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vl_o     <= {XLEN{1'b0}};
            vtype_o  <= {XLEN{1'b0}};
            vlenb_o  <= VLENB[XLEN-1:0];
        end else begin
            if (cfg_en) begin
                vl_o <= vl_in;
                vtype_o <= {24'd0, vtype_enc_in};
            end
            vlenb_o <= VLENB[XLEN-1:0];
        end
    end

endmodule

