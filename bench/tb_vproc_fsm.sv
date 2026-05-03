`timescale 1ns/1ps

module tb_vproc_fsm;

    reg clk;
    reg rst_n;

    reg instr_valid;
    reg is_config;
    reg is_multi_cycle;
    reg counter_done_2;
    reg valid_cfg;

    wire latch_ctrl_en;
    wire csr_cfg_en;
    wire is_widen;
    wire [1:0] state;

    // DUT
    vproc_fsm dut (
        .clk(clk),
        .rst_n(rst_n),
        .instr_valid(instr_valid),
        .is_config(is_config),
        .is_multi_cycle(is_multi_cycle),
        .counter_done_2(counter_done_2),
        .valid_cfg(valid_cfg),
        .latch_ctrl_en(latch_ctrl_en),
        .csr_cfg_en(csr_cfg_en),
        .is_widen(is_widen),
        .state(state)
    );

    // Clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Monitor state
    task print_state;
        begin
            $display("T=%0t ns | state=%0d (0=IDLE,1=CONFIG,2=SINGLE,3=MULTI) | instr_valid=%b is_config=%b is_multi_cycle=%b cfg_done? csr_cfg_en=%b is_widen=%b",
                     $time, state, instr_valid, is_config, is_multi_cycle, csr_cfg_en, is_widen);
        end
    endtask

    initial begin
        rst_n         = 1'b0;
        instr_valid   = 1'b0;
        is_config     = 1'b0;
        is_multi_cycle= 1'b0;
        counter_done_2= 1'b0;
        valid_cfg     = 1'b0;

        $display("==== TB vproc_fsm: reset ====");
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        print_state();

        // Test 1: CONFIG lệnh, sau đó cfg_done -> quay về IDLE
        $display("==== Test 1: CONFIG phase ====");
        @(posedge clk);
        instr_valid = 1'b1;
        is_config   = 1'b1;
        print_state();

        @(posedge clk);
        instr_valid = 1'b0;
        is_config   = 1'b0;
        valid_cfg   = 1'b1;   // báo cấu hình hợp lệ
        print_state();

        @(posedge clk);
        valid_cfg   = 1'b0;
        print_state();

        // Test 2: SINGLE lệnh (không widening), sau khi cfg_done đã set
        $display("==== Test 2: SINGLE op ====");
        @(posedge clk);
        instr_valid   = 1'b1;
        is_multi_cycle= 1'b0;
        is_config     = 1'b0;
        print_state();

        @(posedge clk);
        instr_valid   = 1'b0;
        print_state();

        // Test 3: MULTICYCLE lệnh (widening), chờ counter_done_2
        $display("==== Test 3: MULTICYCLE op ====");
        @(posedge clk);
        instr_valid   = 1'b1;
        is_multi_cycle= 1'b1;
        print_state();

        @(posedge clk);
        instr_valid   = 1'b0;
        print_state();

        // giữ ở MULTICYCLE vài chu kỳ
        repeat (2) @(posedge clk);
        print_state();

        // báo đủ 2 chu kỳ -> quay lại IDLE
        @(posedge clk);
        counter_done_2 = 1'b1;
        print_state();

        @(posedge clk);
        counter_done_2 = 1'b0;
        print_state();

        $display("==== TB vproc_fsm done ====");
        $finish;
    end

endmodule

