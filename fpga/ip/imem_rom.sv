// imem_rom.sv — Behavioral 4×8-bit ROM for simulation (replaces Quartus altsyncram).
//
// Matches the interface of imem_sync when used as a standalone IP.
// Simulation reads one 32-bit hex file and splits into 4 byte lanes internally.
//
// Synthesis: use imem_sync.sv directly (it already contains the 4×8 inference
// attributes). This file is for testbenches that instantiate imem_rom separately.

module imem_rom #(
    parameter int    DEPTH    = 2048,
    parameter string HEX_FILE = "C:\\CapstoneProject2\\riscv_vpu\\fpga\\uart_lena.hex"
) (
    input  logic                      clock,
    input  logic [$clog2(DEPTH)-1:0]  address,
    output logic [31:0]               q
);
    // Four byte-lane arrays — mirrors imem_sync.sv synthesis structure
    logic [7:0] mem_b0 [0:DEPTH-1];
    logic [7:0] mem_b1 [0:DEPTH-1];
    logic [7:0] mem_b2 [0:DEPTH-1];
    logic [7:0] mem_b3 [0:DEPTH-1];

    logic [31:0] mem_sim [0:DEPTH-1];
    initial begin
        $readmemh(HEX_FILE, mem_sim);
        for (int i = 0; i < DEPTH; i++) begin
            mem_b0[i] = mem_sim[i][ 7: 0];
            mem_b1[i] = mem_sim[i][15: 8];
            mem_b2[i] = mem_sim[i][23:16];
            mem_b3[i] = mem_sim[i][31:24];
        end
    end

    always_ff @(posedge clock)
        q <= {mem_b3[address], mem_b2[address], mem_b1[address], mem_b0[address]};

endmodule
