module imem (
    input  logic [31:0] pc,
    output logic [31:0] instr
);

// Memory for Instructions (8KB) (2048 instructions)
	reg [31:0] inst_mem [0:2047];
	wire [10:0] rom_addr = pc[12:2]; //pc increment in steps of 4
	
	assign instr = inst_mem[rom_addr]; 
	initial begin
	 	$readmemh("C:\\CapstoneProject2\\riscv_vpu\\rtl\\imem_from_gcc.hex",inst_mem);
		//$readmemh("C:\\Users\\khoi-laptop\\Documents\\CTMT\\MINDSTONE_2\\riscv_occ\\02_test);
		//$readmemh("imem.mem",inst_mem);
	end
 

endmodule
