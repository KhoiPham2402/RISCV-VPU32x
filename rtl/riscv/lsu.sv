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
  // Read is combinational (1-cycle SRAM). Write is registered (posedge clk).
  // Byte address i_ext_addr[15:2] selects the 32-bit word (same window as scalar).
  input  logic        i_ext_req,    // request valid this cycle
  input  logic        i_ext_we,     // 1 = write, 0 = read
  input  logic [31:0] i_ext_addr,   // byte address
  input  logic [ 3:0] i_ext_be,     // byte enables
  input  logic [31:0] i_ext_wdata,  // write data
  output logic [31:0] o_ext_rdata   // read data (combinational)
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

  // Variables for write RMW
  logic [31:0] curr_word;
  logic [31:0] new_word;
  // mask kept for clarity; values assigned explicitly (no arithmetic shifts)
  logic [31:0] mask;

  // Write path and IO register updates
  // Use asynchronous active-low reset to clear IO & optionally memory
  int idx;
  always_ff @(posedge i_clk or negedge i_reset) begin
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
        // IO region writes
        if (i_lsu_addr[31:16] == IO_BASE0) begin
          unique case (i_lsu_addr[15:12])
            OFF_LEDR: begin
              curr_word = ledr;
              unique case (i_lsu_op)
                3'b000: begin // SB
                  unique case (i_lsu_addr[1:0])
                    2'b00: begin mask = 32'h000000FF; new_word = curr_word; new_word[7:0]   = i_st_data[7:0]; end
                    2'b01: begin mask = 32'h0000FF00; new_word = curr_word; new_word[15:8]  = i_st_data[7:0]; end
                    2'b10: begin mask = 32'h00FF0000; new_word = curr_word; new_word[23:16] = i_st_data[7:0]; end
                    2'b11: begin mask = 32'hFF000000; new_word = curr_word; new_word[31:24] = i_st_data[7:0]; end
                  endcase
                  ledr <= new_word;
                end
                3'b001: begin // SH
                  unique case (i_lsu_addr[1])
                    1'b0: begin mask = 32'h0000FFFF; new_word = curr_word; new_word[15:0]  = i_st_data[15:0]; end
                    1'b1: begin mask = 32'hFFFF0000; new_word = curr_word; new_word[31:16] = i_st_data[15:0]; end
                  endcase
                  ledr <= new_word;
                end
                3'b010: begin // SW
                  ledr <= i_st_data;
                end
                default: begin end
              endcase
            end
            OFF_LEDG: begin
              curr_word = ledg;
              unique case (i_lsu_op)
                3'b000: begin
                  unique case (i_lsu_addr[1:0])
                    2'b00: begin mask = 32'h000000FF; new_word = curr_word; new_word[7:0]   = i_st_data[7:0]; end
                    2'b01: begin mask = 32'h0000FF00; new_word = curr_word; new_word[15:8]  = i_st_data[7:0]; end
                    2'b10: begin mask = 32'h00FF0000; new_word = curr_word; new_word[23:16] = i_st_data[7:0]; end
                    2'b11: begin mask = 32'hFF000000; new_word = curr_word; new_word[31:24] = i_st_data[7:0]; end
                  endcase
                  ledg <= new_word;
                end
                3'b001: begin
                  unique case (i_lsu_addr[1])
                    1'b0: begin mask = 32'h0000FFFF; new_word = curr_word; new_word[15:0]  = i_st_data[15:0]; end
                    1'b1: begin mask = 32'hFFFF0000; new_word = curr_word; new_word[31:16] = i_st_data[15:0]; end
                  endcase
                  ledg <= new_word;
                end
                3'b010: begin
                  ledg <= i_st_data;
                end
                default: begin end
              endcase
            end
            OFF_HEXL: begin
              curr_word = hexl;
              unique case (i_lsu_op)
                3'b000: begin
                  unique case (i_lsu_addr[1:0])
                    2'b00: begin mask = 32'h000000FF; new_word = curr_word; new_word[7:0]   = i_st_data[7:0]; end
                    2'b01: begin mask = 32'h0000FF00; new_word = curr_word; new_word[15:8]  = i_st_data[7:0]; end
                    2'b10: begin mask = 32'h00FF0000; new_word = curr_word; new_word[23:16] = i_st_data[7:0]; end
                    2'b11: begin mask = 32'hFF000000; new_word = curr_word; new_word[31:24] = i_st_data[7:0]; end
                  endcase
                  hexl <= new_word;
                end
                3'b001: begin
                  unique case (i_lsu_addr[1])
                    1'b0: begin mask = 32'h0000FFFF; new_word = curr_word; new_word[15:0]  = i_st_data[15:0]; end
                    1'b1: begin mask = 32'hFFFF0000; new_word = curr_word; new_word[31:16] = i_st_data[15:0]; end
                  endcase
                  hexl <= new_word;
                end
                3'b010: begin
                  hexl <= i_st_data;
                end
                default: begin end
              endcase
            end
            OFF_HEXH: begin
              curr_word = hexh;
              unique case (i_lsu_op)
                3'b000: begin
                  unique case (i_lsu_addr[1:0])
                    2'b00: begin mask = 32'h000000FF; new_word = curr_word; new_word[7:0]   = i_st_data[7:0]; end
                    2'b01: begin mask = 32'h0000FF00; new_word = curr_word; new_word[15:8]  = i_st_data[7:0]; end
                    2'b10: begin mask = 32'h00FF0000; new_word = curr_word; new_word[23:16] = i_st_data[7:0]; end
                    2'b11: begin mask = 32'hFF000000; new_word = curr_word; new_word[31:24] = i_st_data[7:0]; end
                  endcase
                  hexh <= new_word;
                end
                3'b001: begin
                  unique case (i_lsu_addr[1])
                    1'b0: begin mask = 32'h0000FFFF; new_word = curr_word; new_word[15:0]  = i_st_data[15:0]; end
                    1'b1: begin mask = 32'hFFFF0000; new_word = curr_word; new_word[31:16] = i_st_data[15:0]; end
                  endcase
                  hexh <= new_word;
                end
                3'b010: begin
                  hexh <= i_st_data;
                end
                default: begin end
              endcase
            end
            OFF_LCD: begin
              // For LCD, treat writes as word for simplicity
              if (i_lsu_op == 3'b010) begin
                lcd <= i_st_data;
              end
            end
            default: begin end
          endcase
        end else if (i_lsu_addr[31:16] == IO_BASE1 && i_lsu_addr[15:0] == 16'h0000) begin
          // writes to switches region are ignored (read-only in hardware)
        end else begin
          // Data memory writes: implement byte/half/word write using RMW
          idx = i_lsu_addr[15:2];
          curr_word = dmem[idx];
          unique case (i_lsu_op)
            3'b000: begin // SB
              unique case (i_lsu_addr[1:0])
                2'b00: begin mask = 32'h000000FF; new_word = curr_word; new_word[7:0]   = i_st_data[7:0]; end
                2'b01: begin mask = 32'h0000FF00; new_word = curr_word; new_word[15:8]  = i_st_data[7:0]; end
                2'b10: begin mask = 32'h00FF0000; new_word = curr_word; new_word[23:16] = i_st_data[7:0]; end
                2'b11: begin mask = 32'hFF000000; new_word = curr_word; new_word[31:24] = i_st_data[7:0]; end
              endcase
              dmem[idx] <= new_word;
            end
            3'b001: begin // SH
              unique case (i_lsu_addr[1])
                1'b0: begin mask = 32'h0000FFFF; new_word = curr_word; new_word[15:0]  = i_st_data[15:0]; end
                1'b1: begin mask = 32'hFFFF0000; new_word = curr_word; new_word[31:16] = i_st_data[15:0]; end
              endcase
              dmem[idx] <= new_word;
            end
            3'b010: begin // SW
              dmem[idx] <= i_st_data;
            end
            default: begin end
          endcase
        end
      end
    end
  end

  // ── Secondary port: combinational read ──────────────────────────────────
  // Reads directly from dmem using the word-address bits [10:2], same window
  // as the scalar path. The scalar write always wins on a same-cycle conflict
  // because scalar writes register BEFORE ext writes in the always_ff block.
  assign o_ext_rdata = dmem[i_ext_addr[15:2]];

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
