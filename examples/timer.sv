`timescale 1ns/1ps
// Simple synchronous countdown timer.
// A start accepted while idle loads PERIOD.  The timer completes after
// PERIOD subsequent rising clock edges; PERIOD=1 completes on the next edge.
module timer #(
    parameter integer W = 16
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,
    input  logic         cancel,
    input  logic [W-1:0] period,
    output logic         busy,
    output logic         done
);
    logic [W-1:0] count;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            count <= '0;
            busy  <= 1'b0;
            done  <= 1'b0;
        end else begin
            // done is a one-clock pulse, including when requests are present.
            done <= 1'b0;

            if (busy) begin
                // Cancellation wins over expiration on the same edge.
                if (cancel) begin
                    count <= '0;
                    busy  <= 1'b0;
                end else if (count == 1) begin
                    count <= '0;
                    busy  <= 1'b0;
                    done  <= 1'b1;
                end else begin
                    count <= count - 1'b1;
                end
            end else if (start && !cancel && (period != '0)) begin
                count <= period;
                busy  <= 1'b1;
            end
        end
    end

    initial begin
        if (W < 1) $fatal(1, "timer parameter W must be >= 1");
    end
endmodule
