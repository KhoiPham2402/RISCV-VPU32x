`timescale 1ns/1ps
// tb_vga_cdc.sv — VGA smoke test: gray + color mode, single-clock (no CDC)
//
// VGA now runs at sclk=40MHz (800x600@60Hz).
// DMEM and VGA share the same clock → 1-cycle deterministic latency.
//
// Tests:
//   Gray  mode (mode_i=0): DMEM Y channel pre-loaded with TEST_GRAY=0x89.
//                          Expect vga_r=vga_g=vga_b=0x89 in image area.
//   Color mode (mode_i=1): R channel=0xAA, G channel=0x55, B channel=0x11.
//                          Expect vga_r=0xAA, vga_g=0x55, vga_b=0x11.

module tb_vga_cdc;

    // Single clock, 40 MHz (matches new design — no CDC)
    logic clk = 0;
    always #12.5 clk = ~clk;

    logic rst_n = 0;

    // Behavioral DMEM (same clock, 1-cycle latency)
    logic [7:0] mem [0:16383];   // 16384 words × 8-bit (one bank)
    // For the test we use only lane 0: R/G/B/Y all in byte 0 of each word

    logic [13:0] vid_addr;
    logic        vid_re;
    logic [31:0] vid_rdata_i;
    logic [7:0]  port_q;

    // 1-cycle registered read (mimics M10K)
    always_ff @(posedge clk) begin
        if (vid_re) port_q <= mem[vid_addr];
        else        port_q <= 8'h00;
    end
    // Replicate byte to all lanes (since vga_ctrl extracts by byte_lane)
    assign vid_rdata_i = {port_q, port_q, port_q, port_q};

    // ── DUT ──────────────────────────────────────────────────────────────────
    logic [7:0] vga_r, vga_g, vga_b;
    logic vga_hs, vga_vs, vga_blank_n, vga_clk;
    logic mode;

    vga_ctrl dut (
        .pclk          (clk),
        .rst_n         (rst_n),
        .mode_i        (mode),
        .vid_addr_o    (vid_addr),
        .vid_re_o      (vid_re),
        .vid_rdata_i   (vid_rdata_i),
        .vga_r_o       (vga_r),
        .vga_g_o       (vga_g),
        .vga_b_o       (vga_b),
        .vga_clk_o     (vga_clk),
        .vga_hs_o      (vga_hs),
        .vga_vs_o      (vga_vs),
        .vga_blank_n_o (vga_blank_n),
        .vga_sync_n_o  ()
    );

    // ── Pre-load DMEM ─────────────────────────────────────────────────────────
    localparam logic [7:0] TEST_GRAY = 8'h89;
    localparam logic [7:0] TEST_R    = 8'hAA;
    localparam logic [7:0] TEST_G    = 8'h55;
    localparam logic [7:0] TEST_B    = 8'h11;

    initial begin
        // R channel: words 0-4095
        for (int w = 0; w < 4096; w++) mem[w] = TEST_R;
        // G channel: words 4096-8191
        for (int w = 4096; w < 8192; w++) mem[w] = TEST_G;
        // B channel: words 8192-12287
        for (int w = 8192; w < 12288; w++) mem[w] = TEST_B;
        // Y channel: words 12288-16383
        for (int w = 12288; w < 16384; w++) mem[w] = TEST_GRAY;
        $display("[TB] DMEM loaded: R=0x%02X G=0x%02X B=0x%02X Y=0x%02X",
                  TEST_R, TEST_G, TEST_B, TEST_GRAY);
    end

    // ── Reset ─────────────────────────────────────────────────────────────────
    initial begin
        mode  = 1'b0;
        rst_n = 1'b0;
        repeat (30) @(posedge clk);
        rst_n = 1'b1;
        $display("[TB] Reset released. 40 MHz single-clock, 800x600.");
    end

    // ── Monitor: check pixels in image area ───────────────────────────────────
    // 800x600: image at IMG_LEFT=208, IMG_TOP=108, 384x384
    // One frame = 1056x628 = 662,868 clocks.
    int gray_ok=0, gray_err=0;
    int col_ok=0,  col_err=0;
    logic gray_done=0, col_done=0;

    always @(posedge clk) begin
        #1;  // wait 1ps for FFs to settle before sampling
        if (rst_n && vga_blank_n) begin
            if (!mode && !gray_done) begin
                if (vga_r !== 8'h00 || vga_g !== 8'h00 || vga_b !== 8'h00) begin
                    if (vga_r === TEST_GRAY && vga_g === TEST_GRAY && vga_b === TEST_GRAY)
                        gray_ok++;
                    else begin
                        if (gray_err < 3)
                            $display("[GRAY ERR] R=%02X G=%02X B=%02X exp=%02X",
                                      vga_r, vga_g, vga_b, TEST_GRAY);
                        gray_err++;
                    end
                end
                if (gray_ok >= 500) gray_done = 1;
            end
            if (mode && !col_done) begin
                if (vga_r !== 8'h00 || vga_g !== 8'h00 || vga_b !== 8'h00) begin
                    if (vga_r === TEST_R && vga_g === TEST_G && vga_b === TEST_B)
                        col_ok++;
                    else begin
                        if (col_err < 3)
                            $display("[COL  ERR] R=%02X G=%02X B=%02X exp R=%02X G=%02X B=%02X",
                                      vga_r, vga_g, vga_b, TEST_R, TEST_G, TEST_B);
                        col_err++;
                    end
                end
                if (col_ok >= 500) col_done = 1;
            end
        end
    end

    // ── Sequence: gray for 1 frame, then color for 1 frame ────────────────────
    localparam int FRAME = 1056 * 628;

    initial begin
        // Gray mode
        wait (rst_n);
        repeat (FRAME + 100) @(posedge clk);

        $display("");
        $display("=== GRAY mode: %0d OK / %0d ERR ===", gray_ok, gray_err);
        if (gray_err == 0 && gray_ok > 0)
            $display("[PASS] Gray mode correct.");
        else
            $display("[FAIL] Gray mode wrong.");

        // Switch to color mode
        @(posedge clk); mode = 1'b1;
        $display("[TB] Switched to color mode.");

        repeat (FRAME + 100) @(posedge clk);

        $display("=== COLOR mode: %0d OK / %0d ERR ===", col_ok, col_err);
        if (col_err == 0 && col_ok > 0)
            $display("[PASS] Color mode correct.");
        else
            $display("[FAIL] Color mode wrong (possibly alignment issue).");

        $display("=== DONE ===");
        $finish;
    end

endmodule
