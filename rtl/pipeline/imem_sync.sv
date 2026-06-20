// Synchronous instruction memory.
// Output `instr` is registered — valid one cycle after `pc` is presented.
// flush overrides to NOP; stall holds current output.
// Load hex at elaboration via $readmemh(HEX_FILE, ...).

module imem_sync #(
    parameter int    DEPTH    = 2048,          // words (8 KB default)
    parameter string HEX_FILE = "imem.hex"
) (
    input  logic        clk,
    input  logic        reset,   // active-high synchronous
    input  logic        flush,   // inject NOP (branch/jump taken)
    input  logic        stall,   // hold current output
    input  logic [31:0] pc,
    output logic [31:0] instr    // goes directly to decode stage
);
    localparam int AW = $clog2(DEPTH);
    localparam logic [31:0] NOP = 32'h00000013; // ADDI x0, x0, 0

    logic [31:0] mem [0:DEPTH-1];
    initial $readmemh(HEX_FILE, mem);

    always_ff @(posedge clk) begin
        if (reset || flush)  instr <= NOP;
        else if (!stall)     instr <= mem[pc[AW+1:2]];
    end

endmodule
