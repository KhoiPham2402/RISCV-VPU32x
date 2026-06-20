// =============================================================================
// uart.sv  —  UART RX/TX with TileLink-UL slave register interface
//
// Register map (byte address offset from slave base 0xFF00_0000):
//   0x00  RW  CTRL  [0]=TX_EN, [1]=RX_EN
//   0x04  RO  STAT  [0]=TX_BUSY, [1]=RX_VALID (RX FIFO non-empty)
//   0x08  WO  TXDAT [7:0] = byte to transmit (triggers transmission)
//   0x0C  RO  RXDAT [7:0] = next byte from RX FIFO (dequeued on read)
//   0x10  RW  BAUD  baud rate divisor = clk_freq / (16 * baud_rate) - 1
//
// FIFO depth: 8 bytes each (RX and TX).
// Reset: synchronous, active-low.
// =============================================================================
import tl_pkg::*;

module uart #(
    parameter int CLK_FREQ  = 50_000_000,
    parameter int BAUD_RATE = 115_200
) (
    input  logic       clk,
    input  logic       rst_n,

    // ── Serial I/O ───────────────────────────────────────────────────────────
    input  logic       uart_rx,
    output logic       uart_tx,

    // ── TL-UL slave port ─────────────────────────────────────────────────────
    input  tl_a_t      tl_a,
    output tl_d_t      tl_d
);
    // ── Default baud divisor ─────────────────────────────────────────────────
    // Counter decrements every clock cycle; bit period = baud_div+1 clocks.
    // Half-bit start-center delay = baud_div/2 cycles ≈ 0.5 bit period.
    localparam int DEFAULT_DIV = CLK_FREQ / BAUD_RATE - 1;

    // ─────────────────────────────────────────────────────────────────────────
    // Registers
    // ─────────────────────────────────────────────────────────────────────────
    logic        ctrl_tx_en;
    logic        ctrl_rx_en;
    logic [15:0] baud_div;    // configurable baud divisor

    // ─────────────────────────────────────────────────────────────────────────
    // FIFO (8-entry × 8-bit, power-of-2 pointers)
    // ─────────────────────────────────────────────────────────────────────────
    // ramstyle = "logic" → force register inference, not M10K (too small for block RAM)
    (* ramstyle = "logic" *) logic [7:0] tx_fifo [0:7];
    logic [2:0] tx_wptr, tx_rptr;
    logic       tx_full, tx_empty;
    assign tx_full  = (tx_wptr[2] != tx_rptr[2]) && (tx_wptr[1:0] == tx_rptr[1:0]);
    assign tx_empty = (tx_wptr == tx_rptr);

    (* ramstyle = "logic" *) logic [7:0] rx_fifo [0:7];
    logic [2:0] rx_wptr, rx_rptr;
    logic       rx_full, rx_empty;
    assign rx_full  = (rx_wptr[2] != rx_rptr[2]) && (rx_wptr[1:0] == rx_rptr[1:0]);
    assign rx_empty = (rx_wptr == rx_rptr);

    // ─────────────────────────────────────────────────────────────────────────
    // TL-UL decode signals — declared early so RX engine can use rx_dequeue
    // ─────────────────────────────────────────────────────────────────────────
    logic [7:0] reg_off;
    assign reg_off = tl_a.address[7:0];

    logic tl_read;
    logic tl_write;
    assign tl_read  = tl_a.valid && (tl_a.opcode == TL_A_GET);
    assign tl_write = tl_a.valid && (tl_a.opcode == TL_A_PUT_FULL || tl_a.opcode == TL_A_PUT_PARTIAL);

    // RX FIFO dequeue pulse — single driver for rx_rptr (used in RX engine below)
    logic rx_dequeue;
    assign rx_dequeue = tl_read && (reg_off == 8'h0C) && !rx_empty;

    // ─────────────────────────────────────────────────────────────────────────
    // TX Engine (8N1)
    // ─────────────────────────────────────────────────────────────────────────
    logic [15:0] tx_baud_cnt;
    logic [3:0]  tx_bit_cnt;   // 0=idle, 1=start, 2..9=data, 10=stop
    logic [9:0]  tx_shift;     // {stop, data[7:0], start}
    logic        tx_busy;
    assign tx_busy = (tx_bit_cnt != 4'd0);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            tx_baud_cnt <= '0;
            tx_bit_cnt  <= '0;
            tx_shift    <= 10'h3FF;  // idle = all ones
            uart_tx     <= 1'b1;
            tx_rptr     <= '0;
        end else begin
            if (!tx_busy && !tx_empty && ctrl_tx_en) begin
                // Load next byte: {stop=1, data[7:0], start=0}
                // tx_shift[0]=0 is the start bit; it gets output after the first
                // baud period. This produces one idle bit before the start, which
                // is valid 8N1 and avoids the double-start-bit bug.
                tx_shift    <= {1'b1, tx_fifo[tx_rptr[2:0]], 1'b0};
                tx_rptr     <= tx_rptr + 3'd1;
                tx_bit_cnt  <= 4'd10;
                tx_baud_cnt <= baud_div;
            end else if (tx_busy) begin
                if (tx_baud_cnt == 16'd0) begin
                    uart_tx     <= tx_shift[0];
                    tx_shift    <= {1'b1, tx_shift[9:1]};  // LSB first
                    tx_bit_cnt  <= tx_bit_cnt - 4'd1;
                    tx_baud_cnt <= baud_div;
                end else begin
                    tx_baud_cnt <= tx_baud_cnt - 16'd1;
                end
            end else begin
                uart_tx <= 1'b1;  // idle line
            end
        end
    end

    // ─────────────────────────────────────────────────────────────────────────
    // RX Engine (8N1) — 16× oversampling
    // ─────────────────────────────────────────────────────────────────────────
    logic        rx_sync0, rx_sync1;  // 2-FF synchronizer
    logic [15:0] rx_baud_cnt;
    logic [3:0]  rx_bit_cnt;
    logic [7:0]  rx_shift;
    logic        rx_active;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rx_sync0 <= 1'b1; rx_sync1 <= 1'b1;
            rx_baud_cnt <= '0;
            rx_bit_cnt  <= '0;
            rx_shift    <= '0;
            rx_active   <= 1'b0;
            rx_wptr     <= '0;
            rx_rptr     <= '0;
        end else begin
            rx_sync0 <= uart_rx;
            rx_sync1 <= rx_sync0;

            if (!rx_active && ctrl_rx_en) begin
                // Detect start bit (falling edge)
                if (!rx_sync1) begin
                    rx_active   <= 1'b1;
                    rx_baud_cnt <= baud_div + {1'b0, baud_div[15:1]}; // 1.5-bit: center of data bit 0
                    rx_bit_cnt  <= 4'd8;  // 8 data bits
                end
            end else if (rx_active) begin
                if (rx_baud_cnt == 16'd0) begin
                    rx_baud_cnt <= baud_div;
                    if (rx_bit_cnt > 4'd0) begin
                        rx_shift   <= {rx_sync1, rx_shift[7:1]};  // LSB first
                        rx_bit_cnt <= rx_bit_cnt - 4'd1;
                    end else begin
                        // Stop bit — sample and push to FIFO if valid
                        if (rx_sync1 && !rx_full) begin
                            rx_fifo[rx_wptr[2:0]] <= rx_shift;
                            rx_wptr <= rx_wptr + 3'd1;
                        end
                        rx_active <= 1'b0;
                    end
                end else begin
                    rx_baud_cnt <= rx_baud_cnt - 16'd1;
                end
            end

            // RX FIFO dequeue on RXDAT read
            if (rx_dequeue)
                rx_rptr <= rx_rptr + 3'd1;
        end
    end

    // ─────────────────────────────────────────────────────────────────────────
    // TL-UL slave register interface
    // ─────────────────────────────────────────────────────────────────────────

    // Read data mux (combinatorial)
    logic [31:0] rd_data;
    always_comb begin
        rd_data = 32'd0;
        case (reg_off)
            8'h00: rd_data = {30'd0, ctrl_rx_en, ctrl_tx_en};
            8'h04: rd_data = {30'd0, !rx_empty, tx_busy};
            8'h0C: rd_data = rx_empty ? 32'hFFFF_FFFF : {24'd0, rx_fifo[rx_rptr[2:0]]};
            8'h10: rd_data = {16'd0, baud_div};
            default: rd_data = 32'd0;
        endcase
    end

    // D channel: always 1-cycle combinatorial response
    always_comb begin
        tl_d = TL_D_IDLE;
        if (tl_a.valid) begin
            tl_d.valid  = 1'b1;
            tl_d.size   = tl_a.size;
            tl_d.error  = 1'b0;
            if (tl_read) begin
                tl_d.opcode = TL_D_ACCESS_ACK_DATA;
                tl_d.data   = rd_data;
            end else begin
                tl_d.opcode = TL_D_ACCESS_ACK;
                tl_d.data   = 32'd0;
            end
        end
    end

    // Register writes (sequential)
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ctrl_tx_en <= 1'b1;
            ctrl_rx_en <= 1'b1;
            baud_div   <= DEFAULT_DIV[15:0];
            tx_wptr    <= '0;
        end else begin
            if (tl_write) begin
                case (reg_off)
                    8'h00: {ctrl_rx_en, ctrl_tx_en} <= tl_a.data[1:0];
                    8'h08: begin  // TX data: push to TX FIFO
                        if (!tx_full) begin
                            tx_fifo[tx_wptr[2:0]] <= tl_a.data[7:0];
                            tx_wptr <= tx_wptr + 3'd1;
                        end
                    end
                    8'h10: baud_div <= tl_a.data[15:0];
                    default: ;
                endcase
            end
        end
    end

endmodule
