// dmem_bank_b2.v — byte-lane 2 wrapper: sets init_file = "dmem_b2.mif"
module dmem_bank_b2 (
    input  wire        clock,
    input  wire [13:0] address_a, address_b,
    input  wire [ 7:0] data_a, data_b,
    input  wire        rden_a, rden_b, wren_a, wren_b,
    output wire [ 7:0] q_a, q_b
);
    dmem_bank u (
        .clock     (clock),
        .address_a (address_a), .data_a (data_a),
        .wren_a    (wren_a),    .rden_a (rden_a), .q_a (q_a),
        .address_b (address_b), .data_b (data_b),
        .wren_b    (wren_b),    .rden_b (rden_b), .q_b (q_b)
    );
    defparam u.altsyncram_component.init_file = "dmem_b2.mif";
endmodule
