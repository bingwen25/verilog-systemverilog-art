`timescale 1ns/1ps
// Two-stage pipeline: pair sums, then final sum. II=1, one extra cycle latency.
module add4_pipeline (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic [31:0] a, b, c, d,
    output logic        out_valid,
    output logic [31:0] q
);
    logic [31:0] ab, cd;
    logic        valid_s1;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ab        <= 32'b0;
            cd        <= 32'b0;
            valid_s1  <= 1'b0;
            q         <= 32'b0;
            out_valid <= 1'b0;
        end else begin
            valid_s1 <= in_valid;
            if (in_valid) begin
                ab <= a + b;
                cd <= c + d;
            end
            out_valid <= valid_s1;
            if (valid_s1)
                q <= ab + cd;
        end
    end
endmodule
