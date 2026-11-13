`timescale 1ns/1ps
module tb_add4;
    logic clk = 0;
    always #5 clk = ~clk;

    logic rst_n = 0;
    logic in_valid = 0;
    logic [31:0] a = 0, b = 0, c = 0, d = 0;
    wire base_valid, pipe_valid;
    wire [31:0] base_q, pipe_q;

    add4_baseline u_base (.*,.out_valid(base_valid),.q(base_q));
    add4_pipeline u_pipe (.*,.out_valid(pipe_valid),.q(pipe_q));

    logic exp_base_valid = 0, exp_pipe_valid1 = 0, exp_pipe_valid = 0;
    logic [31:0] exp_base_q = 0, exp_pipe_q1 = 0, exp_pipe_q = 0;
    logic align_valid;
    logic [31:0] align_q;
    integer accepted = 0, base_seen = 0, pipe_seen = 0, cycles = 0;
    integer seed = 32'h51a7c0de;
    integer i;

    task automatic drive(input logic v, input logic [31:0] av,bv,cv,dv);
        @(negedge clk);
        in_valid = v; a = av; b = bv; c = cv; d = dv;
    endtask

    // Compare each implementation to its own latency model, then compare
    // transaction streams in order. This intentionally is not cycle equivalence.
    always @(posedge clk) begin
        // The pipeline result after this edge must match the baseline result
        // that existed just before this edge (same accepted transaction).
        align_valid = base_valid;
        align_q = base_q;
        if (!rst_n) begin
            exp_base_valid <= 0;
            exp_pipe_valid1 <= 0;
            exp_pipe_valid <= 0;
            exp_base_q <= 0;
            exp_pipe_q1 <= 0;
            exp_pipe_q <= 0;
        end else begin
            exp_base_valid <= in_valid;
            if (in_valid)
                exp_base_q <= a + b + c + d;
            exp_pipe_valid1 <= in_valid;
            exp_pipe_valid <= exp_pipe_valid1;
            if (in_valid)
                exp_pipe_q1 <= a + b + c + d;
            if (exp_pipe_valid1)
                exp_pipe_q <= exp_pipe_q1;
            if (in_valid) accepted <= accepted + 1;
        end
        cycles <= cycles + 1;
        #1;
        if (base_valid !== exp_base_valid)
            $fatal(1, "baseline valid mismatch cycle=%0d got=%b expected=%b", cycles, base_valid, exp_base_valid);
        if (pipe_valid !== exp_pipe_valid)
            $fatal(1, "pipeline valid mismatch cycle=%0d got=%b expected=%b", cycles, pipe_valid, exp_pipe_valid);
        if (base_valid) begin
            if (base_q !== exp_base_q) $fatal(1, "baseline data mismatch cycle=%0d", cycles);
            base_seen <= base_seen + 1;
        end
        if (pipe_valid) begin
            if (pipe_q !== exp_pipe_q) $fatal(1, "pipeline data mismatch cycle=%0d", cycles);
            pipe_seen <= pipe_seen + 1;
        end
        if (rst_n && pipe_valid !== align_valid)
            $fatal(1, "latency-aligned valid mismatch cycle=%0d", cycles);
        if (rst_n && pipe_valid && pipe_q !== align_q)
            $fatal(1, "latency-aligned data mismatch cycle=%0d", cycles);
    end

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1;
        // Directed wraparound and max throughput burst.
        drive(1, 32'hffff_ffff, 1, 2, 3);
        drive(1, 32'h8000_0000, 32'h8000_0000, 32'hffff_ffff, 1);
        drive(1, 32'hffff_ffff, 32'hffff_ffff, 32'hffff_ffff, 32'hffff_ffff);
        drive(1, 1, 2, 3, 4);
        // Include bubbles and deterministic pseudo-random operands.
        for (i = 0; i < 300; i = i + 1) begin
            seed = seed * 1664525 + 1013904223;
            drive((i % 7 != 2) && (i % 11 != 4), seed, seed ^ 32'h13579bdf,
                  seed + 32'hdeadbeef, seed * 3);
        end
        drive(0,0,0,0,0);
        drive(0,0,0,0,0);
        drive(0,0,0,0,0);
        @(negedge clk);
        if (base_seen != accepted || pipe_seen != accepted)
            $fatal(1, "count mismatch accepted=%0d base=%0d pipe=%0d", accepted, base_seen, pipe_seen);
        $display("PASS add4 transactions=%0d baseline_latency=1 pipeline_latency=2 extra_latency=1", accepted);
        $finish;
    end
endmodule
