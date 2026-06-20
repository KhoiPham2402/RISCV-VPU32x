module imem (
    input  logic [31:0] pc,
    output logic [31:0] instr
);
    // 8 KB = 2048 × 32-bit words; rom_addr from pc[12:2]
    reg [31:0] inst_mem [0:2047];
    wire [10:0] rom_addr = pc[12:2];

    assign instr = inst_mem[rom_addr];

    initial $readmemh("imem.hex", inst_mem);

endmodule
