// =============================================================================
// tb_fixcheck.sv — Directed unit checks for two Critical fixes (2026-08-01):
//   1. brc.sv: signed/unsigned branch comparison was swapped (Issue #19)
//   2. control_unit.sv: RV32M (mul/div/rem) silently aliased onto base ALU
//      ops instead of being squashed (Issue #20)
//
// Run: vsim -c -do fpga/sim/run_fixcheck.do
// =============================================================================
`timescale 1ns/1ps
module tb_fixcheck;

    // ---- brc.sv check: signed/unsigned branch compare ----
    logic [31:0] a, b;
    logic        br_un;
    logic [2:0]  f3;
    logic        o_less, o_taken;
    int errors = 0;

    brc u_brc (
        .i_rs1_data(a), .i_rs2_data(b), .i_br_un(br_un), .func3(f3),
        .o_br_less(o_less), .o_br_taken(o_taken)
    );

    task check_branch(input [31:0] va, vb, input bit un, input [2:0] fn3,
                       input bit expect_taken, input string name);
        begin
            a = va; b = vb; br_un = un; f3 = fn3;
            #1;
            if (o_taken !== expect_taken) begin
                $display("[FAIL] %s: rs1=%0d rs2=%0d br_un=%0d -> taken=%0b expected=%0b",
                          name, $signed(va), $signed(vb), un, o_taken, expect_taken);
                errors++;
            end else begin
                $display("[PASS] %s: taken=%0b (expected %0b)", name, o_taken, expect_taken);
            end
        end
    endtask

    // ---- control_unit.sv check: M-ext squash ----
    logic [16:0] cu_instr;
    logic cu_br_ctrl, cu_j_taken, cu_br_un, cu_opa, cu_opb, cu_mem_wren, cu_rd_wren;
    logic cu_insn_vld, cu_func7, cu_is_load, cu_is_vector, cu_illegal;
    logic [2:0] cu_immsel;
    logic [3:0] cu_alu_op;
    logic [1:0] cu_wb_sel;

    control_unit u_cu (
        .instr(cu_instr), .br_ctrl(cu_br_ctrl), .j_taken(cu_j_taken),
        .Immsel(cu_immsel), .alu_op(cu_alu_op), .wb_sel(cu_wb_sel),
        .br_un(cu_br_un), .opa_sel(cu_opa), .opb_sel(cu_opb),
        .mem_wren(cu_mem_wren), .rd_wren(cu_rd_wren), .insn_vld(cu_insn_vld),
        .func7(cu_func7), .is_load(cu_is_load), .is_vector(cu_is_vector),
        .illegal_instr(cu_illegal)
    );

    task check_mext(input [6:0] funct7, input [2:0] funct3, input string name,
                     input bit expect_illegal);
        begin
            cu_instr = {funct7, funct3, 7'b0110011}; // OPC_REGREG
            #1;
            if (cu_illegal !== expect_illegal || (expect_illegal && cu_rd_wren !== 1'b0)) begin
                $display("[FAIL] %s: funct7=%b funct3=%b -> illegal=%0b rd_wren=%0b",
                          name, funct7, funct3, cu_illegal, cu_rd_wren);
                errors++;
            end else begin
                $display("[PASS] %s: illegal=%0b rd_wren=%0b", name, cu_illegal, cu_rd_wren);
            end
        end
    endtask

    initial begin
        // BLT(-1, 1) must take the branch (signed: -1 < 1)
        check_branch(32'hFFFFFFFF, 32'd1, 1'b0, 3'b100, 1'b1, "BLT(-1,1)");
        // BGE(-1, 1) must NOT take the branch
        check_branch(32'hFFFFFFFF, 32'd1, 1'b0, 3'b101, 1'b0, "BGE(-1,1)");
        // BLTU(-1, 1): unsigned, -1 = 0xFFFFFFFF is huge, so NOT less than 1
        check_branch(32'hFFFFFFFF, 32'd1, 1'b1, 3'b110, 1'b0, "BLTU(-1,1)");
        // BGEU(-1, 1): unsigned, 0xFFFFFFFF >= 1 -> taken
        check_branch(32'hFFFFFFFF, 32'd1, 1'b1, 3'b111, 1'b1, "BGEU(-1,1)");
        // sanity: BLT(1, 2) taken (normal positive case, must still work)
        check_branch(32'd1, 32'd2, 1'b0, 3'b100, 1'b1, "BLT(1,2)");
        // sanity: BLTU(1, 2) taken
        check_branch(32'd1, 32'd2, 1'b1, 3'b110, 1'b1, "BLTU(1,2)");

        // M-extension: mul (funct7=0000001, funct3=000) must be squashed
        check_mext(7'b0000001, 3'b000, "MUL squashed", 1'b1);
        // M-extension: div (funct7=0000001, funct3=100)
        check_mext(7'b0000001, 3'b100, "DIV squashed", 1'b1);
        // base ADD (funct7=0000000) must NOT be flagged illegal
        check_mext(7'b0000000, 3'b000, "ADD not illegal", 1'b0);
        // base SUB (funct7=0100000) must NOT be flagged illegal
        check_mext(7'b0100000, 3'b000, "SUB not illegal", 1'b0);

        if (errors == 0) $display("ALL CHECKS PASSED");
        else $display("%0d CHECK(S) FAILED", errors);
        $stop;
    end
endmodule
