// =============================================================================
// vga_ctrl.sv  —  VGA output controller, 800×600 @ 60 Hz, sclk = 40 MHz
//
// Running VGA at sclk (40 MHz) eliminates CDC with DMEM (also sclk).
// DMEM read latency = exactly 1 sclk cycle → deterministic, no metastability.
//
// mode_i:
//   0 = GRAYSCALE : reads Y channel (words 12288-16383), R=G=B=Y_byte
//   1 = COLOR RGB  : 3-phase read — each source pixel (128×128) is displayed
//                    3× (384×384 in the 800×600 frame).  Three consecutive
//                    display cycles read R/G/B channels respectively.
//                    r_reg/g_reg/b_reg accumulate per source pixel.
//
// DMEM word layout (words 0–16383, 4 bytes/word):
//   0–4095    R channel  (b0[w]=R[4w], b1[w]=R[4w+1], ...)
//   4096–8191 G channel
//   8192–12287 B channel
//   12288–16383 Y channel (grayscale, pre-loaded by gen_y_mif.py)
//
// Image placement in 800×600:
//   3× scale → 384×384 px, centered:
//   IMG_LEFT = (800-384)/2 = 208,  IMG_TOP = (600-384)/2 = 108
// =============================================================================
module vga_ctrl (
    input  logic        pclk,       // 40 MHz system clock (= sclk from PLL)
    input  logic        rst_n,
    input  logic        mode_i,     // 0 = grayscale, 1 = color RGB

    output logic [13:0] vid_addr_o,
    output logic        vid_re_o,
    input  logic [31:0] vid_rdata_i,  // DMEM read data, 1-cycle latency, same clock

    output logic [7:0]  vga_r_o,
    output logic [7:0]  vga_g_o,
    output logic [7:0]  vga_b_o,
    output logic        vga_clk_o,
    output logic        vga_hs_o,
    output logic        vga_vs_o,
    output logic        vga_blank_n_o,
    output logic        vga_sync_n_o
);

    // ── VGA timing (800×600 @ 60 Hz) ─────────────────────────────────────────
    logic [9:0] hc, vc;
    logic hs, vs, de;

    vga_timing u_timing (
        .pclk  (pclk),
        .rst_n (rst_n),
        .hc    (hc),
        .vc    (vc),
        .hs_n  (hs),    // positive polarity for 800×600
        .vs_n  (vs),
        .de    (de)
    );

    // ── Image parameters ─────────────────────────────────────────────────────
    localparam int IMG_LEFT  = 208;   // (800-384)/2
    localparam int IMG_TOP   = 108;   // (600-384)/2
    localparam int IMG_SCALE = 3;     // 3× gives 384×384

    // ── 1-cycle-ahead address generation ─────────────────────────────────────
    logic [9:0] hc_next, vc_next;
    assign hc_next = (hc == 1055) ? 10'd0 : hc + 1'b1;
    assign vc_next = (hc == 1055) ? ((vc == 627) ? 10'd0 : vc + 1'b1) : vc;

    logic in_img_next;
    assign in_img_next =
        (hc_next >= IMG_LEFT) && (hc_next < IMG_LEFT + 384) &&
        (vc_next >= IMG_TOP)  && (vc_next < IMG_TOP  + 384);

    logic [6:0] row_next, col_next;
    assign row_next = (vc_next - IMG_TOP)  / IMG_SCALE;
    assign col_next = (hc_next - IMG_LEFT) / IMG_SCALE;

    // Color phase (0=R, 1=G, 2=B) within each 3-display-pixel source pixel
    logic [1:0] phase_next;
    assign phase_next = (hc_next - IMG_LEFT) % IMG_SCALE;

    // DMEM word offset within channel: same for all channels
    wire [13:0] woff = {row_next, 5'b0} + {9'b0, col_next[6:2]};

    // Address mux
    always_comb begin
        if (!mode_i) begin
            vid_addr_o = 14'd12288 + woff;          // Y channel
        end else begin
            case (phase_next)
                2'd0:    vid_addr_o = woff;               // R: base 0
                2'd1:    vid_addr_o = 14'd4096  + woff;   // G: base 4096
                default: vid_addr_o = 14'd8192  + woff;   // B: base 8192
            endcase
        end
    end
    assign vid_re_o = in_img_next;

    // ── Stage 1: delay control signals 1 cycle ────────────────────────────────
    logic       de_r, hs_r, vs_r, in_img_r;
    logic [1:0] byte_lane_r, phase_r;

    always_ff @(posedge pclk) begin
        if (!rst_n) begin
            de_r        <= 1'b0;
            hs_r        <= 1'b0;
            vs_r        <= 1'b0;
            in_img_r    <= 1'b0;
            byte_lane_r <= 2'b0;
            phase_r     <= 2'b0;
        end else begin
            de_r        <= de;
            hs_r        <= hs;
            vs_r        <= vs;
            in_img_r    <= in_img_next;
            byte_lane_r <= col_next[1:0];
            phase_r     <= phase_next;
        end
    end

    // ── DMEM read arrives here (1-cycle latency, same clock domain) ───────────
    // vid_rdata_i at cycle T+1 contains data for vid_addr_o presented at T.
    // vid_rdata_i is in the SAME clock domain (sclk), no CDC needed.

    // ── Color channel pipeline ────────────────────────────────────────────────
    // R arrives at phase_r==0, G at 1, B at 2.
    // Problem if latched separately: the 3 display pixels of one source pixel
    // would show R from pixel P but G/B from pixel P-1 → color fringing.
    // Fix: accumulate R and G into holding registers, then latch ALL THREE at
    // the moment phase 2 (B) arrives.  All channels update together, so every
    // 3-pixel display block shows the consistent RGB of one source pixel.
    logic [7:0] r_hold, g_hold;   // accumulate R,G until B completes
    logic [7:0] r_out, g_out, b_out;   // stable output for 3 display cycles

    always_ff @(posedge pclk) begin
        if (!rst_n) begin
            r_hold <= 8'h00;  g_hold <= 8'h00;
            r_out  <= 8'h00;  g_out  <= 8'h00;  b_out <= 8'h00;
        end else if (mode_i && in_img_r) begin
            case (phase_r)
                2'd0: r_hold <= vid_rdata_i[byte_lane_r * 8 +: 8];  // save R
                2'd1: g_hold <= vid_rdata_i[byte_lane_r * 8 +: 8];  // save G
                2'd2: begin   // B arrived — commit all three simultaneously
                    r_out <= r_hold;
                    g_out <= g_hold;
                    b_out <= vid_rdata_i[byte_lane_r * 8 +: 8];
                end
                default: ;
            endcase
        end
    end

    // ── Output stage ─────────────────────────────────────────────────────────
    logic [7:0] y_px;
    assign y_px = vid_rdata_i[byte_lane_r * 8 +: 8];

    logic [7:0] out_r, out_g, out_b;
    always_comb begin
        if (!mode_i) begin
            out_r = in_img_r ? y_px : 8'h00;
            out_g = in_img_r ? y_px : 8'h00;
            out_b = in_img_r ? y_px : 8'h00;
        end else begin
            out_r = in_img_r ? r_out : 8'h00;
            out_g = in_img_r ? g_out : 8'h00;
            out_b = in_img_r ? b_out : 8'h00;
        end
    end

    always_ff @(posedge pclk) begin
        if (!rst_n) begin
            vga_r_o       <= 8'h00;
            vga_g_o       <= 8'h00;
            vga_b_o       <= 8'h00;
            vga_hs_o      <= 1'b0;
            vga_vs_o      <= 1'b0;
            vga_blank_n_o <= 1'b0;
        end else begin
            vga_r_o       <= de_r ? out_r : 8'h00;
            vga_g_o       <= de_r ? out_g : 8'h00;
            vga_b_o       <= de_r ? out_b : 8'h00;
            vga_hs_o      <= hs_r;
            vga_vs_o      <= vs_r;
            vga_blank_n_o <= de_r;
        end
    end

    assign vga_clk_o    = pclk;   // 40 MHz → ADV7123
    assign vga_sync_n_o = 1'b0;

endmodule
