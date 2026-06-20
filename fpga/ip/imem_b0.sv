// imem_b0.sv — Behavioral model for altsyncram ROM:1-PORT, byte lane 0 (bits 7:0).
//
// Models OUTDATA_REG_A = UNREGISTERED mode:
//   The M10K's output is combinational — no output FF inside the IP.
//   The single pipeline register lives in imem_sync.sv's always_ff wrapper,
//   giving 1-cycle total latency (matching the original imem_sync behavior).
module imem_b0 #(
    parameter int    DEPTH    = 2048,
    parameter string HEX_FILE = "C:\\CapstoneProject2\\riscv_vpu\\fpga\\uart_lena.hex"
) (
    input  logic                      clock,
    input  logic [$clog2(DEPTH)-1:0]  address,
    output logic [7:0]                q
);
    logic [31:0] mem_sim [0:DEPTH-1];
    initial $readmemh(HEX_FILE, mem_sim);
    assign q = mem_sim[address][7:0];
endmodule
