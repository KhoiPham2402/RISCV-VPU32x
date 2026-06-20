// =============================================================================
// hdmi_ctrl.sv  —  HDMI output controller for DE10-Standard (ADV7513)
//
// Reads the 128×128 grayscale Y channel from dmem (words 12288–16383,
// byte address 0xC000–0xFFFF) and scales it 3× to fill a 384×384 region
// centered on a 640×480 frame.
//
// Pixel mapping:
//   Screen pixel (hc, vc) within active region [128..511] × [48..431]
//   → frame_row = (vc - 48) / 3     (0..127)
//   → frame_col = (hc - 128) / 3    (0..127)
//   → word_addr = 12288 + frame_row * 32 + frame_col / 4
//   → byte_lane = frame_col % 4
//   → Y_byte    = dmem_word[byte_lane*8 +: 8]
//   → RGB888    = {Y,Y,Y}  (grayscale)
//
// The read pipeline is: issue addr at pixel N-1 → data valid at pixel N.
// One cycle pre-fetch address.
// =============================================================================
module hdmi_ctrl #(
    parameter int CLK_FREQ  = 50_000_000,
    parameter int PCLK_FREQ = 25_000_000
) (
    // System clock (50 MHz) for I2C
    input  logic        clk_sys,
    input  logic        rst_n,

    // Pixel clock (25 MHz from PLL)
    input  logic        pclk,

    // DMEM video read port (pixel clock domain)
    output logic [13:0] vid_addr_o,   // word address into dmem
    output logic        vid_re_o,     // read enable
    input  logic [31:0] vid_rdata_i,  // word data (1-cycle latency)

    // HDMI output to ADV7513
    output logic [23:0] hdmi_d_o,     // RGB888 (R=D[23:16], G=D[15:8], B=D[7:0])
    output logic        hdmi_clk_o,
    output logic        hdmi_hs_o,
    output logic        hdmi_vs_o,
    output logic        hdmi_de_o,

    // I2C to ADV7513
    output logic        hdmi_scl_o,
    inout  wire         hdmi_sda_io
);

    // ── VGA timing ────────────────────────────────────────────────────────────
    logic [9:0] hc, vc;
    logic hs_n, vs_n, de;

    vga_timing u_timing (
        .pclk  (pclk),
        .rst_n (rst_n),
        .hc    (hc),
        .vc    (vc),
        .hs_n  (hs_n),
        .vs_n  (vs_n),
        .de    (de)
    );

    // ── ADV7513 I2C configuration ─────────────────────────────────────────────
    adv7513_cfg #(.CLK_FREQ(CLK_FREQ)) u_cfg (
        .clk       (clk_sys),
        .rst_n     (rst_n),
        .cfg_done_o(),
        .i2c_scl_o (hdmi_scl_o),
        .i2c_sda_io(hdmi_sda_io)
    );

    // ── Frame buffer address logic ────────────────────────────────────────────
    // Image region: hc=[128..511], vc=[48..431]
    localparam int IMG_LEFT = 128;
    localparam int IMG_TOP  = 48;

    logic        in_img;
    logic [6:0]  frame_row, frame_col;
    logic [13:0] next_word_addr;
    logic [1:0]  next_byte_lane;

    // Compute for NEXT pixel (one cycle ahead for 1-cycle DMEM latency)
    logic [9:0] hc_next, vc_next;
    assign hc_next = (hc == 799) ? 10'd0 : hc + 1'b1;
    assign vc_next = (hc == 799) ? ((vc == 524) ? 10'd0 : vc + 1'b1) : vc;

    logic in_img_next;
    assign in_img_next = (hc_next >= IMG_LEFT) && (hc_next < IMG_LEFT + 384) &&
                         (vc_next >= IMG_TOP)  && (vc_next < IMG_TOP  + 384);

    logic [6:0] row_next, col_next;
    assign row_next = (vc_next - IMG_TOP)  / 3;
    assign col_next = (hc_next - IMG_LEFT) / 3;

    assign next_word_addr = 14'd12288 + {row_next, 5'b0} + {9'b0, col_next[6:2]};
    assign next_byte_lane = col_next[1:0];

    // Issue DMEM read one cycle early
    assign vid_addr_o = next_word_addr;
    assign vid_re_o   = in_img_next;

    // ── Pixel data pipeline ───────────────────────────────────────────────────
    // vid_rdata_i is valid 1 cycle after vid_re_o
    // We need to delay de, hs_n, vs_n by 1 cycle to match
    logic       de_r, hs_r, vs_r;
    logic [1:0] byte_lane_r;
    logic       in_img_r;

    always_ff @(posedge pclk) begin
        if (!rst_n) begin
            de_r        <= 1'b0;
            hs_r        <= 1'b1;
            vs_r        <= 1'b1;
            in_img_r    <= 1'b0;
            byte_lane_r <= 2'b0;
        end else begin
            de_r        <= de;
            hs_r        <= hs_n;
            vs_r        <= vs_n;
            in_img_r    <= in_img_next;
            byte_lane_r <= next_byte_lane;
        end
    end

    // Extract Y byte from word
    logic [7:0] y_pixel;
    assign y_pixel = vid_rdata_i[byte_lane_r * 8 +: 8];

    // RGB output: grayscale → RGB888; black outside image region
    logic [7:0] out_px;
    assign out_px   = in_img_r ? y_pixel : 8'h00;
    assign hdmi_d_o = de_r ? {out_px, out_px, out_px} : 24'h000000;

    assign hdmi_clk_o = pclk;
    assign hdmi_hs_o  = hs_r;
    assign hdmi_vs_o  = vs_r;
    assign hdmi_de_o  = de_r;

endmodule
