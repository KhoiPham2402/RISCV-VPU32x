// =============================================================================
// lena_rom.sv — 4096 × 32-bit read-only ROM for Lena grayscale demo.
//
// Stores 128×128 grayscale pixels packed 4 per word (little-endian bytes):
//   addr = row*32 + col/4
//   bits[(col%4)*8 +: 8] = pixel(row, col)
//
// Initialized from lena_rom.hex ($readmemh, one 32-bit word per line).
// Copy lena_y_reference.hex → <quartus_project>/lena_rom.hex before compile.
//
// Timing: 1-cycle registered output (matches M10K behaviour expected by vga_ctrl).
// Clock domain: pclk (25 MHz, same as vga_ctrl).
// =============================================================================
module lena_rom (
    input  logic        clk,
    input  logic [13:0] addr,   // word address from vga_ctrl (12288..16383)
    input  logic        re,
    output logic [31:0] rdata
);
    (* ramstyle = "M10K" *) logic [31:0] mem [0:4095];
    initial $readmemh("lena_rom.hex", mem);

    always_ff @(posedge clk)
        if (re) rdata <= mem[addr[11:0]];   // addr[11:0] = addr - 12288

endmodule
