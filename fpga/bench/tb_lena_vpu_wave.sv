// =============================================================================
// tb_lena_vpu_wave.sv — Lena-like grayscale pipeline waveform demo (no UART)
//
// Directly drives vproc_system_wrapper (FPGA RTL) with a BT.601-style sequence:
//   1. vsetvli  e32, m1  → vl=4
//   2. vle32.v  v8 ← R channel {100,120,80,200}
//   3. vmul.vv  v10 = v8 × v9_coeff   (proxy for vmulhu R×77)
//   4. vle32.v  v11 ← G channel {50,80,30,150}
//   5. vmul.vv  v12 = v11 × v9_coeff  (proxy for vmulhu G×150)
//   6. vadd.vv  v10 = v10 + v12        (accumulate)
//   7. vle32.v  v11 ← B channel {10,20,40,60}
//   8. vmul.vv  v12 = v11 × v9_coeff
//   9. vadd.vv  v10 = v10 + v12        (final Y)
//  10. vse32.v  v10 → Y output region
//
// Waveform shows: VLSU ST_IDLE↔ST_LOAD↔ST_STORE, FSM ST_IDLE↔ST_EXEC,
//                 instruction name string, VRF write-back data per lane.
//
// Run:  vsim -do fpga/sim/run_wave_lena_vpu.do
// =============================================================================
`timescale 1ns/1ps

module tb_lena_vpu_wave;

    // ─── Clock / Reset ──────────────────────────────────────────────────────
    localparam CLK_PERIOD = 10;
    logic clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    logic rst_n;

    // ─── VPU interface ──────────────────────────────────────────────────────
    logic        instr_valid;
    logic [31:0] instruction;
    logic [31:0] rs1_scalar_data;
    logic [31:0] rs2_scalar_data;

    logic        vpu_ready, vpu_cfg_done, vpu_busy;
    logic [3:0]  fsm_state;
    logic [31:0] vpu_vl_remain;
    logic [15:0] vmask16;
    logic [3:0]  vpu_cycles;
    logic        fifo_full;
    logic [31:0] wb_lane0, wb_lane1, wb_lane2, wb_lane3;
    logic [31:0] csr_vl, csr_vtype, csr_vlenb, csr_rdata;
    logic        vlsu_busy_o;

    // ─── VLSU DMEM bus ──────────────────────────────────────────────────────
    logic        vlsu_req, vlsu_we;
    logic [31:0] vlsu_addr;
    logic [ 3:0] vlsu_be;
    logic [31:0] vlsu_wdata, vlsu_rdata;
    logic        vlsu_ready;

    // ─── DUT ────────────────────────────────────────────────────────────────
    vproc_system_wrapper #(
        .NUM_REGS   (32),
        .ADDR_WIDTH (5),
        .CTRL_WIDTH (49)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .instr_valid      (instr_valid),
        .instruction      (instruction),
        .rs1_scalar_data  (rs1_scalar_data),
        .rs2_scalar_data  (rs2_scalar_data),
        .vrf_commit_en    (1'b1),
        .cycles           (vpu_cycles),
        .vmask16          (vmask16),
        .fifo_full        (fifo_full),
        .busy             (vpu_busy),
        .fsm_state        (fsm_state),
        .wb_result_lane0  (wb_lane0),
        .wb_result_lane1  (wb_lane1),
        .wb_result_lane2  (wb_lane2),
        .wb_result_lane3  (wb_lane3),
        .vpu_ready        (vpu_ready),
        .vpu_cfg_done     (vpu_cfg_done),
        .vpu_vl_remain    (vpu_vl_remain),
        .csr_vl_o         (csr_vl),
        .csr_vtype_o      (csr_vtype),
        .csr_vlenb_o      (csr_vlenb),
        .scalar_csr_addr  (12'b0),
        .scalar_csr_rdata (csr_rdata),
        .vlsu_mem_req     (vlsu_req),
        .vlsu_mem_we      (vlsu_we),
        .vlsu_mem_addr    (vlsu_addr),
        .vlsu_mem_be      (vlsu_be),
        .vlsu_mem_wdata   (vlsu_wdata),
        .vlsu_mem_rdata   (vlsu_rdata),
        .vlsu_mem_ready   (vlsu_ready),
        .vlsu_busy_o      (vlsu_busy_o)
    );

    // ─── 1-cycle registered DMEM (M10K model) ───────────────────────────────
    reg [31:0] dmem [0:1023];
    logic rd_pend;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rd_pend <= 0; vlsu_rdata <= 0; end
        else begin
            rd_pend <= vlsu_req && !vlsu_we;
            if (vlsu_req) begin
                if (vlsu_we) dmem[vlsu_addr[11:2]] <= vlsu_wdata;
                else         vlsu_rdata <= dmem[vlsu_addr[11:2]];
            end
        end
    end
    assign vlsu_ready = vlsu_we ? vlsu_req : rd_pend;

    // ─── Instruction name decoder ────────────────────────────────────────────
    string instr_name;
    always_comb begin
        if (!instr_valid) instr_name = "---";
        else case (instruction[6:0])
            7'b1010111: begin
                if   (instruction[14:12] == 3'b111)              instr_name = "vsetvli";
                else if (instruction[14:12]==3'b010 &&
                         instruction[31:26]==6'b000000)          instr_name = "vredsum.vs";
                else if (instruction[31:26]==6'b100101 &&
                         instruction[14:12]==3'b010)             instr_name = "vmul.vv";
                else if (instruction[31:26]==6'b100101 &&
                         instruction[14:12]==3'b110)             instr_name = "vmul.vx";
                else if (instruction[31:26]==6'b000000 &&
                         instruction[14:12]==3'b000)             instr_name = "vadd.vv";
                else                                             instr_name = "OP-V";
            end
            7'b0000111: instr_name = (instruction[14:12]==3'b110) ? "vle32.v" : "vle?.v";
            7'b0100111: instr_name = (instruction[14:12]==3'b110) ? "vse32.v" : "vse?.v";
            default:    instr_name = "SCALAR";
        endcase
    end

    // ─── FSM state name ──────────────────────────────────────────────────────
    string fsm_state_name;
    always_comb case (fsm_state)
        4'd0: fsm_state_name = "ST_IDLE";
        4'd1: fsm_state_name = "ST_CONFIG";
        4'd2: fsm_state_name = "ST_EXEC";
        4'd7: fsm_state_name = "ST_REDUCTION";
        4'd8: fsm_state_name = "ST_RED_DONE";
        default: fsm_state_name = "ST_OTHER";
    endcase

    // ─── VRF direct read helpers ─────────────────────────────────────────────
    function automatic logic [31:0] vrf_rd0(input [4:0] a);
        return {dut.vrf_lane0.bank3[a], dut.vrf_lane0.bank2[a],
                dut.vrf_lane0.bank1[a], dut.vrf_lane0.bank0[a]};
    endfunction
    function automatic logic [31:0] vrf_rd1(input [4:0] a);
        return {dut.vrf_lane1.bank3[a], dut.vrf_lane1.bank2[a],
                dut.vrf_lane1.bank1[a], dut.vrf_lane1.bank0[a]};
    endfunction
    function automatic logic [31:0] vrf_rd2(input [4:0] a);
        return {dut.vrf_lane2.bank3[a], dut.vrf_lane2.bank2[a],
                dut.vrf_lane2.bank1[a], dut.vrf_lane2.bank0[a]};
    endfunction
    function automatic logic [31:0] vrf_rd3(input [4:0] a);
        return {dut.vrf_lane3.bank3[a], dut.vrf_lane3.bank2[a],
                dut.vrf_lane3.bank1[a], dut.vrf_lane3.bank0[a]};
    endfunction

    task automatic show_vreg(input [4:0] addr, input string name);
        $display("[%0t ns]   %-6s[%0d] = {%0d, %0d, %0d, %0d}",
                 $time, name, addr,
                 vrf_rd0(addr), vrf_rd1(addr), vrf_rd2(addr), vrf_rd3(addr));
    endtask

    // ─── VRF write monitor ───────────────────────────────────────────────────
    always @(posedge clk) begin
        if (dut.vlsu_vrf_we)
            $display("[%0t ns] [VLSU-WR] addr=%0d  {%0d,%0d,%0d,%0d}",
                     $time, dut.vlsu_vrf_waddr,
                     dut.vlsu_vrf_wdata_l0, dut.vlsu_vrf_wdata_l1,
                     dut.vlsu_vrf_wdata_l2, dut.vlsu_vrf_wdata_l3);
        if (dut.fsm_vrf_wren && (|dut.vrf_we0_eff))
            $display("[%0t ns] [FSM-WR ] addr=%0d  {%0d,%0d,%0d,%0d}",
                     $time, dut.vd_addr_eff,
                     dut.vrf_wdata0_eff, dut.vrf_wdata1_eff,
                     dut.vrf_wdata2_eff, dut.vrf_wdata3_eff);
    end

    // ─── Instruction driver ──────────────────────────────────────────────────
    task automatic drive_instr(input [31:0] insn, input [31:0] rs1=0, input [31:0] rs2=0);
        @(posedge clk); while (!vpu_ready) @(posedge clk);
        #1;
        instruction = insn; rs1_scalar_data = rs1; rs2_scalar_data = rs2;
        instr_valid = 1'b1;
        @(posedge clk); #1;
        instr_valid = 1'b0; instruction = 0;
    endtask

    task automatic wait_vls; // wait for VLSU to finish
        @(posedge clk); while (vlsu_busy_o) @(posedge clk);
        @(posedge clk);
    endtask

    task automatic wait_vpu; // wait for OP-V FSM (FIFO latency compensated)
        repeat(2) @(posedge clk);
        while (vpu_busy) @(posedge clk);
        @(posedge clk);
    endtask

    // =========================================================================
    // Instruction Encodings
    // =========================================================================
    // vsetvli x1, x0, e32, m1, ta, ma
    localparam VSETVLI_E32_M1 = 32'h0D0070D7;
    // vle32.v v8,  (x2)   rs1=x2  (R channel base = 0x00)
    localparam VLE32_V8_X2    = 32'h02016407;
    // vle32.v v11, (x3)   rs1=x3  (G channel base = 0x10)
    localparam VLE32_V11_X3   = 32'h0201A587;
    // vle32.v v11, (x4)   rs1=x4  (B channel base = 0x20)
    localparam VLE32_V11_X4   = 32'h02022587;
    // vmul.vv v10, v8, v9  (R × coeff_v9 — same as existing test)
    localparam VMUL_V10_V8_V9 = 32'h9684A5D7;
    // vmul.vv v12, v11, v9 (G × coeff_v9)
    //   funct6=100101 vm=1 vs2=v11=01011 vs1=v9=01001 OPMVV vd=v12=01100
    //   = 100101_1_01011_01001_010_01100_1010111
    //   = 1001011 01011 01001 010 01100 1010111
    //   = 0x96B4 A657 — verify:
    //   [31:26]=100101, [25]=1, [24:20]=01011=11, [19:15]=01001=9
    //   [14:12]=010, [11:7]=01100=12, [6:0]=1010111 ✓
    localparam VMUL_V12_V11_V9= 32'h96B4A657;
    // vadd.vv v10, v10, v12
    //   funct6=000000 vm=1 vs2=v12=01100 vs1=v10=01010 OPIVV vd=v10=01010
    //   = 000000_1_01100_01010_000_01010_1010111
    //   = 0x02CA 0557 — verify:
    //   [31:26]=000000, [25]=1, [24:20]=01100=12, [19:15]=01010=10
    //   [14:12]=000, [11:7]=01010=10, [6:0]=1010111 ✓
    localparam VADD_V10_V10_V12 = 32'h02CA0557;
    // vse32.v v10, (x5)   store Y result, rs1=x5 (Y base = 0x30)
    //   opcode=0100111 nf=000 mew=0 mop=00 vm=1 sumop=00000
    //   rs1=x5=00101 width=110 vs3=v10=01010
    //   = 000000_1_00000_00101_110_01010_0100111
    //   = 0x0202E527
    localparam VSE32_V10_X5   = 32'h0202E527;

    // =========================================================================
    // Main test
    // =========================================================================
    initial begin
        // ── DMEM init ────────────────────────────────────────────────────────
        // R channel @ byte 0x00 (word addrs 0..3): {100, 120, 80, 200}
        dmem[0]=100; dmem[1]=120; dmem[2]=80;  dmem[3]=200;
        // G channel @ byte 0x10 (word addrs 4..7): {50, 80, 30, 150}
        dmem[4]=50;  dmem[5]=80;  dmem[6]=30;  dmem[7]=150;
        // B channel @ byte 0x20 (word addrs 8..11): {10, 20, 40, 60}
        dmem[8]=10;  dmem[9]=20;  dmem[10]=40; dmem[11]=60;
        // Y output @ byte 0x30 (word addrs 12..15): cleared
        dmem[12]=0; dmem[13]=0; dmem[14]=0; dmem[15]=0;
        // Coefficient vector v9 will be seeded via load:
        // coeff @ byte 0x40 (word addrs 16..19): {77, 150, 29, 1}
        dmem[16]=77; dmem[17]=150; dmem[18]=29; dmem[19]=1;

        // ── Reset ────────────────────────────────────────────────────────────
        rst_n=0; instr_valid=0; instruction=0;
        rs1_scalar_data=0; rs2_scalar_data=0;
        repeat(4) @(posedge clk);
        rst_n=1;
        repeat(2) @(posedge clk);

        // ── Step 1: vsetvli ──────────────────────────────────────────────────
        $display("[%0t ns] >>> vsetvli x1, x0, e32, m1, ta, ma", $time);
        drive_instr(VSETVLI_E32_M1, 32'd0);
        @(posedge clk); while (!vpu_cfg_done) @(posedge clk);
        @(posedge clk);
        $display("[%0t ns]     vl=%0d", $time, csr_vl);

        // ── Step 2: load coeff vector v9 from 0x40 ──────────────────────────
        // vle32.v v9, (x6) — need x6 base=0x40=64
        // Encoding: vle32.v v9, (x6): rs1=x6=6=00110, vd=v9=01001
        //   = 000000_1_00000_00110_110_01001_0000111 = 0x02034487
        $display("[%0t ns] >>> vle32.v v9, (x6)  (load coeff {77,150,29,1})", $time);
        drive_instr(32'h02034487, 32'd64);   // x6=64 → byte 0x40
        @(posedge clk); while (vlsu_busy_o) @(posedge clk);
        @(posedge clk);
        show_vreg(5'd9, "v9");

        // ── Step 3: load R channel ───────────────────────────────────────────
        $display("[%0t ns] >>> vle32.v v8, (x2)  R={100,120,80,200}", $time);
        drive_instr(VLE32_V8_X2, 32'd0);    // x2=0 → byte 0x00
        wait_vls;
        show_vreg(5'd8, "v8(R)");

        // ── Step 4: v10 = v8 * v9  (R × coeff) ─────────────────────────────
        $display("[%0t ns] >>> vmul.vv v10, v8, v9  (R×coeff)", $time);
        drive_instr(VMUL_V10_V8_V9, 32'd0);
        wait_vpu;
        show_vreg(5'd10, "v10");

        // ── Step 5: load G channel ───────────────────────────────────────────
        $display("[%0t ns] >>> vle32.v v11, (x3)  G={50,80,30,150}", $time);
        drive_instr(VLE32_V11_X3, 32'd16);   // x3=16 → byte 0x10
        wait_vls;
        show_vreg(5'd11, "v11(G)");

        // ── Step 6: v12 = v11 * v9  (G × coeff) ────────────────────────────
        $display("[%0t ns] >>> vmul.vv v12, v11, v9  (G×coeff)", $time);
        drive_instr(VMUL_V12_V11_V9, 32'd0);
        wait_vpu;
        show_vreg(5'd12, "v12");

        // ── Step 7: v10 = v10 + v12  (R_y + G_y) ───────────────────────────
        $display("[%0t ns] >>> vadd.vv v10, v10, v12", $time);
        drive_instr(VADD_V10_V10_V12, 32'd0);
        wait_vpu;
        show_vreg(5'd10, "v10");

        // ── Step 8: load B channel ───────────────────────────────────────────
        $display("[%0t ns] >>> vle32.v v11, (x4)  B={10,20,40,60}", $time);
        drive_instr(VLE32_V11_X4, 32'd32);   // x4=32 → byte 0x20
        wait_vls;
        show_vreg(5'd11, "v11(B)");

        // ── Step 9: v12 = v11 * v9  (B × coeff) ────────────────────────────
        $display("[%0t ns] >>> vmul.vv v12, v11, v9  (B×coeff)", $time);
        drive_instr(VMUL_V12_V11_V9, 32'd0);
        wait_vpu;
        show_vreg(5'd12, "v12");

        // ── Step 10: v10 = v10 + v12  (final Y = R_y+G_y+B_y) ───────────────
        $display("[%0t ns] >>> vadd.vv v10, v10, v12  (final Y)", $time);
        drive_instr(VADD_V10_V10_V12, 32'd0);
        wait_vpu;
        show_vreg(5'd10, "v10(Y)");

        // ── Step 11: vse32.v v10, (x5)  store Y ─────────────────────────────
        $display("[%0t ns] >>> vse32.v v10, (x5)  store Y @ 0x30", $time);
        drive_instr(VSE32_V10_X5, 32'd48);   // x5=48 → byte 0x30
        wait_vls;
        $display("[%0t ns]     Y DMEM[12..15] = {%0d,%0d,%0d,%0d}",
                 $time, dmem[12], dmem[13], dmem[14], dmem[15]);

        // ── Summary ───────────────────────────────────────────────────────────
        $display("[%0t ns]", $time);
        $display("[%0t ns] === R×77 + G×150 + B×29 per pixel ===", $time);
        $display("[%0t ns]   pixel 0: R=100*77=%0d  G=50*150=%0d  B=10*29=%0d  sum=%0d",
                 $time, 100*77, 50*150, 10*29, 100*77+50*150+10*29);
        $display("[%0t ns]   pixel 1: R=120*77=%0d  G=80*150=%0d  B=20*29=%0d  sum=%0d",
                 $time, 120*77, 80*150, 20*29, 120*77+80*150+20*29);
        $display("[%0t ns]   (Note: sum > 256 here because we used mul not mulhu)", $time);

        repeat(5) @(posedge clk);
        $stop;
    end

endmodule
