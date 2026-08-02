// FIFO for ctrl_bus + rs1_data + imm, parameterised.
// - Push: push_valid / full (stall when full).
// - Pop:  data_valid / pop_ready (FSM signals ready to accept).
//
// No forwarding bypass — all outputs are purely registered.
// This eliminates the 143-node combinational loop that limited Fmax to 16.7 MHz:
//   push_valid -> forwarding -> fifo_full -> vpu_ready -> push_valid
// Cost: 1 extra dispatch-latency cycle when FIFO was previously empty (negligible
// because the FSM already takes multiple cycles per vector operation).

module vproc_fifo #(
    parameter CTRL_WIDTH = 40,
    parameter RS1_WIDTH  = 32,
    parameter IMM_WIDTH  = 32,
    parameter DEPTH      = 8,
    parameter ADDR_W     = 3    // log2(DEPTH)
) (
    input                      clk,
    input                      rst_n,

    // Push (from decoder / issue)
    input                      push_valid,
    input  [CTRL_WIDTH-1:0]    ctrl_in,
    input  [RS1_WIDTH-1:0]     rs1_in,
    input  [IMM_WIDTH-1:0]     imm_in,
    output                     full,

    // Pop (to FSM / execute)
    output [CTRL_WIDTH-1:0]    ctrl_out,
    output [RS1_WIDTH-1:0]     rs1_out,
    output [IMM_WIDTH-1:0]     imm_out,
    output                     data_valid,
    input                      pop_ready
);

    localparam ENTRY_W = CTRL_WIDTH + RS1_WIDTH + IMM_WIDTH;

    wire [ENTRY_W-1:0] din  = {imm_in, rs1_in, ctrl_in};
    wire [ENTRY_W-1:0] dout;

    assign ctrl_out = dout[CTRL_WIDTH-1:0];
    assign rs1_out  = dout[CTRL_WIDTH + RS1_WIDTH - 1 : CTRL_WIDTH];
    assign imm_out  = dout[ENTRY_W-1 : CTRL_WIDTH + RS1_WIDTH];

    reg [ENTRY_W-1:0] mem [0:DEPTH-1];
    reg [ADDR_W:0]    count;
    reg [ADDR_W-1:0]  wr_ptr;
    reg [ADDR_W-1:0]  rd_ptr;

    wire empty    = (count == {(ADDR_W+1){1'b0}});
    wire is_full  = (count == DEPTH);

    wire wr_en       = push_valid && !is_full;
    wire pop_consume = pop_ready  && !empty;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            count  <= {(ADDR_W+1){1'b0}};
            wr_ptr <= {ADDR_W{1'b0}};
            rd_ptr <= {ADDR_W{1'b0}};
        end else begin
            if (wr_en) begin
                mem[wr_ptr] <= din;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            if (pop_consume) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
            case ({wr_en, pop_consume})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

    assign full       = is_full;
    assign data_valid = !empty;
    assign dout       = mem[rd_ptr];

endmodule
