// =============================================================================
// tb_vpu_wave.sv — VPU Waveform Demo Testbench
//
// Drives vproc_system_wrapper directly (no scalar pipeline needed).
// Sequence: vsetvli → vle32.v v8 → vle32.v v9 → vadd.vv → vmul.vv → vredsum.vs
//
// Expected results:
//   v8  = {10, 20, 30, 40}    (loaded from DMEM[0..3])
//   v9  = {1,  2,  3,  4}     (loaded from DMEM[4..7])
//   v10 = {11, 22, 33, 44}    (vadd.vv v10, v8, v9)
//   v11 = {10, 40, 90, 160}   (vmul.vv v11, v8, v9)
//   v12[0] = 1+11+22+33+44 = 111 (vredsum.vs v12, v10, v9)
//
// Result verification uses direct VRF bank reads (hierarchical references),
// NOT wb_lane0..3 (which are combinatorial ALU outputs, incorrect post-exec).
//
// Signals to watch in ModelSim:
//   instr_name           — decoded instruction name (STRING)
//   fsm_state_name       — VPU FSM state name string
//   dut/fsm_inst/state_r — FSM state enum (auto-decoded by ModelSim)
//   dut/vlsu_inst/state_r — VLSU state enum
// =============================================================================
`timescale 1ns/1ps

module tb_vpu_wave;

    // =========================================================================
    // Clock / Reset
    // =========================================================================
    localparam CLK_PERIOD = 10;   // 100 MHz

    logic clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    logic rst_n;

    // =========================================================================
    // VPU Wrapper Interface
    // =========================================================================
    logic        instr_valid;
    logic [31:0] instruction;
    logic [31:0] rs1_scalar_data;
    logic [31:0] rs2_scalar_data;

    logic        vpu_ready;
    logic        vpu_cfg_done;
    logic [31:0] vpu_vl_remain;
    logic [3:0]  fsm_state;
    logic        vpu_busy;
    logic [15:0] vmask16;
    logic [3:0]  vpu_cycles;
    logic        fifo_full;
    logic [31:0] wb_lane0, wb_lane1, wb_lane2, wb_lane3;
    logic [31:0] csr_vl, csr_vtype, csr_vlenb;
    logic [31:0] csr_rdata;
    logic        vlsu_busy_o;

    // =========================================================================
    // VLSU DMEM Interface
    // =========================================================================
    logic        vlsu_req;
    logic        vlsu_we;
    logic [31:0] vlsu_addr;
    logic [ 3:0] vlsu_be;
    logic [31:0] vlsu_wdata;
    logic [31:0] vlsu_rdata;
    logic        vlsu_ready;

    // =========================================================================
    // DUT: vproc_system_wrapper
    // =========================================================================
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

    // =========================================================================
    // Simple Synchronous DMEM Model (matches M10K 1-cycle registered output)
    // =========================================================================
    // Use reg array so both initial and always can drive it (simulation-only).
    reg [31:0] dmem [0:1023];   // 4 KB word-addressed

    // Registered read + write — use always (not always_ff) to allow initial block.
    logic rd_pending_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_pending_r <= 1'b0;
            vlsu_rdata   <= 32'b0;
        end else begin
            rd_pending_r <= vlsu_req && !vlsu_we;
            if (vlsu_req) begin
                if (vlsu_we)
                    dmem[vlsu_addr[11:2]] <= vlsu_wdata;
                else
                    vlsu_rdata <= dmem[vlsu_addr[11:2]];
            end
        end
    end

    // vlsu_ready: write → same cycle; read → 1 cycle after request (M10K model)
    assign vlsu_ready = vlsu_we ? vlsu_req : rd_pending_r;

    // =========================================================================
    // Instruction Name Decoder (displayed in waveform as string)
    // =========================================================================
    string instr_name;
    always_comb begin
        if (!instr_valid) begin
            instr_name = "---";
        end else begin
            case (instruction[6:0])
                7'b1010111: begin          // OP-V
                    if (instruction[14:12] == 3'b111)
                        instr_name = "vsetvli";
                    else if (instruction[14:12] == 3'b010 &&
                             instruction[31:29] == 3'b000) begin
                        // vred* family: funct3=010 (OPMVV), funct6[5:3]=000
                        case (instruction[28:26])
                            3'b000: instr_name = "vredsum.vs";
                            3'b001: instr_name = "vredand.vs";
                            3'b010: instr_name = "vredor.vs";
                            3'b011: instr_name = "vredxor.vs";
                            3'b100: instr_name = "vredminu.vs";
                            3'b101: instr_name = "vredmin.vs";
                            3'b110: instr_name = "vredmaxu.vs";
                            3'b111: instr_name = "vredmax.vs";
                            default: instr_name = "vred?.vs";
                        endcase
                    end else if (instruction[14:12] == 3'b010 &&
                                 instruction[31:26] == 6'b100101)
                        instr_name = "vmul.vv";
                    else if (instruction[14:12] == 3'b000 &&
                             instruction[31:26] == 6'b000000)
                        instr_name = "vadd.vv";
                    else if (instruction[14:12] == 3'b000 &&
                             instruction[31:26] == 6'b000010)
                        instr_name = "vsub.vv";
                    else
                        instr_name = "OP-V";
                end
                7'b0000111: begin          // LOAD-FP (VLE)
                    case (instruction[14:12])
                        3'b000:  instr_name = "vle8.v";
                        3'b101:  instr_name = "vle16.v";
                        3'b110:  instr_name = "vle32.v";
                        default: instr_name = "vle?.v";
                    endcase
                end
                7'b0100111: begin          // STORE-FP (VSE)
                    case (instruction[14:12])
                        3'b000:  instr_name = "vse8.v";
                        3'b101:  instr_name = "vse16.v";
                        3'b110:  instr_name = "vse32.v";
                        default: instr_name = "vse?.v";
                    endcase
                end
                default: instr_name = "SCALAR";
            endcase
        end
    end

    // FSM state as readable string
    string fsm_state_name;
    always_comb begin
        case (fsm_state)
            4'd0: fsm_state_name = "ST_IDLE";
            4'd1: fsm_state_name = "ST_CONFIG";
            4'd2: fsm_state_name = "ST_EXEC";
            4'd3: fsm_state_name = "ST_WIDENL";
            4'd4: fsm_state_name = "ST_WIDENH";
            4'd5: fsm_state_name = "ST_MASKING";
            4'd6: fsm_state_name = "ST_FINAL_MASKING";
            4'd7: fsm_state_name = "ST_REDUCTION";
            4'd8: fsm_state_name = "ST_REDUCTION_DONE";
            default: fsm_state_name = "ST_???";
        endcase
    end

    // =========================================================================
    // VRF Direct Read (hierarchical) — bypasses combinatorial ALU path
    // Reads assembled 32-bit word from the 4-byte banks of one VRF lane instance.
    // =========================================================================
    function automatic logic [31:0] vrf_read_lane0(input [4:0] addr);
        return {dut.vrf_lane0.bank3[addr], dut.vrf_lane0.bank2[addr],
                dut.vrf_lane0.bank1[addr], dut.vrf_lane0.bank0[addr]};
    endfunction

    function automatic logic [31:0] vrf_read_lane1(input [4:0] addr);
        return {dut.vrf_lane1.bank3[addr], dut.vrf_lane1.bank2[addr],
                dut.vrf_lane1.bank1[addr], dut.vrf_lane1.bank0[addr]};
    endfunction

    function automatic logic [31:0] vrf_read_lane2(input [4:0] addr);
        return {dut.vrf_lane2.bank3[addr], dut.vrf_lane2.bank2[addr],
                dut.vrf_lane2.bank1[addr], dut.vrf_lane2.bank0[addr]};
    endfunction

    function automatic logic [31:0] vrf_read_lane3(input [4:0] addr);
        return {dut.vrf_lane3.bank3[addr], dut.vrf_lane3.bank2[addr],
                dut.vrf_lane3.bank1[addr], dut.vrf_lane3.bank0[addr]};
    endfunction

    // Display full 4-lane VRF register (elem0=lane0 ... elem3=lane3 for SEW=32)
    task automatic display_vreg(input [4:0] addr, input string name);
        $display("[%0t ns]   VRF[%-4s=%0d] = {e0=%0d, e1=%0d, e2=%0d, e3=%0d}",
                 $time, name, addr,
                 vrf_read_lane0(addr),
                 vrf_read_lane1(addr),
                 vrf_read_lane2(addr),
                 vrf_read_lane3(addr));
    endtask

    // =========================================================================
    // VRF Write Monitor — trace every write to the register file
    // =========================================================================
    always @(posedge clk) begin
        if (dut.vlsu_vrf_we) begin
            $display("[%0t ns] [VRF-WR VLSU] addr=%0d  l0=%0d l1=%0d l2=%0d l3=%0d",
                     $time, dut.vlsu_vrf_waddr,
                     dut.vlsu_vrf_wdata_l0, dut.vlsu_vrf_wdata_l1,
                     dut.vlsu_vrf_wdata_l2, dut.vlsu_vrf_wdata_l3);
        end
        if (dut.fsm_vrf_wren && (|dut.vrf_we0_eff || |dut.vrf_we1_eff ||
                                  |dut.vrf_we2_eff || |dut.vrf_we3_eff)) begin
            $display("[%0t ns] [VRF-WR FSM ] addr=%0d  l0=%0d l1=%0d l2=%0d l3=%0d  we={%b,%b,%b,%b}",
                     $time, dut.vd_addr_eff,
                     dut.vrf_wdata0_eff, dut.vrf_wdata1_eff,
                     dut.vrf_wdata2_eff, dut.vrf_wdata3_eff,
                     dut.vrf_we0_eff, dut.vrf_we1_eff,
                     dut.vrf_we2_eff, dut.vrf_we3_eff);
        end
    end

    // =========================================================================
    // Instruction Driver Task
    // =========================================================================
    // Holds instr_valid=1 for exactly 1 clock cycle when the VPU is ready.
    // rs1 provides the scalar register value (base addr for VLS, AVL for vsetvli).
    task automatic drive_instr(
        input [31:0] insn,
        input [31:0] rs1  = 32'd0,
        input [31:0] rs2  = 32'd0
    );
        // Wait for VPU to be ready to accept a new instruction
        @(posedge clk);
        while (!vpu_ready) @(posedge clk);
        #1;  // hold past rising edge

        instruction     = insn;
        rs1_scalar_data = rs1;
        rs2_scalar_data = rs2;
        instr_valid     = 1'b1;

        @(posedge clk); #1;  // one cycle of valid

        instr_valid = 1'b0;
        instruction = 32'b0;
    endtask

    // =========================================================================
    // Instruction Encodings (RVV 1.0 — verified against spec)
    // =========================================================================
    //   vsetvli x1, x0, e32, m1, ta, ma   = 0x0D0070D7
    //     [31:20]=zimm=0xD0(e32,m1,ta,ma) [19:15]=x0 [14:12]=111 [11:7]=x1 [6:0]=OP-V
    //
    //   vle32.v v8,  (x2)                 = 0x02016407
    //     [31:26]=000000 [25]=1 [24:20]=00000 [19:15]=00010(x2) [14:12]=110 [11:7]=01000(v8)
    //
    //   vle32.v v9,  (x3)                 = 0x0201E487
    //     [19:15]=00011(x3) [11:7]=01001(v9)
    //
    //   vadd.vv v10, v8,  v9              = 0x02940557
    //     funct6=000000 vm=1 vs2=v8=01000 vs1=v9=01001 funct3=000 vd=v10=01010
    //     Wait: bits[24:20]=vs2=v8=8, bits[19:15]=vs1=v9=9
    //     0x02940557: f6=000000 vm=1 vs2=01001=9? Let me verify:
    //     0x02940557 = 0000_0010_1001_0100_0000_0101_0101_0111
    //     [31:26]=000000 [25]=1 [24:20]=01001=9(vs2=v9) [19:15]=01000=8(vs1=v8)
    //     [14:12]=000 [11:7]=01010=10(vd=v10)
    //     → vadd.vv v10, vs2=v9, vs1=v8  (OPIVV: result = vs1+vs2 = v8+v9) ✓
    //
    //   vmul.vv v11, v8,  v9              = 0x9684A5D7
    //     funct6=100101 (VMUL) vm=1 vs2=v8=8 vs1=v9=9 OPMVV vd=v11=11
    //     0x9684A5D7: [31:26]=100101 [25]=1 [24:20]=01000=8(vs2=v8) [19:15]=01001=9(vs1=v9)
    //     [14:12]=010 [11:7]=01011=11(vd=v11) ✓
    //
    //   vredsum.vs v12, v10, v9           = 0x02A4A657
    //     funct6=000000 vm=1 vs2=v10=10 vs1=v9=9 OPMVV vd=v12=12
    //     Seed=vs1[0]=v9[0]=1, reduces vs2=v10={11,22,33,44}
    //     Result = 1+11+22+33+44 = 111 ✓

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        // --- Initialise DMEM ---
        // v8 source: DMEM word addresses 0..3  (byte addresses 0x00..0x0C)
        dmem[0] = 32'd10;
        dmem[1] = 32'd20;
        dmem[2] = 32'd30;
        dmem[3] = 32'd40;
        // v9 source: DMEM word addresses 4..7  (byte addresses 0x10..0x1C)
        dmem[4] = 32'd1;
        dmem[5] = 32'd2;
        dmem[6] = 32'd3;
        dmem[7] = 32'd4;

        // --- Reset ---
        rst_n       = 1'b0;
        instr_valid = 1'b0;
        instruction = 32'b0;
        rs1_scalar_data = 32'b0;
        rs2_scalar_data = 32'b0;
        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        // ----------------------------------------------------------------
        // Step 1: vsetvli x1, x0, e32, m1, ta, ma  →  vl = vlmax = 4
        // ----------------------------------------------------------------
        $display("[%0t ns] >>> vsetvli x1, x0, e32, m1, ta, ma", $time);
        drive_instr(32'h0D0070D7, 32'd0);
        @(posedge clk);
        while (!vpu_cfg_done) @(posedge clk);
        @(posedge clk);
        $display("[%0t ns]     CSR: vl=%0d  vtype=0x%02h", $time, csr_vl, csr_vtype[7:0]);

        // ----------------------------------------------------------------
        // Step 2: vle32.v v8, (x2)  — load {10,20,30,40} from DMEM[0..3]
        //   rs1 = 0 (byte base address = 0x00)
        // ----------------------------------------------------------------
        $display("[%0t ns] >>> vle32.v v8, (x2)  base=0x%08h", $time, 32'd0);
        drive_instr(32'h02016407, 32'd0);
        @(posedge clk);
        while (vlsu_busy_o) @(posedge clk);
        @(posedge clk);  // 1 extra cycle for VRF write to settle
        $display("[%0t ns]     After vle32.v v8:", $time);
        display_vreg(5'd8,  "v8");

        // ----------------------------------------------------------------
        // Step 3: vle32.v v9, (x3)  — load {1,2,3,4} from DMEM[4..7]
        //   rs1 = 16 (byte base address = 0x10)
        // ----------------------------------------------------------------
        $display("[%0t ns] >>> vle32.v v9, (x3)  base=0x%08h", $time, 32'd16);
        drive_instr(32'h0201E487, 32'd16);
        @(posedge clk);
        while (vlsu_busy_o) @(posedge clk);
        @(posedge clk);
        $display("[%0t ns]     After vle32.v v9:", $time);
        display_vreg(5'd9,  "v9");

        // ----------------------------------------------------------------
        // Step 4: vadd.vv v10, v8, v9  — v10 = v8 + v9 = {11,22,33,44}
        //   Encoding 0x02940557: vs2=v9(9), vs1=v8(8), vd=v10(10), OPIVV
        //
        // OP-V dispatch timing note: FIFO has no forwarding bypass → 1-cycle dispatch
        // latency.  At P_push+1 (active region) the FSM's state_r is still ST_IDLE
        // (NBA hasn't committed), so vpu_busy=0 and the while loop exits immediately.
        // Use repeat(2) @posedge first to land on P_push+2 where state_r=ST_EXEC (busy=1).
        // ----------------------------------------------------------------
        $display("[%0t ns] >>> vadd.vv v10, v8, v9", $time);
        drive_instr(32'h02940557, 32'd0);
        repeat(2) @(posedge clk);   // skip FIFO dispatch latency cycle
        while (vpu_busy) @(posedge clk);
        @(posedge clk);             // 1 extra: let VRF non-blocking assign settle
        $display("[%0t ns]     After vadd.vv v10, v8, v9:", $time);
        display_vreg(5'd10, "v10");
        $display("[%0t ns]     Expected: {11, 22, 33, 44}", $time);

        // ----------------------------------------------------------------
        // Step 5: vmul.vv v11, v8, v9  — v11 = v8 * v9 = {10,40,90,160}
        //   Encoding 0x9684A5D7: funct6=100101, vs2=v8(8), vs1=v9(9), OPMVV, vd=v11(11)
        // ----------------------------------------------------------------
        $display("[%0t ns] >>> vmul.vv v11, v8, v9", $time);
        drive_instr(32'h9684A5D7, 32'd0);
        repeat(2) @(posedge clk);
        while (vpu_busy) @(posedge clk);
        @(posedge clk);
        $display("[%0t ns]     After vmul.vv v11, v8, v9:", $time);
        display_vreg(5'd11, "v11");
        $display("[%0t ns]     Expected: {10, 40, 90, 160}", $time);

        // ----------------------------------------------------------------
        // Step 6: vredsum.vs v12, v10, v9
        //   Encoding 0x02A4A657: funct6=000000, OPMVV, vs2=v10(10), vs1=v9(9), vd=v12(12)
        //   vs1=v9 provides seed: v9[0]=1
        //   vs2=v10 is the vector to reduce: {11,22,33,44}
        //   result = seed + sum(vs2) = 1+11+22+33+44 = 111 → written to v12[elem0]
        //
        // Reduction takes ~8 FSM cycles (FIFO latency + init + 4 elem iterations +
        // REDUCTION_DONE write).  repeat(2) guarantees we enter the while loop while
        // the FSM is definitely inside ST_REDUCTION (busy=1).
        // ----------------------------------------------------------------
        $display("[%0t ns] >>> vredsum.vs v12, v10, v9", $time);
        drive_instr(32'h02A4A657, 32'd0);
        repeat(2) @(posedge clk);
        while (vpu_busy) @(posedge clk);
        @(posedge clk);
        $display("[%0t ns]     After vredsum.vs v12, v10, v9:", $time);
        display_vreg(5'd12, "v12");
        $display("[%0t ns]     Expected: {111, 0, 0, 0}  (only e0 written)", $time);

        // ----------------------------------------------------------------
        // Summary / Pass-Fail
        // ----------------------------------------------------------------
        $display("[%0t ns]", $time);
        $display("[%0t ns] === Verification Summary ===", $time);
        begin
            logic [31:0] v8e0, v8e1, v8e2, v8e3;
            logic [31:0] v9e0, v9e1, v9e2, v9e3;
            logic [31:0] v10e0, v10e1, v10e2, v10e3;
            logic [31:0] v11e0, v11e1, v11e2, v11e3;
            logic [31:0] v12e0;
            integer pass_cnt, fail_cnt;

            v8e0  = vrf_read_lane0(5'd8);  v8e1  = vrf_read_lane1(5'd8);
            v8e2  = vrf_read_lane2(5'd8);  v8e3  = vrf_read_lane3(5'd8);
            v9e0  = vrf_read_lane0(5'd9);  v9e1  = vrf_read_lane1(5'd9);
            v9e2  = vrf_read_lane2(5'd9);  v9e3  = vrf_read_lane3(5'd9);
            v10e0 = vrf_read_lane0(5'd10); v10e1 = vrf_read_lane1(5'd10);
            v10e2 = vrf_read_lane2(5'd10); v10e3 = vrf_read_lane3(5'd10);
            v11e0 = vrf_read_lane0(5'd11); v11e1 = vrf_read_lane1(5'd11);
            v11e2 = vrf_read_lane2(5'd11); v11e3 = vrf_read_lane3(5'd11);
            v12e0 = vrf_read_lane0(5'd12);

            pass_cnt = 0; fail_cnt = 0;

            // v8
            if (v8e0==10 && v8e1==20 && v8e2==30 && v8e3==40) begin
                pass_cnt++; $display("  [PASS] v8  = {10,20,30,40}");
            end else begin
                fail_cnt++;
                $display("  [FAIL] v8  = {%0d,%0d,%0d,%0d}  expected {10,20,30,40}",
                         v8e0,v8e1,v8e2,v8e3);
            end

            // v9
            if (v9e0==1 && v9e1==2 && v9e2==3 && v9e3==4) begin
                pass_cnt++; $display("  [PASS] v9  = {1,2,3,4}");
            end else begin
                fail_cnt++;
                $display("  [FAIL] v9  = {%0d,%0d,%0d,%0d}  expected {1,2,3,4}",
                         v9e0,v9e1,v9e2,v9e3);
            end

            // v10 = vadd
            if (v10e0==11 && v10e1==22 && v10e2==33 && v10e3==44) begin
                pass_cnt++; $display("  [PASS] v10 = {11,22,33,44}");
            end else begin
                fail_cnt++;
                $display("  [FAIL] v10 = {%0d,%0d,%0d,%0d}  expected {11,22,33,44}",
                         v10e0,v10e1,v10e2,v10e3);
            end

            // v11 = vmul
            if (v11e0==10 && v11e1==40 && v11e2==90 && v11e3==160) begin
                pass_cnt++; $display("  [PASS] v11 = {10,40,90,160}");
            end else begin
                fail_cnt++;
                $display("  [FAIL] v11 = {%0d,%0d,%0d,%0d}  expected {10,40,90,160}",
                         v11e0,v11e1,v11e2,v11e3);
            end

            // v12 = vredsum
            if (v12e0 == 32'd111) begin
                pass_cnt++; $display("  [PASS] v12[0] = 111");
            end else begin
                fail_cnt++;
                $display("  [FAIL] v12[0] = %0d  expected 111", v12e0);
            end

            $display("  ─────────────────────────");
            $display("  TOTAL: %0d PASS / %0d FAIL", pass_cnt, fail_cnt);
            if (fail_cnt == 0)
                $display("  ALL TESTS PASSED");
            else
                $display("  SOME TESTS FAILED — check VRF write monitor above");
        end

        repeat(5) @(posedge clk);
        $stop;
    end

endmodule
