// =============================================================================
// dmem_model_sp.sv — behavioral single-port DMEM model for simulation.
//
// Same timing contract as dmem_qip_wrapper.sv (fpga/rtl/mem/): re/we in this
// cycle -> for a read, rdata registered and valid next cycle; for a write,
// committed this cycle, byte-enabled. Backs a flat word array so existing
// $readmemh / direct hierarchical-path dumps in testbenches keep working.
//
// Simulation-only (not synthesizable IP) — mirrors the real dmem_qip_wrapper
// interface exactly so it can sit behind dmem_arbiter.sv in any testbench.
// =============================================================================
`timescale 1ns/1ps

module dmem_model_sp #(
    parameter int DEPTH = 16384
) (
    input  logic        clk,
    input  logic        re,
    input  logic        we,
    input  logic [31:0] addr,
    input  logic [ 3:0] be,
    input  logic [31:0] wdata,
    output logic [31:0] rdata
);
    localparam int AW = $clog2(DEPTH);

    reg [31:0] mem [0:DEPTH-1];

    logic [31:0] rdata_r;

    always @(posedge clk) begin
        if (re) rdata_r <= mem[addr[AW+1:2]];
        if (we) begin
            if (be[0]) mem[addr[AW+1:2]][ 7: 0] <= wdata[ 7: 0];
            if (be[1]) mem[addr[AW+1:2]][15: 8] <= wdata[15: 8];
            if (be[2]) mem[addr[AW+1:2]][23:16] <= wdata[23:16];
            if (be[3]) mem[addr[AW+1:2]][31:24] <= wdata[31:24];
        end
    end

    assign rdata = rdata_r;

endmodule
