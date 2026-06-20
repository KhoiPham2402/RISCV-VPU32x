// fpga/ip/dmem_bank_b3.sv — Simulation-only passthrough (no defparam/altsyncram).
module dmem_bank_b3 (
    input  logic        clock,
    input  logic [13:0] address_a, address_b,
    input  logic [ 7:0] data_a, data_b,
    input  logic        rden_a, rden_b, wren_a, wren_b,
    output logic [ 7:0] q_a, q_b
);
    dmem_bank u (.clock(clock),
        .address_a(address_a), .data_a(data_a), .wren_a(wren_a), .rden_a(rden_a), .q_a(q_a),
        .address_b(address_b), .data_b(data_b), .wren_b(wren_b), .rden_b(rden_b), .q_b(q_b));
endmodule
