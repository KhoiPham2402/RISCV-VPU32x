module lsu_arbiter (
    // --- INPUT TỪ CORE CHÍNH (Pipeline Stage MEM) ---
    input  logic [31:0] core_addr,      // alu_result_m
    input  logic [31:0] core_wdata,     // rs2_data_m
    input  logic        core_wren,      // mem_wren_mem
    input  logic [2:0]  core_lsu_op,    // func3_m
    input  logic        core_is_load,   // Tín hiệu báo Core đang muốn Load (dựa vào wb_sel_mem == 00)
    
    // --- INPUT TỪ VICUNA (Memory Interface) ---
    input  logic        vic_req,        // xif_mem_req_valid
    input  logic [31:0] vic_addr,       // xif_mem_req_addr
    input  logic [31:0] vic_wdata,      // xif_mem_req_wdata
    input  logic        vic_we,         // xif_mem_req_we (1=Write, 0=Read)
    input  logic [3:0]  vic_be,         // Byte Enable (Vicuna dùng cái này thay vì func3)

    // --- OUTPUT SANG MODULE LSU (lsu.txt) ---
    output logic [31:0] lsu_addr_final,
    output logic [31:0] lsu_wdata_final,
    output logic        lsu_wren_final,
    output logic [2:0]  lsu_op_final,

    // --- OUTPUT CONTROL ---
    output logic        stall_core_req  // Báo Hazard Unit dừng Core nếu Vicuna chiếm dụng
);

    // 1. Chuyển đổi Vicuna Byte Enable sang LSU Opcode (func3)
    // Module lsu.txt của bạn dùng 3 bit func3 để phân biệt SB, SH, SW.
    // Vicuna lại gửi Byte Mask (ví dụ 0011 cho Halfword). Ta cần mapping.
    logic [2:0] vic_lsu_op_converted;

    always_comb begin
        if (vic_we) begin // Store
            case (vic_be)
                4'b0001, 4'b0010, 4'b0100, 4'b1000: vic_lsu_op_converted = 3'b000; // SB
                4'b0011, 4'b1100:                   vic_lsu_op_converted = 3'b001; // SH
                4'b1111:                            vic_lsu_op_converted = 3'b010; // SW
                default:                            vic_lsu_op_converted = 3'b010; // Mặc định SW
            endcase
        end else begin // Load
            // Vicuna Zve32x thường load word đầy đủ, sau đó tự cắt bên trong.
            // Để đơn giản, ta luôn Load Word (LW) cho Vicuna.
            vic_lsu_op_converted = 3'b010; // LW
        end
    end

    // 2. Logic Trọng tài (Priority Logic)
    // Ưu tiên Vicuna: Nếu Vicuna có Request (vic_req=1) -> Vicuna thắng.
    
    assign lsu_addr_final  = vic_req ? vic_addr  : core_addr;
    assign lsu_wdata_final = vic_req ? vic_wdata : core_wdata;
    assign lsu_wren_final  = vic_req ? vic_we    : core_wren;
    assign lsu_op_final    = vic_req ? vic_lsu_op_converted : core_lsu_op;

    // 3. Logic tạo Stall
    // Nếu Vicuna đang dùng LSU (vic_req) MÀ Core cũng muốn dùng (Write hoặc Load) -> Stall Core
    assign stall_core_req = vic_req && (core_wren || core_is_load);

endmodule