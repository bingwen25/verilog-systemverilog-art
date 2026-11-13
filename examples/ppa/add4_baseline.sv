`timescale 1ns/1ps
// Single-output-register reference: accepts one valid tuple per cycle.
module add4_baseline (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic [31:0] a, b, c, d,
    output logic        out_valid,
    output logic [31:0] q
);
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            q         <= 32'b0;
        end else begin
            out_valid <= in_valid;
            if (in_valid)
                q <= a + b + c + d;
        end
    end
endmodule
