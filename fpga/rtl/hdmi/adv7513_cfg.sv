// =============================================================================
// adv7513_cfg.sv  —  One-shot ADV7513 I2C configuration sequence
//
// Sends 14 register writes at power-on via i2c_master.
// Each register write is a 3-byte I2C transaction:
//   START + addr(W) + ACK + reg_addr + ACK + reg_val + ACK + STOP
//
// Because i2c_master sends START+addr+byte and then STOP per call,
// we need two consecutive calls to write one register:
//   Phase 0: start_i with slave_addr, rw=0, data=reg_addr
//   Phase 1: start_i with slave_addr, rw=0, data=reg_val   (repeated write)
//
// done_o pulses high once all registers are written.
// =============================================================================
module adv7513_cfg #(
    parameter int CLK_FREQ = 50_000_000
) (
    input  logic clk,
    input  logic rst_n,

    output logic cfg_done_o,    // pulses 1 cycle when all writes complete

    // I2C pads (to top-level)
    output logic i2c_scl_o,
    inout  wire  i2c_sda_io
);
    // ADV7513 7-bit I2C address
    localparam logic [6:0] ADV_ADDR = 7'h39;

    // Register init table: {reg_addr[7:0], reg_val[7:0]}
    localparam int N_REGS = 14;
    logic [15:0] cfg_table [0:N_REGS-1];

    initial begin
        cfg_table[0]  = {8'h41, 8'h10};  // power on
        cfg_table[1]  = {8'h98, 8'h03};  // ADI required
        cfg_table[2]  = {8'h9A, 8'hE0};  // ADI required
        cfg_table[3]  = {8'h9C, 8'h30};  // ADI required
        cfg_table[4]  = {8'h9D, 8'h61};  // ADI required (≤42.5 MHz pclk)
        cfg_table[5]  = {8'hA2, 8'hA4};  // ADI required
        cfg_table[6]  = {8'hA3, 8'hA4};  // ADI required
        cfg_table[7]  = {8'hE0, 8'hD0};  // ADI required
        cfg_table[8]  = {8'hF9, 8'h00};  // ADI required
        cfg_table[9]  = {8'h15, 8'h00};  // RGB 444 input, 8-bit
        cfg_table[10] = {8'h16, 8'h38};  // 8 bpc, style 1
        cfg_table[11] = {8'hAF, 8'h06};  // HDMI mode
        cfg_table[12] = {8'hD6, 8'hC0};  // HPD override
        cfg_table[13] = {8'h17, 8'h02};  // 16:9 aspect (or 0x00 for 4:3)
    end

    // ── I2C master wires ─────────────────────────────────────────────────────
    logic       i2c_start;
    logic [7:0] i2c_data;
    logic       i2c_done;
    logic       i2c_ack;
    logic       i2c_busy;

    i2c_master #(.CLK_FREQ(CLK_FREQ)) u_i2c (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_i     (i2c_start),
        .slave_addr_i(ADV_ADDR),
        .rw_i        (1'b0),
        .data_i      (i2c_data),
        .done_o      (i2c_done),
        .ack_o       (i2c_ack),
        .busy_o      (i2c_busy),
        .scl_o       (i2c_scl_o),
        .sda_io      (i2c_sda_io)
    );

    // ── Configuration FSM ─────────────────────────────────────────────────────
    typedef enum logic [2:0] {
        CFG_IDLE   = 3'd0,
        CFG_ADDR   = 3'd1,   // send register address byte
        CFG_WAIT_A = 3'd2,   // wait for i2c done (reg addr)
        CFG_VAL    = 3'd3,   // send register value byte
        CFG_WAIT_V = 3'd4,   // wait for i2c done (reg val)
        CFG_NEXT   = 3'd5,   // advance to next register
        CFG_DONE   = 3'd6
    } cfg_state_t;

    cfg_state_t cfg_state_r;
    logic [$clog2(N_REGS)-1:0] idx_r;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cfg_state_r <= CFG_ADDR;
            idx_r       <= '0;
            i2c_start   <= 1'b0;
            i2c_data    <= '0;
            cfg_done_o  <= 1'b0;
        end else begin
            i2c_start  <= 1'b0;
            cfg_done_o <= 1'b0;

            case (cfg_state_r)
                CFG_ADDR: begin
                    if (!i2c_busy) begin
                        i2c_data  <= cfg_table[idx_r][15:8];  // reg address
                        i2c_start <= 1'b1;
                        cfg_state_r <= CFG_WAIT_A;
                    end
                end

                CFG_WAIT_A: begin
                    if (i2c_done)
                        cfg_state_r <= CFG_VAL;
                end

                CFG_VAL: begin
                    if (!i2c_busy) begin
                        i2c_data  <= cfg_table[idx_r][7:0];   // reg value
                        i2c_start <= 1'b1;
                        cfg_state_r <= CFG_WAIT_V;
                    end
                end

                CFG_WAIT_V: begin
                    if (i2c_done)
                        cfg_state_r <= CFG_NEXT;
                end

                CFG_NEXT: begin
                    if (idx_r == N_REGS - 1)
                        cfg_state_r <= CFG_DONE;
                    else begin
                        idx_r       <= idx_r + 1'b1;
                        cfg_state_r <= CFG_ADDR;
                    end
                end

                CFG_DONE: begin
                    cfg_done_o  <= 1'b1;
                    cfg_state_r <= CFG_DONE;  // stay done
                end

                default: cfg_state_r <= CFG_ADDR;
            endcase
        end
    end

endmodule
