`timescale 1ns / 1ps
// =============================================================================
// tb_vlsu_masked_store_wave.sv  —  VSE8.v masked store waveform capture
//
// Demonstrates a 3-word (vl=12, SEW=8) masked store where mask=0x555:
//   elements 0,2,4,6,8,10 active   → mem_be = 4'b0101 every word
//   elements 1,3,5,7,9,11 masked   → byte-lanes 1,3 suppressed
//
// Run: vsim -do run_vlsu_masked_wave.do
// =============================================================================
module tb_vlsu_masked_store_wave;

    // -------------------------------------------------------------------------
    // DUT signals (same as tb_vproc_vlsu)
    // -------------------------------------------------------------------------
    reg         clk, rst_n;
    reg         instr_valid;
    reg  [31:0] instruction;
    reg  [31:0] rs1_scalar_data;
    reg  [31:0] rs2_scalar_data;
    reg         vrf_commit_en;

    wire [3:0]  cycles;
    wire [15:0] vmask16;
    wire        fifo_full, busy;
    wire [3:0]  fsm_state;
    wire [31:0] wb_result_lane0, wb_result_lane1,
                wb_result_lane2, wb_result_lane3;
    wire        vpu_ready, vpu_cfg_done;
    wire [31:0] vpu_vl_remain;
    wire [31:0] csr_vl_o, csr_vtype_o, csr_vlenb_o;
    wire [11:0] scalar_csr_addr_w;
    wire [31:0] scalar_csr_rdata;

    wire        vlsu_mem_req, vlsu_mem_we;
    wire [31:0] vlsu_mem_addr;
    wire [ 3:0] vlsu_mem_be;
    wire [31:0] vlsu_mem_wdata;
    reg  [31:0] vlsu_mem_rdata;
    wire        vlsu_busy_o;
    // Mock DMEM is combinatorial (0-cycle) → always ready
    wire        vlsu_mem_ready = 1'b1;

    vproc_system_wrapper dut (
        .clk             (clk),          .rst_n           (rst_n),
        .instr_valid     (instr_valid),  .instruction     (instruction),
        .rs1_scalar_data (rs1_scalar_data),
        .rs2_scalar_data (rs2_scalar_data),
        .vrf_commit_en   (vrf_commit_en),
        .cycles(cycles), .vmask16(vmask16), .fifo_full(fifo_full),
        .busy(busy),     .fsm_state(fsm_state),
        .wb_result_lane0(wb_result_lane0), .wb_result_lane1(wb_result_lane1),
        .wb_result_lane2(wb_result_lane2), .wb_result_lane3(wb_result_lane3),
        .vpu_ready(vpu_ready), .vpu_cfg_done(vpu_cfg_done),
        .vpu_vl_remain(vpu_vl_remain),
        .csr_vl_o(csr_vl_o), .csr_vtype_o(csr_vtype_o), .csr_vlenb_o(csr_vlenb_o),
        .scalar_csr_addr (scalar_csr_addr_w),
        .scalar_csr_rdata(scalar_csr_rdata),
        .vlsu_mem_req   (vlsu_mem_req),  .vlsu_mem_we    (vlsu_mem_we),
        .vlsu_mem_addr  (vlsu_mem_addr), .vlsu_mem_be    (vlsu_mem_be),
        .vlsu_mem_wdata (vlsu_mem_wdata),.vlsu_mem_rdata (vlsu_mem_rdata),
        .vlsu_mem_ready (vlsu_mem_ready),.vlsu_busy_o    (vlsu_busy_o)
    );
    assign scalar_csr_addr_w = 12'h000;

    // -------------------------------------------------------------------------
    // Mock DMEM (4 KB, byte-enable write)
    // -------------------------------------------------------------------------
    reg [31:0] dmem [0:1023];

    // Synchronous read (1-cycle latency) to match vproc_vec_lsu prefetch pipeline
    always @(posedge clk) begin
        if (vlsu_mem_req && vlsu_mem_we) begin
            if (vlsu_mem_be[0]) dmem[vlsu_mem_addr[11:2]][ 7: 0] <= vlsu_mem_wdata[ 7: 0];
            if (vlsu_mem_be[1]) dmem[vlsu_mem_addr[11:2]][15: 8] <= vlsu_mem_wdata[15: 8];
            if (vlsu_mem_be[2]) dmem[vlsu_mem_addr[11:2]][23:16] <= vlsu_mem_wdata[23:16];
            if (vlsu_mem_be[3]) dmem[vlsu_mem_addr[11:2]][31:24] <= vlsu_mem_wdata[31:24];
        end
        vlsu_mem_rdata <= dmem[vlsu_mem_addr[11:2]]; // registered read, 1-cycle latency
    end
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Instruction encoders
    // -------------------------------------------------------------------------
    localparam [6:0]  OPCODE_OPV  = 7'b101_0111;
    localparam [10:0] ZIMM_E8_M1  = 11'h0C0;

    function automatic [31:0] build_vsetvli(input [10:0] z, input [4:0] vd, input [4:0] rs1);
        build_vsetvli = {1'b0, z, rs1, 3'b111, vd, OPCODE_OPV};
    endfunction

    function automatic [31:0] build_vle8(input [4:0] vd);
        build_vle8 = 32'd0;
        build_vle8[6:0]=7'b0000111; build_vle8[11:7]=vd;
        build_vle8[14:12]=3'b000;   build_vle8[25]=1'b1; // unmasked
    endfunction

    function automatic [31:0] build_vse8_masked(input [4:0] vs3);
        // vm=0 (bit[25]=0) → masked store
        build_vse8_masked = 32'd0;
        build_vse8_masked[6:0]=7'b0100111; build_vse8_masked[11:7]=vs3;
        build_vse8_masked[14:12]=3'b000;   // e8, bit[25] stays 0 → vm=0
    endfunction

    // -------------------------------------------------------------------------
    // Handshake tasks
    // -------------------------------------------------------------------------
    task automatic issue(input [31:0] inst, input [31:0] rs1v, input [31:0] rs2v);
        @(negedge clk);
        instruction=inst; rs1_scalar_data=rs1v; rs2_scalar_data=rs2v;
        instr_valid=1'b1;
        @(negedge clk); instr_valid=1'b0;
    endtask

    task automatic wait_idle;
        int t=0;
        while ((vpu_ready===1'b0 || busy===1'b1) && t<5000) begin @(posedge clk); t++; end
        @(posedge clk); @(posedge clk);
    endtask

    // -------------------------------------------------------------------------
    // Testbench body
    // -------------------------------------------------------------------------
    initial begin
        // --- DMEM init ---------------------------------------------------------
        for (int i=0; i<1024; i++) dmem[i] = 32'h00000000;

        // Mask @ byte 0x080 (word 32):
        // v0_mask_flat[7:0]  = vrf_lane0.bank0[0] = DMEM[32] byte0 = 0x55 = 01010101
        //   → elements 0,2,4,6 active (bits 0,2,4,6 of 0x55)
        // v0_mask_flat[15:8] = vrf_lane0.bank1[0] = DMEM[32] byte1 = 0x05 = 00000101
        //   → elements 8,10 active (bits 8,10 of v0_flat)
        // Result: be=4'b0101 for all 3 words (elements 0,2 | 4,6 | 8,10 active)
        dmem[32] = 32'h00000555;   // byte0=0x55 (elems 0-7 mask), byte1=0x05 (elems 8-15 mask)

        // Source data @ byte 0x100 (word 64..66):
        dmem[64] = 32'hD4C3B2A1;   // src elements 0-3
        dmem[65] = 32'hE8D7C6B5;   // src elements 4-7
        dmem[66] = 32'hFCFBEA09;   // src elements 8-11

        // --- Signals -----------------------------------------------------------
        clk=0; rst_n=0; instr_valid=0; vrf_commit_en=1;
        rs1_scalar_data=0; rs2_scalar_data=0; instruction=0;

        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        // --- Step 1: configure vl=16, SEW=8, LMUL=1 --------------------------
        $display("[%0t] vsetvli vl=16, e8, m1", $time);
        issue(build_vsetvli(ZIMM_E8_M1, 5'd1, 5'd1), 32'd16, 32'd0);
        wait_idle();

        // --- Step 2: vle8.v v0, (0x080) → load mask register -----------------
        $display("[%0t] vle8.v v0, (0x080) — load mask", $time);
        issue(build_vle8(5'd0), 32'h00000080, 32'd0);
        wait_idle();

        // --- Step 3: vle8.v v1, (0x100) → load source data -------------------
        $display("[%0t] vle8.v v1, (0x100) — load src data", $time);
        issue(build_vle8(5'd1), 32'h00000100, 32'd0);
        wait_idle();

        // --- Step 4: reconfigure vl=12 ----------------------------------------
        $display("[%0t] vsetvli vl=12, e8, m1", $time);
        issue(build_vsetvli(ZIMM_E8_M1, 5'd1, 5'd1), 32'd12, 32'd0);
        wait_idle();

        // --- Step 5: vse8.v v1, (0x200), vm=0 — 3-word masked store ----------
        $display("[%0t] vse8.v v1, (0x200), vm=0 — MASKED STORE (vl=12)", $time);
        issue(build_vse8_masked(5'd1), 32'h00000200, 32'd0);
        wait_idle();

        $display("=== Result ===");
        // Expected: bytes 0,2 of each word written; bytes 1,3 (masked) stay 0
        $display("dmem[0x200]=0x%08X  exp=0x00C300A1  (elems 0,2 active; 1,3 masked)", dmem[128]);
        $display("dmem[0x204]=0x%08X  exp=0x00D700B5  (elems 4,6 active; 5,7 masked)", dmem[129]);
        $display("dmem[0x208]=0x%08X  exp=0x00FB0009  (elems 8,10 active; 9,11 masked)", dmem[130]);
        $display("=== DONE — screenshot the wave window now ===");
        #100;
        $finish;
    end

endmodule
