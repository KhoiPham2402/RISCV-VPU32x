`timescale 1ns/1ps

// Testbench FIFO: golden model, random test, in kết quả từng testcase lên terminal, dump waveform.

module tb_vproc_fifo;

    parameter WIDTH = 32;
    parameter DEPTH = 8;
    parameter ADDR_W = 3;

    reg                  clk;
    reg                  rst_n;
    reg                  push_valid;
    reg  [WIDTH-1:0]     data_in;
    wire                 full;
    wire [WIDTH-1:0]     data_out;
    wire                 data_valid;
    reg                  pop_ready;

    vproc_fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH), .ADDR_W(ADDR_W)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .push_valid(push_valid),
        .data_in(data_in),
        .full(full),
        .data_out(data_out),
        .data_valid(data_valid),
        .pop_ready(pop_ready)
    );

    // ----- Golden model: hàng đợi 32-bit, depth 8, cùng luật full/forwarding -----
    reg [WIDTH-1:0] gold_mem [0:DEPTH-1];
    reg [ADDR_W-1:0] gold_wr, gold_rd;
    reg [ADDR_W:0]   gold_count;

    wire gold_empty = (gold_count == {(ADDR_W+1){1'b0}});
    wire gold_full  = (gold_count == DEPTH);
    wire gold_forwarding = gold_empty && push_valid && pop_ready;
    wire gold_wr_en = push_valid && !gold_full && !gold_forwarding;
    wire gold_pop_consume = pop_ready && !gold_empty;

    wire gold_data_valid = !gold_empty || (push_valid && gold_empty);
    wire [WIDTH-1:0] gold_data_out = (gold_empty && push_valid) ? data_in : gold_mem[gold_rd];
    wire gold_full_out = gold_full && !gold_forwarding;

    integer i;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Golden model update (đồng bộ với DUT)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gold_wr   <= {ADDR_W{1'b0}};
            gold_rd   <= {ADDR_W{1'b0}};
            gold_count<= {(ADDR_W+1){1'b0}};
            for (i = 0; i < DEPTH; i = i + 1) gold_mem[i] <= {WIDTH{1'b0}};
        end else begin
            if (gold_wr_en) begin
                gold_mem[gold_wr] <= data_in;
                gold_wr            <= gold_wr + 1'b1;
            end
            if (gold_pop_consume) begin
                gold_rd <= gold_rd + 1'b1;
            end
            case ({gold_wr_en, gold_pop_consume})
                2'b10:   gold_count <= gold_count + 1'b1;
                2'b01:   gold_count <= gold_count - 1'b1;
                default: gold_count <= gold_count;
            endcase
        end
    end

    // So sánh DUT vs golden mỗi cycle (sau khi ổn định)
    reg first_cmp;
    integer cycle, err_count, test_id;
    initial begin
        first_cmp = 1;
        cycle     = 0;
        err_count= 0;
        test_id   = 0;
    end

    wire cmp_full_ok = (full === gold_full_out);
    wire cmp_valid_ok = (data_valid === gold_data_valid);
    wire cmp_data_ok = (data_valid && gold_data_valid) ? (data_out === gold_data_out) : 1'b1;
    wire cmp_ok = cmp_full_ok && cmp_valid_ok && cmp_data_ok;

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle <= 0;
        end else begin
            cycle <= cycle + 1;
            if (!first_cmp && !cmp_ok) begin
                err_count <= err_count + 1;
                $display("[FAIL] cycle=%0d | full: dut=%b gold=%b | valid: dut=%b gold=%b | data: dut=0x%08x gold=0x%08x",
                    cycle, full, gold_full_out, data_valid, gold_data_valid, data_out, gold_data_out);
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) first_cmp <= 1;
        else if (cycle >= 2) first_cmp <= 0;
    end

    // ----- Random test + directed -----
    integer seed;
    integer num_cycles;
    integer tc;
    initial begin
        rst_n      = 0;
        push_valid = 0;
        data_in    = 32'b0;
        pop_ready  = 0;
        seed       = 1;
        num_cycles = 2000;

        $display("===== TB vproc_fifo: reset =====");
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        $display("===== Testcase 1: Push full, rồi pop hết =====");
        push_valid = 1;
        pop_ready  = 0;
        for (tc = 0; tc < DEPTH; tc = tc + 1) begin
            data_in = 32'h1000 + tc;
            @(posedge clk);
        end
        push_valid = 0;
        data_in    = 32'b0;
        repeat (2) @(posedge clk);
        pop_ready  = 1;
        repeat (DEPTH + 1) @(posedge clk);
        pop_ready  = 0;
        repeat (2) @(posedge clk);
        $display("  Testcase 1 done.");

        $display("===== Testcase 2: Forwarding (empty + push + pop_ready) =====");
        push_valid = 1;
        data_in    = 32'hDEAD_BEEF;
        pop_ready  = 1;
        @(posedge clk);
        if (data_valid && data_out == 32'hDEAD_BEEF)
            $display("  Forward OK: data_out=0x%08x", data_out);
        else
            $display("  Forward FAIL: data_valid=%b data_out=0x%08x", data_valid, data_out);
        push_valid = 0;
        pop_ready  = 0;
        repeat (2) @(posedge clk);

        $display("===== Testcase 3: Random push/pop (%0d cycles) =====", num_cycles);
        for (tc = 0; tc < num_cycles; tc = tc + 1) begin
            push_valid = $urandom(seed) & 1;
            pop_ready  = $urandom(seed) & 1;
            data_in    = $urandom(seed);
            @(posedge clk);
            if (tc < 20 || tc >= num_cycles - 5 || (tc % 200 == 0))
                $display("  [%0d] push=%b pop_ready=%b full=%b valid=%b data_out=0x%08x",
                    tc, push_valid, pop_ready, full, data_valid, data_out);
        end
        $display("  Random test done.");

        $display("===== Testcase 4: Alternating push then pop (stress) =====");
        push_valid = 0;
        pop_ready  = 0;
        repeat (2) @(posedge clk);
        for (tc = 0; tc < 32; tc = tc + 1) begin
            push_valid = 1;
            data_in    = 32'hA000 + tc;
            pop_ready  = 0;
            @(posedge clk);
            push_valid = 0;
            @(posedge clk);
            pop_ready  = 1;
            @(posedge clk);
            pop_ready  = 0;
            @(posedge clk);
        end
        $display("  Alternating done.");

        repeat (10) @(posedge clk);
        $display("===== TONG KET =====");
        if (err_count == 0)
            $display("PASS: tb_vproc_fifo (0 errors, %0d cycles checked)", cycle);
        else
            $display("FAIL: tb_vproc_fifo (%0d errors)", err_count);
        $finish;
    end

    // Dump waveform (VCD) để mở bằng ModelSim hoặc GTKWave
    initial begin
        $dumpfile("tb_vproc_fifo.vcd");
        $dumpvars(0, tb_vproc_fifo);
    end

endmodule
