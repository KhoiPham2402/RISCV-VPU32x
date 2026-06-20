// =============================================================================
// vga_timing.sv  —  800×600 @ 60 Hz timing generator (40 MHz pixel clock)
//
// VESA standard 800×600 @ 60 Hz, pixel clock = 40.000 MHz
//   H total = 1056 px  (800 active + 256 blank)
//   V total =  628 ln  ( 600 active +  28 blank)
//   HS: active HIGH, 128 px wide, starts at hc=840
//   VS: active HIGH,   4 lines,   starts at vc=601
//   Sync polarity: +H +V  (monitors auto-detect)
// =============================================================================
module vga_timing (
    input  logic        pclk,
    input  logic        rst_n,

    output logic [9:0]  hc,
    output logic [9:0]  vc,
    output logic        hs_n,   // kept active-low naming for port compat; see below
    output logic        vs_n,
    output logic        de
);
    localparam int H_ACTIVE = 800;
    localparam int H_FP     = 40;
    localparam int H_SYNC   = 128;
    localparam int H_BP     = 88;
    localparam int H_TOTAL  = H_ACTIVE + H_FP + H_SYNC + H_BP;  // 1056

    localparam int V_ACTIVE = 600;
    localparam int V_FP     = 1;
    localparam int V_SYNC   = 4;
    localparam int V_BP     = 23;
    localparam int V_TOTAL  = V_ACTIVE + V_FP + V_SYNC + V_BP;  // 628

    localparam int HS_START = H_ACTIVE + H_FP;  // 840
    localparam int VS_START = V_ACTIVE + V_FP;  // 601

    always_ff @(posedge pclk) begin
        if (!rst_n) begin
            hc <= '0;
            vc <= '0;
        end else begin
            if (hc == H_TOTAL - 1) begin
                hc <= '0;
                vc <= (vc == V_TOTAL - 1) ? '0 : vc + 1'b1;
            end else begin
                hc <= hc + 1'b1;
            end
        end
    end

    // 800×600 uses POSITIVE sync (+H +V).
    // Port names kept as hs_n/vs_n for interface compatibility;
    // signals are HIGH during sync pulse (positive polarity).
    assign hs_n = (hc >= HS_START) && (hc < HS_START + H_SYNC);  // HIGH = sync
    assign vs_n = (vc >= VS_START) && (vc < VS_START + V_SYNC);   // HIGH = sync
    assign de   = (hc < H_ACTIVE)  && (vc < V_ACTIVE);

endmodule
