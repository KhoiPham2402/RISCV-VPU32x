// Vector register file 32-bit, ghép từ 4 bank 8-bit
// - Mỗi bank 8-bit có 2 cổng đọc (vs1, vs2) và 1 cổng ghi (vd)
// - write_en[3:0]: enable ghi theo từng bank 8-bit
// - Data ghi 32-bit được chia thành 4 lane 8-bit

module vproc_vregfile #(
    parameter NUM_REGS   = 32,
    parameter ADDR_WIDTH = 5     // log2(NUM_REGS) = 5 cho 32 regs
) (
    input                   clk,
    input                   rst_n,

    // địa chỉ đọc/ghi vector register
    input  [ADDR_WIDTH-1:0] vs1,    // read port 1
    input  [ADDR_WIDTH-1:0] vs2,    // read port 2
    input  [ADDR_WIDTH-1:0] vd,     // write port

    // enable ghi theo từng lane 8-bit
    input  [3:0]            write_en,

    // dữ liệu ghi 32-bit (4 lane 8-bit)
    input  [31:0]           wdata,

    // dữ liệu đọc 32-bit (ghép từ 4 output 8-bit)
    output [31:0]           rs1_data,
    output [31:0]           rs2_data,
    output [31:0]           mask_data  // v0 đủ 32 bit/lane (ghép mask 128b ở wrapper)
);

    // 4 bank 8-bit: mỗi bank lưu 1 lane của vector register
    reg [7:0] bank0 [0:NUM_REGS-1];  // bit [7:0]
    reg [7:0] bank1 [0:NUM_REGS-1];  // bit [15:8]
    reg [7:0] bank2 [0:NUM_REGS-1];  // bit [23:16]
    reg [7:0] bank3 [0:NUM_REGS-1];  // bit [31:24]

    integer i;

    // ghi đồng bộ theo clock, async reset về 0
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_REGS; i = i + 1) begin
                bank0[i] <= 8'b0;
                bank1[i] <= 8'b0;
                bank2[i] <= 8'b0;
                bank3[i] <= 8'b0;
            end
        end else begin
            // ghi từng lane nếu write_en tương ứng được bật
            if (write_en[0]) bank0[vd] <= wdata[7:0];
            if (write_en[1]) bank1[vd] <= wdata[15:8];
            if (write_en[2]) bank2[vd] <= wdata[23:16];
            if (write_en[3]) bank3[vd] <= wdata[31:24];
        end
    end

    // đọc async: mỗi bank có 2 cổng đọc (vs1, vs2)
    assign rs1_data[7:0]   = bank0[vs1];
    assign rs1_data[15:8]  = bank1[vs1];
    assign rs1_data[23:16] = bank2[vs1];
    assign rs1_data[31:24] = bank3[vs1];

    assign rs2_data[7:0]   = bank0[vs2];
    assign rs2_data[15:8]  = bank1[vs2];
    assign rs2_data[23:16] = bank2[vs2];
    assign rs2_data[31:24] = bank3[vs2];

    assign mask_data[7:0]    = bank0[0];
    assign mask_data[15:8]  = bank1[0];
    assign mask_data[23:16] = bank2[0];
    assign mask_data[31:24] = bank3[0];

endmodule

