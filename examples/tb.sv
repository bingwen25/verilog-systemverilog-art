`timescale 1ns/1ps

module fifo_case #(
    parameter integer DEPTH = 4,
    parameter integer ID = 0
) (
    input  logic clk,
    input  logic rst_n,
    output logic finished
);
    localparam integer WIDTH = 16;
    localparam integer MAX_TXNS = 10000;

    logic in_valid;
    logic in_ready;
    logic [WIDTH-1:0] in_data;
    logic out_valid;
    logic out_ready;
    logic [WIDTH-1:0] out_data;
    logic hold_input;
    logic [WIDTH-1:0] model [0:MAX_TXNS-1];
    integer head;
    integer tail;
    integer cycle;
    integer seed;
    logic expected_ready;
    logic expected_valid;
    integer sent;
    integer received;
    integer drain_i;

    function automatic logic [WIDTH-1:0] data_for(input integer tag, input integer seq_number);
        integer value;
        integer bit_index;
        begin
            value = (tag * 4096) ^ (seq_number * 17 + 565);
            for (bit_index = 0; bit_index < WIDTH; bit_index = bit_index + 1)
                data_for[bit_index] = value[bit_index];
        end
    endfunction

    sync_fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
        .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data)
    );

    initial begin
        finished = 1'b0;
        in_valid = 1'b0;
        in_data = '0;
        out_ready = 1'b0;
        hold_input = 1'b0;
        head = 0;
        tail = 0;
        sent = 0;
        received = 0;
        seed = 32'h4f1bbcdc ^ (DEPTH * 32'h1020304);
        wait (rst_n === 1'b1);

        for (cycle = 0; cycle < 1800; cycle = cycle + 1) begin
            @(negedge clk);
            // Once a beat is stalled, preserve valid and data until accepted,
            // even when the directed phase changes in the meantime.
            if (!hold_input) begin
                // Directed fill/overflow, simultaneous full read/write, and drain.
                if (cycle < DEPTH + 2) begin
                    in_valid = 1'b1;
                end else if (cycle < DEPTH + 5) begin
                    in_valid = 1'b1;
                end else if (cycle < DEPTH + 10) begin
                    in_valid = 1'b0;
                end else begin
                    in_valid = ($urandom(seed) % 100) < 62;
                end
                in_data = data_for(ID, cycle);
            end
            // Output readiness is independent of source backpressure.
            if (cycle < DEPTH + 2)
                out_ready = 1'b0;
            else if (cycle < DEPTH + 5)
                out_ready = 1'b1;
            else if (cycle < DEPTH + 10)
                out_ready = 1'b1;
            else
                out_ready = ($urandom(seed) % 100) < 57;
        end

        // Drain without withdrawing an input beat that is still stalled.
        for (drain_i = 0; drain_i < DEPTH + 3; drain_i = drain_i + 1) begin
            @(negedge clk);
            if (!hold_input) in_valid = 1'b0;
            out_ready = 1'b1;
            @(posedge clk);
        end
        #1;
        if (head != tail)
            $fatal(1, "FIFO depth %0d did not drain: model count %0d", DEPTH, tail-head);
        if (out_valid !== 1'b0)
            $fatal(1, "FIFO depth %0d remains valid after drain", DEPTH);
        finished = 1'b1;
        $display("PASS fifo depth=%0d sent=%0d received=%0d", DEPTH, sent, received);
    end

    // Scoreboard samples pre-edge values, matching ready/valid transfer rules.
    always @(posedge clk) begin
        if (!rst_n) begin
            head = 0;
            tail = 0;
            hold_input = 1'b0;
        end else if (!finished) begin
            hold_input = in_valid && !in_ready;
            expected_ready = (tail - head < DEPTH);
            expected_valid = (tail - head != 0);
            if (in_ready !== expected_ready)
                $fatal(1, "FIFO depth %0d cycle %0d in_ready mismatch", DEPTH, cycle);
            if (out_valid !== expected_valid)
                $fatal(1, "FIFO depth %0d cycle %0d out_valid mismatch", DEPTH, cycle);
            if (expected_valid && (out_data !== model[head]))
                $fatal(1, "FIFO depth %0d cycle %0d data mismatch: got %h expected %h",
                       DEPTH, cycle, out_data, model[head]);

            if (out_valid && out_ready) begin
                head = head + 1;
                received = received + 1;
            end
            if (in_valid && in_ready) begin
                if (tail >= MAX_TXNS) $fatal(1, "FIFO scoreboard capacity exceeded");
                model[tail] = in_data;
                tail = tail + 1;
                sent = sent + 1;
            end
        end
    end
endmodule

module tb;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    logic start;
    logic cancel;
    logic [7:0] period;
    logic busy;
    logic done;
    logic fifo1_done, fifo3_done, fifo4_done;
    integer timer_i;

    timer #(.W(8)) timer_dut (
        .clk(clk), .rst_n(rst_n), .start(start), .cancel(cancel),
        .period(period), .busy(busy), .done(done)
    );

    fifo_case #(.DEPTH(1), .ID(1)) fifo_depth1(clk, rst_n, fifo1_done);
    fifo_case #(.DEPTH(3), .ID(3)) fifo_depth3(clk, rst_n, fifo3_done);
    fifo_case #(.DEPTH(4), .ID(4)) fifo_depth4(clk, rst_n, fifo4_done);

    task automatic timer_step(
        input logic step_start,
        input logic step_cancel,
        input logic [7:0] step_period,
        input logic expected_busy,
        input logic expected_done
    );
        begin
            @(negedge clk);
            start = step_start;
            cancel = step_cancel;
            period = step_period;
            @(posedge clk);
            #1;
            if (busy !== expected_busy || done !== expected_done)
                $fatal(1, "timer mismatch: busy=%b done=%b expected busy=%b done=%b",
                       busy, done, expected_busy, expected_done);
        end
    endtask

    initial begin
        start = 1'b0;
        cancel = 1'b0;
        period = '0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Zero is rejected; start+cancel is rejected while idle.
        timer_step(1, 0, 0, 0, 0);
        timer_step(1, 1, 5, 0, 0);
        // Period 1 completes on the next edge. Keep start high through the
        // completion edge, then show that a still-high start is accepted once
        // the timer is idle on the following edge.
        timer_step(1, 0, 1, 1, 0);
        timer_step(1, 0, 1, 0, 1);
        timer_step(1, 0, 1, 1, 0);
        timer_step(0, 0, 0, 0, 1);
        // Period 3 means three subsequent edges; busy start is ignored.
        timer_step(1, 0, 3, 1, 0);
        timer_step(1, 0, 7, 1, 0);
        timer_step(0, 0, 0, 1, 0);
        timer_step(0, 0, 0, 0, 1);
        // Cancellation at the nominal terminal edge suppresses done.
        timer_step(1, 0, 2, 1, 0);
        timer_step(0, 0, 0, 1, 0);
        timer_step(0, 1, 0, 0, 0);
        // W=8 can represent 255. Verify exactly 255 subsequent edges.
        timer_step(1, 0, 255, 1, 0);
        for (timer_i = 1; timer_i <= 255; timer_i = timer_i + 1)
            timer_step(0, 0, 0, (timer_i < 255), (timer_i == 255));
        // Reset is synchronous and clears a running timer.
        timer_step(1, 0, 8, 1, 0);
        @(negedge clk);
        rst_n = 1'b0;
        @(posedge clk);
        #1;
        if (busy !== 1'b0 || done !== 1'b0) $fatal(1, "timer reset failed");
        @(negedge clk);
        rst_n = 1'b1;
        $display("PASS timer directed cases");

        wait (fifo1_done && fifo3_done && fifo4_done);
        $display("PASS all examples");
        $finish;
    end

    initial begin
        #30000;
        $fatal(1, "testbench timeout");
    end
endmodule
