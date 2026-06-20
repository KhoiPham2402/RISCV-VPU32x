// imem_b2.sv — Behavioral model for altsyncram ROM:1-PORT, byte lane 2 (bits 23:16).
// OUTDATA_REG_A = UNREGISTERED: combinational output, no IP-internal FF.
module imem_b2 #(
    parameter int    DEPTH    = 2048,
    parameter string HEX_FILE = "C:\\CapstoneProject2\\riscv_vpu\\fpga\\uart_lena.hex"
) (
    input  logic                      clock,
    input  logic [$clog2(DEPTH)-1:0]  address,
    output logic [7:0]                q
);
    logic [31:0] mem_sim [0:DEPTH-1];
    initial $readmemh(HEX_FILE, mem_sim);
    assign q = mem_sim[address][23:16];
endmodule
