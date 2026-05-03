// VRF address generator (minimal logic):
// - FSM/datapath bên ngoài điều khiển bằng 2 enable tách riêng:
//   + s_offset_enable: tăng offset cho source address (vs1/vs2)
//   + d_offset_enable: tăng offset cho destination address (vd)
// - offset_clear reset cả hai offset khi về IDLE.

module vproc_vrf_addr_gen #(
    parameter ADDR_WIDTH = 5
) (
    input                   clk,
    input                   rst_n,
    input                   s_offset_enable,
    input                   d_offset_enable,
    input                   offset_clear,
    input  [ADDR_WIDTH-1:0] vs1_base,
    input  [ADDR_WIDTH-1:0] vs2_base,
    input  [ADDR_WIDTH-1:0] vd_base,
    output [ADDR_WIDTH-1:0] vs1_addr,
    output [ADDR_WIDTH-1:0] vs2_addr,
    output [ADDR_WIDTH-1:0] vd_addr
);

    reg [ADDR_WIDTH-1:0] s_offset_r;
    reg [ADDR_WIDTH-1:0] d_offset_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_offset_r <= {ADDR_WIDTH{1'b0}};
        end else if (offset_clear) begin
            s_offset_r <= {ADDR_WIDTH{1'b0}};
        end else if (s_offset_enable) begin
            s_offset_r <= s_offset_r + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d_offset_r <= {ADDR_WIDTH{1'b0}};
        end else if (offset_clear) begin
            d_offset_r <= {ADDR_WIDTH{1'b0}};
        end else if (d_offset_enable) begin
            d_offset_r <= d_offset_r + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
        end
    end

    assign vs1_addr = vs1_base + s_offset_r[ADDR_WIDTH-1:0];
    assign vs2_addr = vs2_base + s_offset_r[ADDR_WIDTH-1:0];
    assign vd_addr  = vd_base  + d_offset_r[ADDR_WIDTH-1:0];

endmodule

