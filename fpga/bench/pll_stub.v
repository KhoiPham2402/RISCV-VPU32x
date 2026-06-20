// Behavioral PLL stub for simulation.
// pclk_int (outclk_1) is forced by testbench anyway.
module pll (
    input  refclk,
    input  rst,
    output outclk_0,
    output outclk_1,
    output locked
);
    assign outclk_0 = refclk;
    assign outclk_1 = 1'b0;   // overridden by force in testbench
    assign locked   = 1'b1;
endmodule
