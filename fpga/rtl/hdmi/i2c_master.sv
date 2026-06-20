// =============================================================================
// i2c_master.sv  —  Byte-level I2C master (standard 100 kHz from 50 MHz clk)
//
// Interface:
//   start      : pulse 1 cycle to begin transaction (addr + write_n must be valid)
//   slave_addr : 7-bit address
//   write_n    : 0=write, 1=read  (only write mode used for ADV7513 init)
//   data_in    : byte to write (captured at start)
//   done       : pulses 1 cycle when byte ACK'd and SCL returns high
//   ack        : 0=ACK received from slave, 1=NACK
//
// Usage: write slave_addr, then call with write bytes one at a time.
//   Caller must issue repeated START or STOP by de-asserting and re-asserting.
//
// Protocol: full START-byte-ACK-STOP per transaction.
// For register writes: caller issues start twice (addr, then data),
//   using the addr_phase flag to distinguish.
// =============================================================================
module i2c_master #(
    parameter int CLK_FREQ  = 50_000_000,
    parameter int SCL_FREQ  = 100_000
) (
    input  logic       clk,
    input  logic       rst_n,

    // Control
    input  logic       start_i,       // pulse: begin START+addr+byte
    input  logic [6:0] slave_addr_i,  // 7-bit I2C address
    input  logic       rw_i,          // 0=write, 1=read
    input  logic [7:0] data_i,        // byte to send (write mode)
    output logic       done_o,        // pulse: transaction byte complete
    output logic       ack_o,         // 0=ACK, 1=NACK from slave
    output logic       busy_o,

    // I2C pads
    output logic       scl_o,
    inout  wire        sda_io
);
    // Clock divider: quarter-period ticks
    localparam int DIV4 = CLK_FREQ / (SCL_FREQ * 4);

    typedef enum logic [3:0] {
        ST_IDLE    = 4'd0,
        ST_START   = 4'd1,
        ST_ADDR    = 4'd2,
        ST_ADDR_RW = 4'd3,
        ST_SEND    = 4'd4,
        ST_ACK     = 4'd5,
        ST_STOP    = 4'd6,
        ST_DONE    = 4'd7
    } state_t;

    state_t         state_r;
    logic [15:0]    div_r;          // quarter-period counter
    logic           tick;           // quarter-period tick
    logic [1:0]     phase_r;        // 0-3 within one SCL period
    logic [3:0]     bit_cnt_r;      // bit index 7..0, then ACK
    logic [7:0]     shift_r;        // TX shift register
    logic           scl_r;
    logic           sda_out_r;
    logic           sda_oe_r;       // 1=drive SDA, 0=tristate

    assign tick    = (div_r == DIV4 - 1);
    assign scl_o   = scl_r;
    assign sda_io  = sda_oe_r ? sda_out_r : 1'bz;
    assign busy_o  = (state_r != ST_IDLE);

    // ── Divider ───────────────────────────────────────────────────────────────
    always_ff @(posedge clk) begin
        if (!rst_n || state_r == ST_IDLE)
            div_r <= '0;
        else if (tick)
            div_r <= '0;
        else
            div_r <= div_r + 1'b1;
    end

    // ── Phase within SCL period ───────────────────────────────────────────────
    always_ff @(posedge clk) begin
        if (!rst_n || state_r == ST_IDLE)
            phase_r <= '0;
        else if (tick)
            phase_r <= phase_r + 1'b1;
    end

    // ── FSM ──────────────────────────────────────────────────────────────────
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_r   <= ST_IDLE;
            scl_r     <= 1'b1;
            sda_out_r <= 1'b1;
            sda_oe_r  <= 1'b1;
            done_o    <= 1'b0;
            ack_o     <= 1'b1;
            bit_cnt_r <= '0;
            shift_r   <= '0;
        end else begin
            done_o <= 1'b0;

            case (state_r)
                ST_IDLE: begin
                    scl_r     <= 1'b1;
                    sda_out_r <= 1'b1;
                    sda_oe_r  <= 1'b1;
                    if (start_i) begin
                        shift_r   <= {slave_addr_i, rw_i};
                        bit_cnt_r <= 4'd7;
                        state_r   <= ST_START;
                    end
                end

                // START condition: SDA falls while SCL high
                ST_START: if (tick) begin
                    case (phase_r)
                        2'd0: begin sda_out_r <= 1'b1; scl_r <= 1'b1; end
                        2'd1: begin sda_out_r <= 1'b0; end  // SDA falls
                        2'd2: begin scl_r     <= 1'b0; end  // SCL falls
                        2'd3: begin state_r   <= ST_ADDR; end
                    endcase
                end

                // Clock out 8 bits (addr[6:0] + rw)
                ST_ADDR: if (tick) begin
                    case (phase_r)
                        2'd0: begin sda_out_r <= shift_r[7]; sda_oe_r <= 1'b1; end
                        2'd1: begin scl_r <= 1'b1; end
                        2'd2: begin end
                        2'd3: begin
                            scl_r <= 1'b0;
                            if (bit_cnt_r == 0) begin
                                state_r <= ST_ACK;
                                sda_oe_r <= 1'b0;  // release for ACK
                            end else begin
                                shift_r   <= {shift_r[6:0], 1'b0};
                                bit_cnt_r <= bit_cnt_r - 1'b1;
                            end
                        end
                    endcase
                end

                // ACK bit from slave
                ST_ACK: if (tick) begin
                    case (phase_r)
                        2'd0: begin end
                        2'd1: begin scl_r <= 1'b1; end
                        2'd2: begin ack_o <= sda_io; end   // sample ACK
                        2'd3: begin
                            scl_r <= 1'b0;
                            if (!rw_i) begin
                                // Load data byte for write
                                shift_r   <= data_i;
                                bit_cnt_r <= 4'd7;
                                state_r   <= ST_SEND;
                                sda_oe_r  <= 1'b1;
                            end else begin
                                state_r <= ST_STOP;
                            end
                        end
                    endcase
                end

                // Clock out data byte
                ST_SEND: if (tick) begin
                    case (phase_r)
                        2'd0: begin sda_out_r <= shift_r[7]; sda_oe_r <= 1'b1; end
                        2'd1: begin scl_r <= 1'b1; end
                        2'd2: begin end
                        2'd3: begin
                            scl_r <= 1'b0;
                            if (bit_cnt_r == 0) begin
                                state_r  <= ST_STOP;
                                sda_oe_r <= 1'b0;
                            end else begin
                                shift_r   <= {shift_r[6:0], 1'b0};
                                bit_cnt_r <= bit_cnt_r - 1'b1;
                            end
                        end
                    endcase
                end

                // STOP: SCL rises, then SDA rises
                ST_STOP: if (tick) begin
                    case (phase_r)
                        2'd0: begin sda_out_r <= 1'b0; sda_oe_r <= 1'b1; end
                        2'd1: begin scl_r <= 1'b1; end
                        2'd2: begin sda_out_r <= 1'b1; end  // SDA rises while SCL high
                        2'd3: begin state_r <= ST_DONE; end
                    endcase
                end

                ST_DONE: begin
                    done_o  <= 1'b1;
                    state_r <= ST_IDLE;
                end

                default: state_r <= ST_IDLE;
            endcase
        end
    end

endmodule
