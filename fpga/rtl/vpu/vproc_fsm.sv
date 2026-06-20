// FSM điều khiển VPU – xử lý: CONFIG, EXEC, WIDEN, MASKING.
//
// ──────────────────────── Sơ đồ trạng thái ────────────────────────
//
//   IDLE ──(instr_valid)──┬── is_config ──────→ CONFIG ─(1 cyc)─→ IDLE
//                         │
//                         ├── is_masking ─────→ MASKING ─(counter_done)→ FINAL_MASKING → IDLE
//                         │
//                         ├── is_widen ───────→ WIDEN ──(counter_done)──→ IDLE
//                         │
//                         └── else ───────────→ EXEC  ──(counter_done)──→ IDLE
//
// ──────────────────────── Ghi chú ─────────────────────────────────
//
//   counter_done: tín hiệu từ bộ đếm / so sánh bên ngoài báo hoàn tất.
//   widen_sel  : toggle nội bộ mỗi cycle trong ST_WIDEN (0=lo, 1=hi).

module vproc_fsm (
    input         clk,
    input         rst_n,

    // Từ FIFO
    input         instr_valid,      // có lệnh sẵn sàng (= FIFO data_valid)
    input         is_config,        // lệnh config (vsetvli / vsetvl)
    input         is_masking,       // lệnh tạo mask (vd: vmadc/vmsbc, vmseq...)
    input         is_widen,         // lệnh widening
    input         is_reduction,     // lệnh reduction (vred*)

    // Từ bộ đếm bên ngoài
    input         counter_done,     // báo hoàn tất execution (EXEC / WIDEN / MASKING)
    input         reduction_done,   // báo reduction đã có kết quả cuối
    input         reduction_busy,   // reduction đang xử lý phần tử nội bộ

    // Output điều khiển
    output logic     latch_ctrl_en, // chốt ctrl_bus + rs1 từ FIFO vào thanh ghi
    output logic     csr_cfg_en,    // cho phép CSR ghi cấu hình
    output logic     counter_start, // pulse start cho cycle counter (lệnh non-config)
    output logic     vrf_wren,      // VRF write enable (toàn cục)
    output logic     widen_sel,     // 0=lo, 1=hi (chọn byte thấp/cao khi widening)
    output logic     s_offset_en,   // enable tăng source offset
    output logic     d_offset_en,   // enable tăng destination offset
    output logic     offset_reset,  // reset offset counters khi về IDLE
    output logic     pop_ready,     // đã nhận lệnh, FIFO advance read pointer
    output logic     reduction_start,// pulse start reduction
    output logic     reduction_en,   // chạy reduction nhiều chu kỳ

    // Trạng thái
    output           busy,
    output [3:0]     state_out
);

    typedef enum logic [3:0] {
        ST_IDLE    = 4'd0,
        ST_CONFIG  = 4'd1,
        ST_EXEC    = 4'd2,
        ST_WIDENL  = 4'd3,
        ST_WIDENH  = 4'd4,
        ST_MASKING = 4'd5,
        ST_FINAL_MASKING = 4'd6,
        ST_REDUCTION = 4'd7,
        ST_REDUCTION_DONE = 4'd8
    } fsm_state_t;

    fsm_state_t state_r, state_next;
    assign state_out = state_r;
    assign busy = (state_r != ST_IDLE);

    // Sequential: state + widen_sel registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r <= ST_IDLE;
        end else begin
            state_r <= state_next;
        end
    end

    // Combinational: next-state logic
    always_comb begin
        state_next = state_r;

        unique case (state_r)
            ST_IDLE: begin
                if (instr_valid) begin
                    if (is_config)
                        state_next = ST_CONFIG;
                    else if (is_masking)
                        state_next = ST_MASKING;
                    else if (is_widen)
                        state_next = ST_WIDENL;
                    else if (is_reduction)
                        state_next = ST_REDUCTION;
                    else
                        state_next = ST_EXEC;
                end
            end

            ST_CONFIG: begin
                state_next = ST_IDLE;
            end

            ST_EXEC: begin
                if (counter_done)
                    state_next = ST_IDLE;
            end

            ST_WIDENL: begin
                state_next = ST_WIDENH;
            end

            ST_WIDENH: begin
                if (counter_done)
                    state_next = ST_IDLE;
                else
                    state_next = ST_WIDENL;
            end

            ST_MASKING: begin
                if (counter_done)
                    state_next = ST_FINAL_MASKING;
            end

            ST_FINAL_MASKING: begin
                state_next = ST_IDLE;
            end

            ST_REDUCTION: begin
                if (reduction_done)
                    state_next = ST_REDUCTION_DONE;
            end

            ST_REDUCTION_DONE: begin
                state_next = ST_IDLE;
            end

            default: state_next = ST_IDLE;
        endcase
    end

    // Combinational: outputs
    always_comb begin
        latch_ctrl_en = 1'b0;
        csr_cfg_en    = 1'b0;
        counter_start = 1'b0;
        vrf_wren      = 1'b0;
        pop_ready     = 1'b0;
        widen_sel     = 1'b0;
        s_offset_en   = 1'b0;
        d_offset_en   = 1'b0;
        offset_reset  = 1'b0;
        reduction_start = 1'b0;
        reduction_en    = 1'b0;

        unique case (state_r)
            ST_IDLE: begin
                offset_reset = 1'b1;
                if (instr_valid) begin
                    latch_ctrl_en = 1'b1;
                    pop_ready     = 1'b1;
                    if (!is_config)
                        counter_start = 1'b1;
                    if (is_reduction)
                        reduction_start = 1'b1;
                end
            end

            ST_CONFIG: begin
                csr_cfg_en = 1'b1;
            end

            ST_EXEC: begin
                vrf_wren = 1'b1;
                s_offset_en = 1'b1;
                d_offset_en = 1'b1;
            end

            ST_WIDENL: begin
                vrf_wren = 1'b1;
                d_offset_en = 1'b1;
            end

            ST_WIDENH: begin
                vrf_wren    = 1'b1;
                widen_sel   = 1'b1;
                s_offset_en = 1'b1;
                d_offset_en = 1'b1;
            end

            ST_MASKING: begin
                // Chỉ tăng source; giữ nguyên vd đến cuối lệnh mask.
                s_offset_en = 1'b1;
                d_offset_en = 1'b0;
            end

            ST_FINAL_MASKING: begin
                // Ghi kết quả mask đã gom về vd trong 1 chu kỳ cuối.
                vrf_wren = 1'b1;
            end

            ST_REDUCTION: begin
                s_offset_en  = !reduction_busy;  // advance address only between chunks
                d_offset_en  = 1'b0;
                reduction_en = !reduction_busy;  // valid pulse only when module is free
            end

            ST_REDUCTION_DONE: begin
                // reduction ghi duy nhất phần tử 0 (wrapper sẽ gate lane_we)
                vrf_wren = 1'b1;
            end

            default: begin
            end
        endcase
    end

endmodule
