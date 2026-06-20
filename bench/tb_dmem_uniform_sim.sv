`timescale 1ns/1ps
// tb_dmem_uniform_sim.sv — Debug: all pixels = same R,G,B. Expected Y = constant.
// If words 1-3 still mismatch with uniform input → VLSU write structural bug.
// If words 1-3 pass → bug is computation-specific to non-uniform pixel values.

module tb_dmem_uniform_sim;
    localparam int CLK_HALF  = 10;
    localparam int RST_CYCS  = 100;
    localparam int RUN_CYCS  = 80_000;

    // Uniform pixel values matching pixel 0 from lena
    localparam logic [7:0] R_VAL = 8'hE0;  // 224
    localparam logic [7:0] G_VAL = 8'h89;  // 137
    localparam logic [7:0] B_VAL = 8'h80;  // 128
    // Expected Y = R×77>>8 + G×150>>8 + B×29>>8 = 67+80+14 = 161 = 0xA1
    localparam logic [7:0] Y_EXP = 8'hA1;
    localparam logic [31:0] Y_WORD_EXP = {Y_EXP,Y_EXP,Y_EXP,Y_EXP};

    logic clk = 1'b0;
    logic reset;
    logic vpu_busy;

    riscv_vpu_top_fpga #(.UART_CLK_FREQ(50_000_000), .UART_BAUD_RATE(115_200)) dut (
        .i_clk(clk), .i_reset(reset), .i_io_sw(32'd0), .uart_rx(1'b1),
        .uart_tx(), .o_io_ledr(), .o_io_ledg(), .o_io_lcd(),
        .o_io_hex0(),.o_io_hex1(),.o_io_hex2(),.o_io_hex3(),.o_io_hex4(),.o_io_hex5(),
        .o_io_hex6(),.o_io_hex7(),
        .vga_r(),.vga_g(),.vga_b(),.vga_clk(),.vga_hs(),.vga_vs(),
        .vga_blank_n(),.vga_sync_n(),
        .o_pc_debug(),.o_insn_vld(),.o_vpu_cycles(),.o_vmask16(),
        .o_vpu_busy(vpu_busy),.o_fsm_state(),
        .o_wb_result_lane0(),.o_wb_result_lane1(),
        .o_wb_result_lane2(),.o_wb_result_lane3()
    );
    always #(CLK_HALF) clk = ~clk;

    // ── Monitor VRF lane1 writes for v1, v4, v7 (first 15 events) ───────────
    int vrf_cap_cnt = 0;
    always @(posedge clk) begin
        if (!reset && vrf_cap_cnt < 15) begin
            if (dut.u_vpu.vrf_lane1.write_en != 4'b0000 &&
                (dut.u_vpu.vrf_lane1.vd <= 5'd7)) begin
                $display("  t=%0t VRF lane1 write v%0d: data=0x%08X we=%04b",
                         $time, dut.u_vpu.vrf_lane1.vd,
                         dut.u_vpu.vrf_lane1.wdata, dut.u_vpu.vrf_lane1.write_en);
                vrf_cap_cnt++;
            end
        end
    end

    // ── Monitor VLSU writes to Y area ────────────────────────────────────────
    int vlsu_cap_cnt = 0;
    always @(posedge clk) begin
        if (!reset && dut.u_vpu.vlsu_mem_req && dut.u_vpu.vlsu_mem_we &&
            dut.u_vpu.vlsu_mem_addr >= 32'hC000 && vlsu_cap_cnt < 6) begin
            $display("  VLSU write[%0d]: addr=0x%08X data=0x%08X be=%04b",
                     vlsu_cap_cnt, dut.u_vpu.vlsu_mem_addr,
                     dut.u_vpu.vlsu_mem_wdata, dut.u_vpu.vlsu_mem_be);
            vlsu_cap_cnt++;
        end
    end

    int i;

    initial begin
        // Fill R channel (words 0-4095): all bytes = R_VAL
        for (i = 0; i < 4096; i++) begin
            dut.u_dmem.bank0.u.mem[i] = R_VAL;
            dut.u_dmem.bank1.u.mem[i] = R_VAL;
            dut.u_dmem.bank2.u.mem[i] = R_VAL;
            dut.u_dmem.bank3.u.mem[i] = R_VAL;
        end
        // Fill G channel (words 4096-8191)
        for (i = 4096; i < 8192; i++) begin
            dut.u_dmem.bank0.u.mem[i] = G_VAL;
            dut.u_dmem.bank1.u.mem[i] = G_VAL;
            dut.u_dmem.bank2.u.mem[i] = G_VAL;
            dut.u_dmem.bank3.u.mem[i] = G_VAL;
        end
        // Fill B channel (words 8192-12287)
        for (i = 8192; i < 12288; i++) begin
            dut.u_dmem.bank0.u.mem[i] = B_VAL;
            dut.u_dmem.bank1.u.mem[i] = B_VAL;
            dut.u_dmem.bank2.u.mem[i] = B_VAL;
            dut.u_dmem.bank3.u.mem[i] = B_VAL;
        end
        // Y area zeros (words 12288-16383)
        for (i = 12288; i < 16384; i++) begin
            dut.u_dmem.bank0.u.mem[i] = 8'h00;
            dut.u_dmem.bank1.u.mem[i] = 8'h00;
            dut.u_dmem.bank2.u.mem[i] = 8'h00;
            dut.u_dmem.bank3.u.mem[i] = 8'h00;
        end
        $display("[0 ns] DMEM uniform: R=0x%02X G=0x%02X B=0x%02X  Y_exp=0x%02X",
                 R_VAL, G_VAL, B_VAL, Y_EXP);

        reset = 1'b1;
        repeat (RST_CYCS) @(posedge clk);
        reset = 1'b0;

        repeat (RUN_CYCS) @(posedge clk);
        i = 0;
        while (vpu_busy && i < 2000) begin @(posedge clk); i++; end

        // ── Dump VRF content of v1 and v4 across all 4 lanes ─────────────────
        // v1 = register address 1, v4 = register address 4
        // lane0 = bits[31:0], lane1 = bits[63:32], etc.
        $display("  VRF v1 lane0=%08X lane1=%08X lane2=%08X lane3=%08X",
            dut.u_vpu.vrf_lane0.bank3[1]<<24|dut.u_vpu.vrf_lane0.bank2[1]<<16|dut.u_vpu.vrf_lane0.bank1[1]<<8|dut.u_vpu.vrf_lane0.bank0[1],
            dut.u_vpu.vrf_lane1.bank3[1]<<24|dut.u_vpu.vrf_lane1.bank2[1]<<16|dut.u_vpu.vrf_lane1.bank1[1]<<8|dut.u_vpu.vrf_lane1.bank0[1],
            dut.u_vpu.vrf_lane2.bank3[1]<<24|dut.u_vpu.vrf_lane2.bank2[1]<<16|dut.u_vpu.vrf_lane2.bank1[1]<<8|dut.u_vpu.vrf_lane2.bank0[1],
            dut.u_vpu.vrf_lane3.bank3[1]<<24|dut.u_vpu.vrf_lane3.bank2[1]<<16|dut.u_vpu.vrf_lane3.bank1[1]<<8|dut.u_vpu.vrf_lane3.bank0[1]);
        $display("  VRF v4 lane0=%08X lane1=%08X lane2=%08X lane3=%08X",
            dut.u_vpu.vrf_lane0.bank3[4]<<24|dut.u_vpu.vrf_lane0.bank2[4]<<16|dut.u_vpu.vrf_lane0.bank1[4]<<8|dut.u_vpu.vrf_lane0.bank0[4],
            dut.u_vpu.vrf_lane1.bank3[4]<<24|dut.u_vpu.vrf_lane1.bank2[4]<<16|dut.u_vpu.vrf_lane1.bank1[4]<<8|dut.u_vpu.vrf_lane1.bank0[4],
            dut.u_vpu.vrf_lane2.bank3[4]<<24|dut.u_vpu.vrf_lane2.bank2[4]<<16|dut.u_vpu.vrf_lane2.bank1[4]<<8|dut.u_vpu.vrf_lane2.bank0[4],
            dut.u_vpu.vrf_lane3.bank3[4]<<24|dut.u_vpu.vrf_lane3.bank2[4]<<16|dut.u_vpu.vrf_lane3.bank1[4]<<8|dut.u_vpu.vrf_lane3.bank0[4]);
        // Note: after 80000 cycles all iterations complete.
        // v1 shows LAST iteration load. v4 shows LAST vmulhu result.
        // But word[1] bug is in iteration 0 only — check DMEM directly.

        // Check all 4096 Y words
        begin
            int errs;
            logic [31:0] got;
            errs = 0;
            for (i = 0; i < 4096; i++) begin
                got = {dut.u_dmem.bank3.u.mem[12288+i], dut.u_dmem.bank2.u.mem[12288+i],
                       dut.u_dmem.bank1.u.mem[12288+i], dut.u_dmem.bank0.u.mem[12288+i]};
                if (got !== Y_WORD_EXP) begin
                    if (errs < 8)
                        $display("  MISMATCH word[%0d]: got=0x%08X exp=0x%08X",i,got,Y_WORD_EXP);
                    errs++;
                end
            end
            if (errs == 0)
                $display("[PASS] All 4096 Y words = 0x%08X (uniform input)", Y_WORD_EXP);
            else
                $display("[FAIL] %0d / 4096 words wrong (uniform input)", errs);
        end
        $finish;
    end

    initial begin
        #((RST_CYCS + RUN_CYCS + 3000) * CLK_HALF * 2 + 1000);
        $display("[FAIL] Watchdog"); $finish;
    end
endmodule
