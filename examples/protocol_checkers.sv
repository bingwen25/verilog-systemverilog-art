// Verification-only checker; compile separately with an SVA-capable simulator.
// rst_n cancels outstanding obligations. DUT must hold valid and payload
// through a stalled cycle, including the next cycle that accepts the item.
module rv_checker #(parameter integer WIDTH = 8) (
    input logic clk,
    input logic rst_n,
    input logic valid,
    input logic ready,
    input logic [WIDTH-1:0] payload
);
    assert property (@(posedge clk) disable iff (!rst_n)
        valid && !ready |=> valid && $stable(payload));
    assert property (@(posedge clk) disable iff (!rst_n)
        !$isunknown({valid, ready}));
    assert property (@(posedge clk) disable iff (!rst_n)
        valid && ready |-> !$isunknown(payload));
    cover property (@(posedge clk) disable iff (!rst_n)
        (valid && !ready) ##1 (valid && ready));
endmodule
