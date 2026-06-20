`timescale 1ns/1ps
// =============================================================================
// tb_wave_full_vpu.sv — Full design waveform debug testbench
//
// Chạy FULL data path: scalar core → DMEM → VLSU → VRF → VPU → VLSU → DMEM
// Program: vpu_demo.S (compile: make SRC=vpu_demo.S HEX_OUT=../vpu_demo.hex)
//
// Tín hiệu waveform tập trung vào VPU:
//   ─ PC + instruction type    : biết scalar core đang ở đâu
//   ─ vpu_insn_vld + instruction: lệnh VPU vừa dispatch
//   ─ fsm_state + busy          : VPU đang ở giai đoạn nào
//   ─ vs1/vs2/vd addr           : thanh ghi nào đang dùng
//   ─ rs2/rs1 data per lane     : operand values đọc từ VRF
//   ─ wb_lane0..3               : kết quả ALU
//   ─ vrf_waddr/wdata/wen       : ghi vào VRF
//   ─ vlsu_mem_req/addr/data    : VLSU memory bus
//   ─ HEX0 output               : tiến trình chương trình
//
// Stop: khi HEX0 code = 0x5E ('d' = done) hoặc timeout
// Chạy: vsim -do run_wave_full_vpu.do
// =============================================================================

module tb_wave_full_vpu;

    // ── DUT ports ─────────────────────────────────────────────────────────────
    logic        clk, rst_n;
    logic [31:0] io_sw;
    logic [31:0] io_ledr, io_ledg, io_lcd;
    logic [6:0]  io_hex0, io_hex1, io_hex2, io_hex3;
    logic [6:0]  io_hex4, io_hex5, io_hex6, io_hex7;
    logic [31:0] pc_debug;
    logic        insn_vld;
    logic [3:0]  vpu_cycles;
    logic [15:0] vpu_vmask16;
    logic        vpu_fifo_full, vpu_busy;
    logic [3:0]  vpu_fsm_state;
    logic [31:0] vpu_wb_lane0, vpu_wb_lane1, vpu_wb_lane2, vpu_wb_lane3;

    // ── Shortcuts vào nội bộ ──────────────────────────────────────────────────
    `define IMEM   dut.u_scalar_core.IMEM
    `define LSU    dut.u_scalar_core.lsu_u
    `define CORE   dut.u_scalar_core
    `define VPU    dut.u_vpu

    // ── DUT ───────────────────────────────────────────────────────────────────
    riscv_vpu_top dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .io_sw       (io_sw),
        .io_ledr     (io_ledr),
        .io_ledg     (io_ledg),
        .io_lcd      (io_lcd),
        .io_hex0     (io_hex0),
        .io_hex1     (io_hex1),
        .io_hex2     (io_hex2),
        .io_hex3     (io_hex3),
        .io_hex4     (io_hex4),
        .io_hex5     (io_hex5),
        .io_hex6     (io_hex6),
        .io_hex7     (io_hex7),
        .pc_debug    (pc_debug),
        .insn_vld    (insn_vld),
        .vpu_cycles  (vpu_cycles),
        .vpu_vmask16 (vpu_vmask16),
        .vpu_fifo_full(vpu_fifo_full),
        .vpu_busy    (vpu_busy),
        .vpu_fsm_state(vpu_fsm_state),
        .vpu_wb_lane0(vpu_wb_lane0),
        .vpu_wb_lane1(vpu_wb_lane1),
        .vpu_wb_lane2(vpu_wb_lane2),
        .vpu_wb_lane3(vpu_wb_lane3)
    );

    always #5 clk = ~clk;

    // ── Helper: đọc VRF ───────────────────────────────────────────────────────
    function automatic [31:0] vrf_rd(input int lane, input int r);
        case (lane)
            0: vrf_rd = {`VPU.vrf_lane0.bank3[r], `VPU.vrf_lane0.bank2[r],
                         `VPU.vrf_lane0.bank1[r], `VPU.vrf_lane0.bank0[r]};
            1: vrf_rd = {`VPU.vrf_lane1.bank3[r], `VPU.vrf_lane1.bank2[r],
                         `VPU.vrf_lane1.bank1[r], `VPU.vrf_lane1.bank0[r]};
            2: vrf_rd = {`VPU.vrf_lane2.bank3[r], `VPU.vrf_lane2.bank2[r],
                         `VPU.vrf_lane2.bank1[r], `VPU.vrf_lane2.bank0[r]};
            3: vrf_rd = {`VPU.vrf_lane3.bank3[r], `VPU.vrf_lane3.bank2[r],
                         `VPU.vrf_lane3.bank1[r], `VPU.vrf_lane3.bank0[r]};
            default: vrf_rd = 32'hX;
        endcase
    endfunction

    // ── Helper: đọc DMEM ──────────────────────────────────────────────────────
    function automatic [31:0] dmem_rd(input int byte_addr);
        dmem_rd = `LSU.dmem[byte_addr[15:2]];
    endfunction

    // ── Helper: decode opcode ─────────────────────────────────────────────────
    function automatic string opcode_str(input [6:0] op);
        case (op)
            7'b0110011: opcode_str = "ALU-R ";
            7'b0010011: opcode_str = "ALU-I ";
            7'b0000011: opcode_str = "LOAD  ";
            7'b0100011: opcode_str = "STORE ";
            7'b1100011: opcode_str = "BRANCH";
            7'b1101111: opcode_str = "JAL   ";
            7'b0110111: opcode_str = "LUI   ";
            7'b1010111: opcode_str = "OP-V  ";
            7'b0000111: opcode_str = "VLE   ";
            7'b0100111: opcode_str = "VSE   ";
            7'b1110011: opcode_str = "SYSTEM";
            default:    opcode_str = "???   ";
        endcase
    endfunction

    // ── Decode VPU instruction name ────────────────────────────────────────────
    function automatic string vpu_instr_name(input [31:0] inst);
        logic [5:0] f6;
        logic [2:0] f3;
        f6 = inst[31:26];
        f3 = inst[14:12];
        if (inst[6:0] == 7'b0000111) begin vpu_instr_name = "vle32.v "; end
        else if (inst[6:0] == 7'b0100111) begin vpu_instr_name = "vse32.v "; end
        else if (f3 == 3'b111)       begin vpu_instr_name = "vsetvli "; end
        else
        case (f6)
            6'h00: vpu_instr_name = "vadd    ";
            6'h02: vpu_instr_name = "vsub    ";
            6'h25: vpu_instr_name = "vmul    ";
            6'h0B: vpu_instr_name = "vxor    ";
            6'h09: vpu_instr_name = "vand    ";
            6'h0A: vpu_instr_name = "vor     ";
            6'h0C: vpu_instr_name = "vredsum ";
            6'h0D: vpu_instr_name = "vredmax ";
            6'h0F: vpu_instr_name = "vredmin ";
            6'h18: vpu_instr_name = "vmseq   ";
            6'h1A: vpu_instr_name = "vmsltu  ";
            default: vpu_instr_name = "vop?    ";
        endcase
    endfunction

    // ── Print VRF register (e32) ──────────────────────────────────────────────
    task automatic print_vreg(input int r);
        $display("    v%0d = {e0=%0d, e1=%0d, e2=%0d, e3=%0d}  (hex: %08X %08X %08X %08X)",
            r,
            $signed(vrf_rd(0,r)), $signed(vrf_rd(1,r)),
            $signed(vrf_rd(2,r)), $signed(vrf_rd(3,r)),
            vrf_rd(0,r), vrf_rd(1,r), vrf_rd(2,r), vrf_rd(3,r));
    endtask

    // ── Print DMEM word block ─────────────────────────────────────────────────
    task automatic print_dmem(input int base_addr, input int nwords, input string label);
        int i;
        $write("    %s [0x%04X]: ", label, base_addr);
        for (i = 0; i < nwords; i++) begin
            $write("{%0d} ", $signed(dmem_rd(base_addr + i*4)));
        end
        $display("");
    endtask

    // ── Cycle counter ─────────────────────────────────────────────────────────
    int cycle_cnt;
    int pass_cnt, fail_cnt;

    // ── VPU instruction trace ─────────────────────────────────────────────────
    // In ra mỗi khi scalar core dispatch một VPU instruction
    logic prev_vpu_insn_vld;
    always @(posedge clk) begin
        if (rst_n) begin
            prev_vpu_insn_vld <= `CORE.vpu_insn_vld;
            if (`CORE.vpu_insn_vld && !prev_vpu_insn_vld) begin
                $display("  [Cy%0d] DISPATCH %s  inst=0x%08X  vpu_ready=%b  stall=%b",
                    cycle_cnt, vpu_instr_name(`CORE.inst),
                    `CORE.inst, `CORE.i_vpu_ready, `CORE.vpu_stall);
            end
        end
    end

    // ── VRF writeback trace ───────────────────────────────────────────────────
    always @(posedge clk) begin
        if (rst_n && `VPU.fsm_vrf_wren && !`VPU.final_masking_commit) begin
            $display("  [Cy%0d] VRF_WB  vd=v%0d  d0=0x%08X d1=0x%08X d2=0x%08X d3=0x%08X  we={%h%h%h%h}",
                cycle_cnt,
                `VPU.vrf_waddr_eff,
                `VPU.vrf_wdata0_eff, `VPU.vrf_wdata1_eff,
                `VPU.vrf_wdata2_eff, `VPU.vrf_wdata3_eff,
                `VPU.vrf_we3_eff[0], `VPU.vrf_we2_eff[0],
                `VPU.vrf_we1_eff[0], `VPU.vrf_we0_eff[0]);
        end
    end

    // ── VLSU trace ────────────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (rst_n && `VPU.vlsu_mem_req) begin
            if (`VPU.vlsu_mem_we)
                $display("  [Cy%0d] VLSU_WR  addr=0x%08X  data=0x%08X  be=%04b",
                    cycle_cnt, `VPU.vlsu_mem_addr,
                    `VPU.vlsu_mem_wdata, `VPU.vlsu_mem_be);
            else
                $display("  [Cy%0d] VLSU_RD  addr=0x%08X  rdata=0x%08X",
                    cycle_cnt, `VPU.vlsu_mem_addr, `VPU.vlsu_mem_rdata);
        end
    end

    // ── PC trace (in khi PC thay đổi) ────────────────────────────────────────
    logic [31:0] prev_pc;
    always @(posedge clk) begin
        if (rst_n) begin
            if (pc_debug !== prev_pc) begin
                prev_pc <= pc_debug;
                if (pc_debug[31:8] == 0 && pc_debug <= 32'h200) begin
                    $display("[Cy%0d] PC=0x%04X  inst=0x%08X  (%s)",
                        cycle_cnt, pc_debug, `CORE.inst,
                        opcode_str(`CORE.inst[6:0]));
                end
            end
        end
    end

    // ==========================================================================
    // MAIN
    // ==========================================================================
    initial begin
        clk   = 0;
        rst_n = 0;
        io_sw = 32'h0;
        pass_cnt = 0;
        fail_cnt = 0;
        cycle_cnt = 0;
        prev_pc = 32'hFFFF_FFFF;
        prev_vpu_insn_vld = 0;

        // Override IMEM với vpu_demo.hex
        $readmemh("vpu_demo.hex", `IMEM.inst_mem);

        $display("=================================================================");
        $display("  tb_wave_full_vpu — Full VPU path test");
        $display("  Program: vpu_demo.S  (vsetvli → vle32 → vadd/vsub/vmul/vxor");
        $display("           → vadd.vx → vredsum → vse32 → scalar verify)");
        $display("=================================================================\n");

        // Reset
        repeat(4) @(negedge clk);
        rst_n = 1;
        repeat(2) @(negedge clk);

        // Run đến khi HEX0 = 0x5E (code cho 'd' = done) hoặc timeout
        fork
            // Thread 1: đếm cycle và check stop
            begin
                for (cycle_cnt = 0; cycle_cnt < 50000; cycle_cnt++) begin
                    @(posedge clk); #1;
                    // HEX0 = io_hex0[6:0] = 0x5E → done
                    if (io_hex0 == 7'h5E) begin
                        $display("\n[Cy%0d] HEX0='d' detected — program DONE!", cycle_cnt);
                        break;
                    end
                end
                if (cycle_cnt >= 50000)
                    $display("\n[WARN] Timeout after 50000 cycles!");
            end
        join

        repeat(5) @(posedge clk);

        // ====================================================================
        // POST-MORTEM: kiểm tra kết quả
        // ====================================================================
        $display("\n=================================================================");
        $display("  POST-MORTEM RESULTS");
        $display("=================================================================");
        $display("  CSR: vl=%0d  vtype=0x%08X  vlenb=%0d",
            `VPU.csr_vl_o, `VPU.csr_vtype_o, `VPU.csr_vlenb_o);
        $display("  FSM: state=%0d  busy=%b", vpu_fsm_state, vpu_busy);

        $display("\n── VRF Contents (key registers) ──────────────────────────────");
        print_vreg(8);    // Input A
        print_vreg(9);    // Input B
        print_vreg(2);    // vadd result
        print_vreg(3);    // vsub result
        print_vreg(4);    // vmul result
        print_vreg(5);    // vxor result
        print_vreg(6);    // vadd.vx result
        print_vreg(7);    // vredsum result

        $display("\n── DMEM Results (via vse32.v) ────────────────────────────────");
        print_dmem('h0800,  4, "Input A   ");
        print_dmem('h0810,  4, "Input B   ");
        print_dmem('h0820,  4, "vadd      ");
        print_dmem('h0830,  4, "vsub      ");
        print_dmem('h0840,  4, "vmul      ");
        print_dmem('h0850,  4, "vxor      ");
        print_dmem('h0860,  4, "vadd.vx   ");
        print_dmem('h0870,  4, "vredsum   ");

        $display("\n── Scalar Register Read-back ─────────────────────────────────");
        $display("  s1(vadd[0])=%0d  s2(vadd[1])=%0d  s3(vadd[2])=%0d  s4(vadd[3])=%0d",
            $signed(`CORE.u_register_file.data9),   // s1=x9
            $signed(`CORE.u_register_file.data18),  // s2=x18
            $signed(`CORE.u_register_file.data19),  // s3=x19
            $signed(`CORE.u_register_file.data20)); // s4=x20
        $display("  s5(vmul[0])=%0d  s6(vmul[1])=%0d  s7(vmul[2])=%0d  s8(vmul[3])=%0d",
            $signed(`CORE.u_register_file.data21),
            $signed(`CORE.u_register_file.data22),
            $signed(`CORE.u_register_file.data23),
            $signed(`CORE.u_register_file.data24));
        $display("  s9(vredsum)=%0d",
            $signed(`CORE.u_register_file.data25));

        // ── Verify ─────────────────────────────────────────────────────────
        $display("\n── Verification ──────────────────────────────────────────────");

        // vadd: A+B = {11,22,33,44}
        begin
            logic [31:0] r0,r1,r2,r3;
            r0 = vrf_rd(0,2); r1 = vrf_rd(1,2); r2 = vrf_rd(2,2); r3 = vrf_rd(3,2);
            if (r0===32'd11 && r1===32'd22 && r2===32'd33 && r3===32'd44) begin
                $display("  ✓ PASS  vadd.vv v2: {11,22,33,44}"); pass_cnt++;
            end else begin
                $display("  ✗ FAIL  vadd.vv v2: got {%0d,%0d,%0d,%0d} exp {11,22,33,44}",
                    r0,r1,r2,r3); fail_cnt++;
            end
        end

        // vsub: A-B = {9,18,27,36}
        begin
            logic [31:0] r0,r1,r2,r3;
            r0=vrf_rd(0,3); r1=vrf_rd(1,3); r2=vrf_rd(2,3); r3=vrf_rd(3,3);
            if (r0===32'd9 && r1===32'd18 && r2===32'd27 && r3===32'd36) begin
                $display("  ✓ PASS  vsub.vv v3: {9,18,27,36}"); pass_cnt++;
            end else begin
                $display("  ✗ FAIL  vsub.vv v3: got {%0d,%0d,%0d,%0d}", r0,r1,r2,r3); fail_cnt++;
            end
        end

        // vmul: A*B = {10,40,90,160}
        begin
            logic [31:0] r0,r1,r2,r3;
            r0=vrf_rd(0,4); r1=vrf_rd(1,4); r2=vrf_rd(2,4); r3=vrf_rd(3,4);
            if (r0===32'd10 && r1===32'd40 && r2===32'd90 && r3===32'd160) begin
                $display("  ✓ PASS  vmul.vv v4: {10,40,90,160}"); pass_cnt++;
            end else begin
                $display("  ✗ FAIL  vmul.vv v4: got {%0d,%0d,%0d,%0d}", r0,r1,r2,r3); fail_cnt++;
            end
        end

        // vadd.vx: A+50 = {60,70,80,90}
        begin
            logic [31:0] r0,r1,r2,r3;
            r0=vrf_rd(0,6); r1=vrf_rd(1,6); r2=vrf_rd(2,6); r3=vrf_rd(3,6);
            if (r0===32'd60 && r1===32'd70 && r2===32'd80 && r3===32'd90) begin
                $display("  ✓ PASS  vadd.vx v6: {60,70,80,90}"); pass_cnt++;
            end else begin
                $display("  ✗ FAIL  vadd.vx v6: got {%0d,%0d,%0d,%0d}", r0,r1,r2,r3); fail_cnt++;
            end
        end

        // vredsum: v9[0] + sum(v8) = 1+10+20+30+40 = 101
        begin
            logic [31:0] r0;
            r0 = vrf_rd(0,7);
            if (r0 === 32'd101) begin
                $display("  ✓ PASS  vredsum  v7[0]: 101"); pass_cnt++;
            end else begin
                $display("  ✗ FAIL  vredsum  v7[0]: got %0d exp 101", r0); fail_cnt++;
            end
        end

        // DMEM verify (vse32.v path)
        begin
            logic [31:0] d0;
            d0 = dmem_rd('h0820);
            if (d0 === 32'd11) begin
                $display("  ✓ PASS  vse32.v vadd[0] in DMEM: 11"); pass_cnt++;
            end else begin
                $display("  ✗ FAIL  vse32.v vadd[0] in DMEM: got %0d", d0); fail_cnt++;
            end
        end

        $display("\n=================================================================");
        $display("  SUMMARY: PASS=%0d  FAIL=%0d  Cycles=%0d",
                 pass_cnt, fail_cnt, cycle_cnt);
        if (fail_cnt == 0)
            $display("  → ALL PASS ✓  Full data-path verified");
        else
            $display("  → FAIL — xem waveform để debug");
        $display("=================================================================\n");
        $finish;
    end

endmodule
