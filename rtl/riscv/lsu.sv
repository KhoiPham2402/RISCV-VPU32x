module lsu(
  input  logic i_clk,
  input  logic i_reset,
  input  logic [31:0] i_lsu_addr,
  input  logic [31:0] i_st_data,
  input  logic        i_lsu_wren,
  input  logic [ 2:0] i_lsu_op,
  output logic [31:0] o_ld_data,
  output logic [31:0] o_io_ledr,
  output logic [31:0] o_io_ledg,
  output logic [ 6:0] o_io_hex0,
  output logic [ 6:0] o_io_hex1,
  output logic [ 6:0] o_io_hex2,
  output logic [ 6:0] o_io_hex3,
  output logic [ 6:0] o_io_hex4,
  output logic [ 6:0] o_io_hex5,
  output logic [ 6:0] o_io_hex6,
  output logic [ 6:0] o_io_hex7,
  output logic [31:0] o_io_lcd,
  input  logic [31:0] i_io_sw,

  // ── Secondary port: VLSU shared DMEM access ───────────────────────────────
  // Read is REGISTERED (synchronous 1-cycle latency): data appears the cycle
  // AFTER i_ext_req is asserted — matching vproc_vec_lsu's M10K SRAM assumption.
  // Write is registered (posedge clk).
  // Byte address i_ext_addr[15:2] selects the 32-bit word (same window as scalar).
  input  logic        i_ext_req,    // request valid this cycle
  input  logic        i_ext_we,     // 1 = write, 0 = read
  input  logic [31:0] i_ext_addr,   // byte address
  input  logic [ 3:0] i_ext_be,     // byte enables
  input  logic [31:0] i_ext_wdata,  // write data
  output logic [31:0] o_ext_rdata   // read data (registered, 1-cycle latency)
);
  // 64 KiB data memory (16384 x 32-bit words) — sized for 128×128 lena benchmark
	logic [31:0] dmem [0:16383];
  // IO registers
  logic [31:0] ledr;
  logic [31:0] ledg;
  logic [31:0] hexl;
  logic [31:0] hexh;
  logic [31:0] lcd;
  logic [31:0] sw;

  // internal read data
  logic [31:0] w_ld_data;

  // convenience locals
  localparam logic [15:0] IO_BASE0 = 16'h1000; // 0x1000_xxxx region (LEDs, HEX, LCD)
  localparam logic [15:0] IO_BASE1 = 16'h1001; // 0x1001_xxxx region (switches)

  localparam int OFF_LEDR  = 4'h0; // 0x1000_0000
  localparam int OFF_LEDG  = 4'h1; // 0x1000_1000
  localparam int OFF_HEXL  = 4'h2; // 0x1000_2000
  localparam int OFF_HEXH  = 4'h3; // 0x1000_3000
  localparam int OFF_LCD   = 4'h4; // 0x1000_4000

  // Initialize memory from mem.dump if present (word hex values)


  // Read: select IO registers or dmem word
  always_comb begin
    if (i_lsu_addr[31:16] == IO_BASE0) begin
      // IO region: decode by high nibble of the lower 16 bits
      case (i_lsu_addr[15:12])
        OFF_LEDR: w_ld_data = ledr;
        OFF_LEDG: w_ld_data = ledg;
        OFF_HEXL: w_ld_data = hexl;
        OFF_HEXH: w_ld_data = hexh;
        OFF_LCD:  w_ld_data = lcd;
        default:  w_ld_data = 32'b0;
      endcase
    end else if (i_lsu_addr[31:16] == IO_BASE1 && i_lsu_addr[15:0] == 16'h0000) begin
      // switches mapped at 0x1001_0000
      w_ld_data = sw;
    end else begin
      // data memory (word addressed by bits [15:2])
      w_ld_data = dmem[i_lsu_addr[15:2]];
    end
  end

  // Load semantics: sign/zero-extend or full word
  always_comb begin
    unique case (i_lsu_op)
      3'b000: begin // LB
        case (i_lsu_addr[1:0])
          2'b00: o_ld_data = {{24{w_ld_data[ 7]}}, w_ld_data[ 7: 0]};
          2'b01: o_ld_data = {{24{w_ld_data[15]}}, w_ld_data[15: 8]};
          2'b10: o_ld_data = {{24{w_ld_data[23]}}, w_ld_data[23:16]};
          2'b11: o_ld_data = {{24{w_ld_data[31]}}, w_ld_data[31:24]};
        endcase
      end
      3'b001: begin // LH
        case (i_lsu_addr[1])
          1'b0: o_ld_data = {{16{w_ld_data[15]}}, w_ld_data[15: 0]};
          1'b1: o_ld_data = {{16{w_ld_data[31]}}, w_ld_data[31:16]};
        endcase
      end
      3'b010: begin // LW
        o_ld_data = w_ld_data;
      end
      3'b100: begin // LBU
        case (i_lsu_addr[1:0])
          2'b00: o_ld_data = {24'b0, w_ld_data[ 7: 0]};
          2'b01: o_ld_data = {24'b0, w_ld_data[15: 8]};
          2'b10: o_ld_data = {24'b0, w_ld_data[23:16]};
          2'b11: o_ld_data = {24'b0, w_ld_data[31:24]};
        endcase
      end
      3'b101: begin // LHU
        case (i_lsu_addr[1])
          1'b0: o_ld_data = {16'b0, w_ld_data[15: 0]};
          1'b1: o_ld_data = {16'b0, w_ld_data[31:16]};
        endcase
      end
      default: begin
        o_ld_data = 32'b0;
      end
    endcase
  end

  // apply_store: compute updated word for SB / SH / SW without copy-paste
  function automatic logic [31:0] apply_store(
      input logic [31:0] curr,
      input logic [31:0] wdata,
      input logic [2:0]  op,
      input logic [1:0]  addr_lo
  );
      apply_store = curr;
      case (op)
          3'b000: case (addr_lo)  // SB
              2'b00: apply_store[ 7: 0] = wdata[7:0];
              2'b01: apply_store[15: 8] = wdata[7:0];
              2'b10: apply_store[23:16] = wdata[7:0];
              2'b11: apply_store[31:24] = wdata[7:0];
          endcase
          3'b001: if (addr_lo[1]) apply_store[31:16] = wdata[15:0];  // SH
                  else            apply_store[15: 0] = wdata[15:0];
          default: apply_store = wdata;  // SW
      endcase
  endfunction

  // Write path and IO register updates
  always_ff @(posedge i_clk) begin
    if (!i_reset) begin
      ledr <= 32'b0;
      ledg <= 32'b0;
      hexl <= 32'b0;
      hexh <= 32'b0;
      lcd  <= 32'b0;
      sw   <= 32'b0;
      dmem <= '{default:32'b0};
    end else begin
      sw <= i_io_sw;

      // ── Secondary port: VLSU write (byte-enable aware) ──────────────────
      if (i_ext_req && i_ext_we) begin
        if (i_ext_be[0]) dmem[i_ext_addr[15:2]][ 7: 0] <= i_ext_wdata[ 7: 0];
        if (i_ext_be[1]) dmem[i_ext_addr[15:2]][15: 8] <= i_ext_wdata[15: 8];
        if (i_ext_be[2]) dmem[i_ext_addr[15:2]][23:16] <= i_ext_wdata[23:16];
        if (i_ext_be[3]) dmem[i_ext_addr[15:2]][31:24] <= i_ext_wdata[31:24];
      end

      if (i_lsu_wren) begin
        if (i_lsu_addr[31:16] == IO_BASE0) begin
          case (i_lsu_addr[15:12])
            OFF_LEDR: ledr <= apply_store(ledr, i_st_data, i_lsu_op, i_lsu_addr[1:0]);
            OFF_LEDG: ledg <= apply_store(ledg, i_st_data, i_lsu_op, i_lsu_addr[1:0]);
            OFF_HEXL: hexl <= apply_store(hexl, i_st_data, i_lsu_op, i_lsu_addr[1:0]);
            OFF_HEXH: hexh <= apply_store(hexh, i_st_data, i_lsu_op, i_lsu_addr[1:0]);
            OFF_LCD:  if (i_lsu_op == 3'b010) lcd <= i_st_data;
            default:  ;
          endcase
        end else if (!(i_lsu_addr[31:16] == IO_BASE1)) begin
          // Data memory write (byte/half/word)
          dmem[i_lsu_addr[15:2]] <= apply_store(dmem[i_lsu_addr[15:2]],
                                                 i_st_data, i_lsu_op, i_lsu_addr[1:0]);
        end
      end
    end
  end

  // ── Secondary port: registered read ─────────────────────────────────────
  // Captures dmem[addr] on the posedge when a read request is active, giving
  // vproc_vec_lsu the synchronous 1-cycle SRAM behaviour it was designed for.
  // The prefetch that VLSU fires during ST_IDLE ensures word 0 is in the
  // register by the time ST_LOAD begins — no extra latency in practice.
  logic [31:0] ext_rdata_r;
  always_ff @(posedge i_clk) begin
    if (!i_reset)
      ext_rdata_r <= 32'b0;
    else if (i_ext_req && !i_ext_we)
      ext_rdata_r <= dmem[i_ext_addr[15:2]];
  end
  assign o_ext_rdata = ext_rdata_r;

  // outputs
  assign o_io_ledr = ledr;
  assign o_io_ledg = ledg;
  assign o_io_hex0 = hexl[ 6: 0];
  assign o_io_hex1 = hexl[14: 8];
  assign o_io_hex2 = hexl[22:16];
  assign o_io_hex3 = hexl[30:24];
  assign o_io_hex4 = hexh[ 6: 0];
  assign o_io_hex5 = hexh[14: 8];
  assign o_io_hex6 = hexh[22:16];
  assign o_io_hex7 = hexh[30:24];
  assign o_io_lcd  = lcd;

endmodule
