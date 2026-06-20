// dmem_bank.sv — Behavioral 8-bit True Dual-Port SRAM
//
// Simulation-only replacement for the Quartus altsyncram (M10K) IP.
// Mimics: registered outputs, OLD_DATA read-during-write, single clock.
//
// Generate the real IP in Quartus:
//   IP Catalog → Basic Functions → On Chip Memory → RAM: 2-PORT (altsyncram)
//   Width=8, Depth=16384, TDP, no byteena, M10K, registered outputs, OLD_DATA.
//   Output name: dmem_bank → dmem_bank.qip

module dmem_bank #(
    parameter int DEPTH = 16384
) (
    input  logic                     clock,
    // Port A
    input  logic [$clog2(DEPTH)-1:0] address_a,
    input  logic [7:0]               data_a,
    input  logic                     wren_a,
    input  logic                     rden_a,
    output logic [7:0]               q_a,
    // Port B
    input  logic [$clog2(DEPTH)-1:0] address_b,
    input  logic [7:0]               data_b,
    input  logic                     wren_b,
    input  logic                     rden_b,
    output logic [7:0]               q_b
);
    logic [7:0] mem [0:DEPTH-1];

    // Port A — OLD_DATA: read evaluates before write takes effect (both are NBAs)
    always_ff @(posedge clock) begin
        if (rden_a) q_a <= mem[address_a];
        if (wren_a) mem[address_a] <= data_a;
    end

    // Port B
    always_ff @(posedge clock) begin
        if (rden_b) q_b <= mem[address_b];
        if (wren_b) mem[address_b] <= data_b;
    end

endmodule
