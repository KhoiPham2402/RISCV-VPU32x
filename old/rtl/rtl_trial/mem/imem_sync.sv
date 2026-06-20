// =============================================================================
// imem_sync.sv  —  Synchronous Instruction Memory
// Address presented cycle N → instruction valid at cycle N+1.
// en_i = 0 freezes the output register (used for VPU stalls).
// =============================================================================
module imem_sync #(
    parameter int DEPTH = 2048   // 8 KB  (2048 × 32-bit words)
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        en_i,      // fetch enable; 0 = hold output
    input  logic [31:0] pc_i,
    output logic [31:0] instr_o
);
    localparam int AW = $clog2(DEPTH);   // address bits for word index

    logic [31:0] mem [0:DEPTH-1];

    // Simulation init — on ASIC replaced by SRAM macro with separate init flow
    initial $readmemh("imem.hex", mem);

    always_ff @(posedge clk) begin
        if (!rst_n)
            instr_o <= 32'h0000_0013;   // NOP (addi x0,x0,0) during reset
        else if (en_i)
            instr_o <= mem[pc_i[AW+1:2]];
    end

endmodule
