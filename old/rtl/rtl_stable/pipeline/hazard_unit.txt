module hazard_unit (
    // Inputs từ ID Stage (Dùng để check Load-Use Hazard)
    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,

    // Inputs từ EX Stage (Dùng để check Forwarding & Load-Use)
    input  logic [4:0]  rs1_addr_exe,
    input  logic [4:0]  rs2_addr_exe,
    input  logic [4:0]  rd_addr_exe,
    input  logic        rd_wren_exe,
    input  logic        is_load_exe, // Tín hiệu báo lệnh hiện tại ở EX là Load

    // Inputs từ MEM Stage (Dùng cho Forwarding)
    input  logic [4:0]  rd_addr_mem,
    input  logic        rd_wren_mem,

    // Inputs từ WB Stage (Dùng cho Forwarding)
    input  logic [4:0]  rd_addr_wb,
    input  logic        rd_wren_wb,

    // Input Control (Branch/Jump taken)
    input  logic        pc_sel,      // 1 nếu Branch taken hoặc Jump

    input logic         is_vector_id; // Từ control unit
    input logic         vicuna_ready; // Từ Vicuna

    // Outputs
    output logic        stall,       // Dừng PC và IF/ID
    output logic        flush,       // Xóa lệnh sai (Flush ID/EX)
    output logic        hazard,
    output logic [1:0]  fwd_a,       // 00: Reg, 01: Mem, 10: WB
    output logic [1:0]  fwd_b        // 00: Reg, 01: Mem, 10: WB
);

    //==================================================================
    // 1. FORWARDING LOGIC
    //==================================================================
    // Nguyên tắc: Ưu tiên dữ liệu mới nhất (MEM > WB)
    // Forwarding xảy ra tại tầng EXE (so sánh rs_exe với rd_mem/rd_wb)

    always_comb begin
        // --- Forward A (RS1) ---
        // Priority 1: Forward từ MEM (Lệnh liền trước)
        if (rd_wren_mem && (rd_addr_mem != 5'd0) && (rd_addr_mem == rs1_addr_exe)) begin
            fwd_a = 2'b01;
        end
        // Priority 2: Forward từ WB (Lệnh trước nữa)
        // Chỉ forward nếu MEM KHÔNG forward (tránh double hazard)
        else if (rd_wren_wb && (rd_addr_wb != 5'd0) && (rd_addr_wb == rs1_addr_exe)) begin
            fwd_a = 2'b10;
        end
        // Default: Lấy từ Register File
        else begin
            fwd_a = 2'b00;
        end

        // --- Forward B (RS2) ---
        // Priority 1: Forward từ MEM
        if (rd_wren_mem && (rd_addr_mem != 5'd0) && (rd_addr_mem == rs2_addr_exe)) begin
            fwd_b = 2'b01;
        end
        // Priority 2: Forward từ WB
        else if (rd_wren_wb && (rd_addr_wb != 5'd0) && (rd_addr_wb == rs2_addr_exe)) begin
            fwd_b = 2'b10;
        end
        // Default
        else begin
            fwd_b = 2'b00;
        end
    end

    //==================================================================
    // 2. LOAD-USE HAZARD DETECTION
    //==================================================================
    // Xảy ra khi: Lệnh ở EX là Load, lệnh ở ID cần dùng kết quả đó.
    // Forwarding không giải quyết được vì data chưa có từ Memory.
    // Hành động: Stall 1 nhịp.

    logic stall_cond;
    logic stall_vector;
    always_comb begin
        stall_cond = 1'b0;
        if (is_load_exe && (rd_addr_exe != 5'd0)) begin
            if ((rd_addr_exe == rs1_addr) || (rd_addr_exe == rs2_addr)) begin
                stall_cond = 1'b1;
            end
        end
    end
    // Đối với lệnh vector, nếu Vicuna chưa sẵn sàng nhận lệnh mới, ta cũng stall
    always_comb begin
        stall_vector = 1'b0;
        if (is_vector_id && !vicuna_ready) begin
            stall_vector = 1'b1;
        end
    end
    // Thêm input
    input logic mem_stall_req, // Nối với stall_from_arbiter
    always_comb begin
        if (mem_stall_req) begin
        stall_cond = 1'b1;
        end
    end
    //==================================================================
    // 3. OUTPUT ASSIGNMENTS
    //==================================================================
    
    // Stall: Đóng băng PC và IF/ID pipeline reg
    assign stall = stall_cond | stall_vector | mem_stall_req;

    // Flush: 
    // - Nếu có Branch/Jump (pc_sel=1): Flush lệnh đang ở ID và EX (tùy thiết kế branch resolution ở đâu).
    // - Nếu Stall (stall_cond=1): Flush lệnh ở ID/EX (chèn bong bóng - NOP vào EX).
    // Ở đây ta giả sử flush cho ID/EX pipeline register:
    assign flush = pc_sel;
    assign hazard = pc_sel | stall;

endmodule