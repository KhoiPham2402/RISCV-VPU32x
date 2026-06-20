// =============================================================================
// vproc_vec_lsu.sv  —  Vector Load/Store Unit (VLSU)
// RISC-V V Extension: Unit-Stride VLE8/16/32 and VSE8/16/32
//
// Architecture Overview:
//   - One 32-bit (word) memory access per clock cycle.
//   - LOAD  (VLE): Reads sequential words from DMEM, packs them lane-by-lane
//                  into a 128-bit line buffer, then writes all 4 VRF lanes
//                  simultaneously when a full 4-word group is complete.
//   - STORE (VSE): Reads the source vector register combinationally from VRF
//                  (via the vs2 read port, multiplexed in the wrapper), then
//                  issues one word write to DMEM per cycle.
//   - SEW Mapping (eew from instruction width field):
//       e8  (sew=00) → 4 elements per 32-bit word,  num_words = ceil(vl / 4)
//       e16 (sew=01) → 2 elements per 32-bit word,  num_words = ceil(vl / 2)
//       e32 (sew=10) → 1 element  per 32-bit word,  num_words = vl
//   - vl already accounts for LMUL (total element count across all LMUL regs).
//   - Tail elements in a partial last register are written as 0 (tail-agnostic).
//
// Integration Contract:
//   - VLSU is decoupled from the FSM/FIFO pipeline. It is triggered by a 1-cycle
//     pulse (vls_valid) from the system wrapper upon detecting a VLE/VSE opcode.
//   - The wrapper asserts vpu_ready = ~fifo_full & ~vlsu_busy, stalling the
//     scalar pipeline whenever VLSU is active.
//   - While VLSU runs, the FSM is idle; VRF read/write ports are free to use.
//
// Synthesisability: All constructs are RTL-level. No initial blocks, no $-tasks.
// =============================================================================

module vproc_vec_lsu #(
    parameter int unsigned VLEN      = 128,  // vector register length (bits)
    parameter int unsigned REG_AWIDTH = 5    // log2(num_vector_registers) = 5
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // -------------------------------------------------------------------------
    // Issue Interface — driven by vproc_system_wrapper on VLE/VSE decode
    // -------------------------------------------------------------------------
    input  logic                    vls_valid,      // 1-cycle start pulse
    input  logic                    vls_is_load,    // 1 = VLE (load), 0 = VSE (store)
    input  logic [1:0]              vls_sew,        // element width: 00=e8,01=e16,10=e32
    input  logic [31:0]             vls_vl,         // total element count from CSR vl
    input  logic [REG_AWIDTH-1:0]   vls_vd_addr,    // vd (load destination) / vs3 (store source)
    input  logic [31:0]             rs1_data,       // base byte address from scalar rs1
    input  logic                    vm_i,           // 1 = unmasked, 0 = masked
    input  logic [VLEN-1:0]         v0_flat_i,      // v0 mask register (flat, VLEN bits)

    // -------------------------------------------------------------------------
    // VRF Read Port — for STORE source data (driven by wrapper vs2 mux)
    // The wrapper routes rs2_data of each VRF lane here while vlsu_busy_store=1.
    // The VLSU drives vlsu_vrf_raddr → wrapper uses it as vs2_addr for all 4 VRFs.
    // -------------------------------------------------------------------------
    input  logic [31:0]             vrf_lane0_rdata,  // VRF lane 0 rs2_data output
    input  logic [31:0]             vrf_lane1_rdata,  // VRF lane 1 rs2_data output
    input  logic [31:0]             vrf_lane2_rdata,  // VRF lane 2 rs2_data output
    input  logic [31:0]             vrf_lane3_rdata,  // VRF lane 3 rs2_data output
    output logic [REG_AWIDTH-1:0]   vlsu_vrf_raddr,   // vs2 address to feed all 4 VRFs

    // -------------------------------------------------------------------------
    // Shared DMEM Bus — connects to secondary port of scalar lsu.sv
    // mem_ready is always 1 for a synchronous 1-cycle SRAM.
    // -------------------------------------------------------------------------
    output logic                    mem_req,    // request valid this cycle
    output logic                    mem_we,     // 1 = write, 0 = read
    output logic [31:0]             mem_addr,   // byte address (word-aligned)
    output logic [3:0]              mem_be,     // byte enables (qualified for masked/partial stores)
    output logic [31:0]             mem_wdata,  // write data (store)
    input  logic [31:0]             mem_rdata,  // read data  (load, combinational)
    input  logic                    mem_ready,  // 1 when DMEM can accept/return data

    // -------------------------------------------------------------------------
    // VRF Write Port — for LOAD writeback (multiplexed in wrapper)
    // Fires for one cycle per complete 4-word (128-bit) group.
    // -------------------------------------------------------------------------
    output logic                    vrf_we,         // write enable
    output logic [REG_AWIDTH-1:0]   vrf_waddr,      // target register address
    output logic [31:0]             vrf_wdata_l0,   // lane 0: bits [31:0]
    output logic [31:0]             vrf_wdata_l1,   // lane 1: bits [63:32]
    output logic [31:0]             vrf_wdata_l2,   // lane 2: bits [95:64]
    output logic [31:0]             vrf_wdata_l3,   // lane 3: bits [127:96]

    // -------------------------------------------------------------------------
    // Status
    // -------------------------------------------------------------------------
    output logic                    vlsu_busy,  // high while VLSU is active
    output logic                    vlsu_busy_store, // subset: busy AND store phase
    output logic                    vls_done    // 1-cycle completion pulse
);

    // =========================================================================
    // State Machine
    // =========================================================================
    typedef enum logic [1:0] {
        ST_IDLE  = 2'd0,
        ST_LOAD  = 2'd1,
        ST_STORE = 2'd2,
        ST_DONE  = 2'd3
    } vlsu_state_t;

    vlsu_state_t state_r, state_next;

    // =========================================================================
    // Latched Control Registers (set on vls_valid pulse)
    // =========================================================================
    logic [31:0]            base_r;         // base byte address
    logic [1:0]             sew_r;          // element width encoding
    logic [REG_AWIDTH-1:0]  vd_addr_r;      // vd / vs3 base register address
    logic [31:0]            num_words_r;    // total 32-bit words to transfer
    logic [31:0]            word_ctr_r;     // current word index (0 .. num_words-1)

    // Load line buffer — accumulates 4 × 32-bit words before a VRF write
    logic [31:0]            load_buf_r [0:3];

    // Mask and partial-tail state latched at issue time
    logic            vm_r;            // latched vm bit (1=unmasked)
    logic [VLEN-1:0] v0_flat_r;       // latched v0 mask register
    logic [3:0]      last_word_be_r;  // byte enables for the last (partial) store word

    // =========================================================================
    // num_words Calculation (combinational, uses inputs at issue time)
    //   e8  → ceil(vl / 4)  = (vl + 3) >> 2
    //   e16 → ceil(vl / 2)  = (vl + 1) >> 1
    //   e32 → vl
    // =========================================================================
    logic [31:0] num_words_comb;

    always_comb begin
        case (vls_sew)
            2'd0:    num_words_comb = (vls_vl + 32'd3) >> 2;  // e8
            2'd1:    num_words_comb = (vls_vl + 32'd1) >> 1;  // e16
            default: num_words_comb = vls_vl;                  // e32
        endcase
        // Guard: at least 1 word even when vl == 0 (avoids deadlock)
        if (num_words_comb == 32'd0)
            num_words_comb = 32'd1;
    end

    // =========================================================================
    // last_word_be: byte enables for the last store word when vl is not a
    // multiple of elements-per-word. Tail bytes must not be written to DMEM.
    //   e8  (4 elems/word): enabled bytes = vl%4; 0 → full word
    //   e16 (2 elems/word): enabled bytes = vl%2 halfwords
    //   e32 (1 elem/word) : always full word
    // =========================================================================
    logic [3:0] last_word_be_comb;
    always_comb begin
        case (vls_sew)
            2'd0: begin // e8
                case (vls_vl[1:0])
                    2'd1:    last_word_be_comb = 4'b0001;
                    2'd2:    last_word_be_comb = 4'b0011;
                    2'd3:    last_word_be_comb = 4'b0111;
                    default: last_word_be_comb = 4'b1111; // 0 mod 4 → full word
                endcase
            end
            2'd1:    last_word_be_comb = vls_vl[0] ? 4'b0011 : 4'b1111; // e16
            default: last_word_be_comb = 4'b1111;                         // e32
        endcase
    end

    // =========================================================================
    // mask_be: per-word byte enables derived from v0_flat during masked stores.
    //   vm_r=1 (unmasked): all bytes enabled
    //   vm_r=0 (masked):
    //     e32: 1 element/word → mask_be = v0[word_ctr] ? 1111 : 0000
    //     e16: 2 elements/word → lower 2B from v0[2k], upper 2B from v0[2k+1]
    //     e8:  4 elements/word → each byte independently from v0[4k+j]
    // =========================================================================
    logic [3:0] mask_be;
    always_comb begin
        if (vm_r) begin
            mask_be = 4'b1111;
        end else begin
            case (sew_r)
                2'd0: begin // e8: 4 elements per word
                    mask_be[0] = v0_flat_r[{word_ctr_r[4:0], 2'b00}];
                    mask_be[1] = v0_flat_r[{word_ctr_r[4:0], 2'b01}];
                    mask_be[2] = v0_flat_r[{word_ctr_r[4:0], 2'b10}];
                    mask_be[3] = v0_flat_r[{word_ctr_r[4:0], 2'b11}];
                end
                2'd1: begin // e16: 2 elements per word
                    mask_be[1:0] = v0_flat_r[{word_ctr_r[5:0], 1'b0}] ? 2'b11 : 2'b00;
                    mask_be[3:2] = v0_flat_r[{word_ctr_r[5:0], 1'b1}] ? 2'b11 : 2'b00;
                end
                default: begin // e32: 1 element per word
                    mask_be = v0_flat_r[word_ctr_r[6:0]] ? 4'b1111 : 4'b0000;
                end
            endcase
        end
    end

    // =========================================================================
    // Derived Signals (combinational)
    // =========================================================================

    // Byte address of the current word (word-aligned: bottom 2 bits always 0)
    wire [31:0] curr_byte_addr  = base_r + {word_ctr_r[29:0], 2'b00};

    // Lane index within the current 4-word group (0..3)
    wire [1:0]  lane_idx        = word_ctr_r[1:0];

    // Register group offset: each 4 consecutive words map to one VRF register
    wire [REG_AWIDTH-1:0] reg_offset = word_ctr_r[REG_AWIDTH+1:2];  // word_ctr >> 2

    // VRF register address for the current group
    wire [REG_AWIDTH-1:0] vrf_curr_addr = vd_addr_r + reg_offset;

    // Completion flags
    wire last_word  = (word_ctr_r + 32'd1 >= num_words_r);
    wire line_done  = (lane_idx == 2'd3) || last_word;  // full group OR end of transfer

    // =========================================================================
    // LOAD: Combinational line-buffer mux
    //   ld_lane[i] sources:
    //     current lane  → mem_rdata  (not yet registered)
    //     already-read  → load_buf_r (registered from previous cycles)
    //     future/tail   → 32'd0      (tail-agnostic: tail elements = 0)
    // =========================================================================
    logic [31:0] ld_lane [0:3];

    always_comb begin
        integer i;
        for (i = 0; i < 4; i++) begin
            if (i == lane_idx)
                ld_lane[i] = mem_rdata;       // current word from DMEM
            else if (i < lane_idx)
                ld_lane[i] = load_buf_r[i];   // already received
            else
                ld_lane[i] = 32'd0;           // tail or not-yet-received
        end
    end

    // =========================================================================
    // STORE: Select correct lane from VRF read data
    // =========================================================================
    logic [31:0] store_word;

    always_comb begin
        case (lane_idx)
            2'd0:    store_word = vrf_lane0_rdata;
            2'd1:    store_word = vrf_lane1_rdata;
            2'd2:    store_word = vrf_lane2_rdata;
            default: store_word = vrf_lane3_rdata;
        endcase
    end

    // =========================================================================
    // State Register
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state_r <= ST_IDLE;
        else
            state_r <= state_next;
    end

    // =========================================================================
    // Next-State Logic
    // =========================================================================
    always_comb begin
        state_next = state_r;
        unique case (state_r)
            ST_IDLE: begin
                if (vls_valid)
                    state_next = vls_is_load ? ST_LOAD : ST_STORE;
            end
            ST_LOAD: begin
                if (mem_ready && last_word)
                    state_next = ST_DONE;
            end
            ST_STORE: begin
                if (mem_ready && last_word)
                    state_next = ST_DONE;
            end
            ST_DONE: begin
                state_next = ST_IDLE;
            end
            default: state_next = ST_IDLE;
        endcase
    end

    // =========================================================================
    // Sequential: Latch context + advance word counter + accumulate load buffer
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            base_r        <= '0;
            sew_r         <= '0;
            vd_addr_r     <= '0;
            num_words_r   <= '0;
            word_ctr_r    <= '0;
            load_buf_r[0]  <= '0;
            load_buf_r[1]  <= '0;
            load_buf_r[2]  <= '0;
            load_buf_r[3]  <= '0;
            vm_r           <= 1'b1;
            v0_flat_r      <= '0;
            last_word_be_r <= 4'b1111;
        end else begin

            // --- Issue: latch parameters ---
            if (state_r == ST_IDLE && vls_valid) begin
                base_r      <= rs1_data;
                sew_r       <= vls_sew;
                vd_addr_r   <= vls_vd_addr;
                num_words_r    <= num_words_comb;
                word_ctr_r     <= '0;
                vm_r           <= vm_i;
                v0_flat_r      <= v0_flat_i;
                last_word_be_r <= last_word_be_comb;
            end

            // --- Active: advance word counter ---
            if ((state_r == ST_LOAD || state_r == ST_STORE) && mem_ready)
                word_ctr_r <= word_ctr_r + 32'd1;

            // --- Load: accumulate into line buffer ---
            // When line_done, reset all lanes to 0 so the next group starts clean.
            // The current lane is simultaneously captured from mem_rdata.
            if (state_r == ST_LOAD && mem_ready) begin
                if (line_done) begin
                    load_buf_r[0] <= (lane_idx == 2'd0) ? mem_rdata : 32'd0;
                    load_buf_r[1] <= (lane_idx == 2'd1) ? mem_rdata : 32'd0;
                    load_buf_r[2] <= (lane_idx == 2'd2) ? mem_rdata : 32'd0;
                    load_buf_r[3] <= (lane_idx == 2'd3) ? mem_rdata : 32'd0;
                end else begin
                    load_buf_r[lane_idx] <= mem_rdata;
                end
            end

        end
    end

    // =========================================================================
    // Output Logic
    // =========================================================================

    // --- Memory bus ---
    assign mem_req   = (state_r == ST_LOAD) || (state_r == ST_STORE);
    assign mem_we    = (state_r == ST_STORE);
    assign mem_addr  = curr_byte_addr;
    assign mem_be    = (state_r == ST_STORE)
                       ? ((last_word ? last_word_be_r : 4'b1111) & mask_be)
                       : 4'b1111;
    assign mem_wdata = store_word;

    // --- VRF read address for store (wrapper muxes this into VRF vs2_addr) ---
    assign vlsu_vrf_raddr = vrf_curr_addr;

    // --- VRF write (load only): one cycle per complete 4-word line ---
    assign vrf_we      = (state_r == ST_LOAD) && mem_ready && line_done;
    assign vrf_waddr   = vrf_curr_addr;
    assign vrf_wdata_l0 = ld_lane[0];
    assign vrf_wdata_l1 = ld_lane[1];
    assign vrf_wdata_l2 = ld_lane[2];
    assign vrf_wdata_l3 = ld_lane[3];

    // --- Status ---
    assign vlsu_busy       = (state_r != ST_IDLE);
    assign vlsu_busy_store = (state_r == ST_STORE);
    assign vls_done        = (state_r == ST_DONE);

endmodule
