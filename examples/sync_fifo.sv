`timescale 1ns/1ps
// Conservative ready/valid synchronous FIFO.
// The output is a combinational view of the current read slot.  Empty FIFOs
// never pass input data directly to the output, and a full FIFO does not
// accept a write even if a read is also requested on that edge.
module sync_fifo #(
    parameter integer WIDTH = 8,
    parameter integer DEPTH = 4
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 in_valid,
    output logic                 in_ready,
    input  logic [WIDTH-1:0]     in_data,
    output logic                 out_valid,
    input  logic                 out_ready,
    output logic [WIDTH-1:0]     out_data
);
    localparam integer PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam integer CNT_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);
    localparam logic [PTR_W-1:0] LAST_PTR = DEPTH - 1;
    localparam logic [CNT_W-1:0] DEPTH_COUNT = DEPTH;

    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [PTR_W-1:0] rd_ptr;
    logic [PTR_W-1:0] wr_ptr;
    logic [CNT_W-1:0] count;
    logic do_write;
    logic do_read;

    assign in_ready  = (count < DEPTH_COUNT);
    assign out_valid = (count != 0);
    assign out_data  = mem[rd_ptr];
    assign do_write  = in_valid && in_ready;
    assign do_read   = out_valid && out_ready;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr <= '0;
            wr_ptr <= '0;
            count  <= '0;
        end else begin
            if (do_write) begin
                mem[wr_ptr] <= in_data;
                if (wr_ptr == LAST_PTR)
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end

            if (do_read) begin
                if (rd_ptr == LAST_PTR)
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end

            case ({do_write, do_read})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

    initial begin
        if (WIDTH < 1) $fatal(1, "sync_fifo parameter WIDTH must be >= 1");
        if (DEPTH < 1) $fatal(1, "sync_fifo parameter DEPTH must be >= 1");
    end
endmodule
