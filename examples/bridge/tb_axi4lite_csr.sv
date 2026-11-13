`timescale 1ns/1ps
module tb_axi4lite_csr;
    localparam logic [1:0] OKAY = 2'b00, SLVERR = 2'b10;
    logic clk = 0;
    always #5 clk = ~clk;

    logic resetn = 0;
    logic [31:0] awaddr = 0, wdata = 0, araddr = 0;
    logic [2:0] awprot = 0, arprot = 0;
    logic awvalid = 0, wvalid = 0, bready = 0;
    logic arvalid = 0, rready = 0;
    logic [3:0] wstrb = 0;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;

    axi4lite_csr #(.ID_VALUE(32'hA5C3_1234)) dut (
        .aclk(clk), .aresetn(resetn), .awaddr(awaddr), .awprot(awprot),
        .awvalid(awvalid), .awready(awready), .wdata(wdata), .wstrb(wstrb),
        .wvalid(wvalid), .wready(wready), .bresp(bresp), .bvalid(bvalid),
        .bready(bready), .araddr(araddr), .arprot(arprot), .arvalid(arvalid),
        .arready(arready), .rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready));

    task automatic send_aw(input logic [31:0] addr);
        begin
            @(negedge clk); awaddr = addr; awvalid = 1;
            do @(posedge clk); while (!awready);
            @(negedge clk); awvalid = 0;
        end
    endtask

    task automatic send_w(input logic [31:0] data, input logic [3:0] strb);
        begin
            @(negedge clk); wdata = data; wstrb = strb; wvalid = 1;
            do @(posedge clk); while (!wready);
            @(negedge clk); wvalid = 0;
        end
    endtask

    task automatic take_b(input logic [1:0] expected, input integer stall_cycles);
        integer i;
        logic [1:0] held_resp;
        begin
            bready = 0;
            while (!bvalid) @(posedge clk);
            held_resp = bresp;
            if (bresp !== expected) $fatal(1, "BRESP expected %b got %b", expected, bresp);
            for (i = 0; i < stall_cycles; i = i + 1) begin
                @(posedge clk);
                if (!bvalid || bresp !== held_resp) $fatal(1, "B response changed under backpressure");
            end
            @(negedge clk); bready = 1;
            @(posedge clk);
            @(negedge clk); bready = 0;
        end
    endtask

    task automatic send_ar(input logic [31:0] addr);
        begin
            @(negedge clk); araddr = addr; arvalid = 1;
            do @(posedge clk); while (!arready);
            @(negedge clk); arvalid = 0;
        end
    endtask

    task automatic take_r(input logic [31:0] expected_data, input logic [1:0] expected_resp,
                          input integer stall_cycles);
        integer i;
        logic [31:0] held_data;
        logic [1:0] held_resp;
        begin
            rready = 0;
            while (!rvalid) @(posedge clk);
            held_data = rdata; held_resp = rresp;
            if (rdata !== expected_data || rresp !== expected_resp)
                $fatal(1, "R response expected %h/%b got %h/%b", expected_data, expected_resp, rdata, rresp);
            for (i = 0; i < stall_cycles; i = i + 1) begin
                @(posedge clk);
                if (!rvalid || rdata !== held_data || rresp !== held_resp)
                    $fatal(1, "R response changed under backpressure");
            end
            @(negedge clk); rready = 1;
            @(posedge clk);
            @(negedge clk); rready = 0;
        end
    endtask

    task automatic check_read(input logic [31:0] addr, input logic [31:0] data,
                              input logic [1:0] resp);
        begin send_ar(addr); take_r(data, resp, 0); end
    endtask

    // Global watchdog catches a broken handshake/task instead of hanging forever.
    initial begin
        #100000;
        $fatal(1, "watchdog: testbench timed out");
    end

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk); resetn = 1;

        // Address first, then data: byte lanes 0 and 2 become 11 and 33.
        send_aw(32'h0); send_w(32'h4433_2211, 4'b0101); take_b(OKAY, 0);
        check_read(32'h0, 32'h0033_0011, OKAY);

        // Data first, then address: lanes 1 and 3 replace their old bytes.
        send_w(32'hAABB_CCDD, 4'b1010); send_aw(32'h0); take_b(OKAY, 0);
        check_read(32'h0, 32'hAA33_CC11, OKAY);

        // A zero strobe is a successful no-op for the ordinary CTRL register.
        send_aw(0); send_w(32'hFFFF_FFFF, 4'b0000); take_b(OKAY, 0);
        check_read(0, 32'hAA33_CC11, OKAY);

        // AW and W valid together on a single edge; source holds both through handshake.
        @(negedge clk); awaddr = 0; awvalid = 1; wdata = 32'h1234_5678;
        wstrb = 4'b1111; wvalid = 1;
        do @(posedge clk); while (!(awready && wready));
        @(negedge clk); awvalid = 0; wvalid = 0;
        take_b(OKAY, 0);
        check_read(32'h0, 32'h1234_5678, OKAY);

        // Stall B, verify stable response, and prove read can finish independently.
        send_aw(0); send_w(32'hFACE_CAFE, 4'hF);
        while (!bvalid) @(posedge clk);
        check_read(32'h4, 32'hA5C3_1234, OKAY);
        take_b(OKAY, 3);

        // Stall R while a write completes on the independent write path.
        send_ar(0);
        while (!rvalid) @(posedge clk);
        send_aw(0); send_w(32'h0BAD_F00D, 4'hF); take_b(OKAY, 0);
        take_r(32'hFACE_CAFE, OKAY, 3); // AR acceptance snapshots old CTRL value.
        check_read(0, 32'h0BAD_F00D, OKAY);

        // Read-only ID write, unaligned address and unmapped address all report SLVERR.
        send_aw(4); send_w(32'hFFFF_FFFF, 4'hF); take_b(SLVERR, 0);
        send_aw(1); send_w(32'hFFFF_FFFF, 4'hF); take_b(SLVERR, 0);
        send_aw(8); send_w(32'hFFFF_FFFF, 4'hF); take_b(SLVERR, 0);
        check_read(4, 32'hA5C3_1234, OKAY);
        check_read(1, 0, SLVERR);
        check_read(8, 0, SLVERR);
        check_read(0, 32'h0BAD_F00D, OKAY);

        // AR acceptance and CTRL write commit on the same edge: read sees old state.
        @(negedge clk); araddr = 0; arvalid = 1; awaddr = 0; awvalid = 1;
        wdata = 32'hCAFE_BABE; wstrb = 4'hF; wvalid = 1;
        do @(posedge clk); while (!(arready && awready && wready));
        @(negedge clk); arvalid = 0; awvalid = 0; wvalid = 0;
        take_r(32'h0BAD_F00D, OKAY, 0);
        take_b(OKAY, 0);
        check_read(0, 32'hCAFE_BABE, OKAY);

        // Reset cancels an accepted AW half; a later W half must not match it.
        send_aw(0);
        @(negedge clk); resetn = 0; @(posedge clk); @(negedge clk);
        if (bvalid) $fatal(1, "reset created B response for lone AW");
        resetn = 1;
        send_w(32'h1111_2222, 4'hF);
        repeat (2) begin @(posedge clk); if (bvalid) $fatal(1, "stale AW survived reset"); end
        @(negedge clk); resetn = 0; @(posedge clk); @(negedge clk); resetn = 1;

        // Reset cancels an accepted W half; a later AW half must not match it.
        send_w(32'h3333_4444, 4'hF);
        @(negedge clk); resetn = 0; @(posedge clk); @(negedge clk); resetn = 1;
        send_aw(0);
        repeat (2) begin @(posedge clk); if (bvalid) $fatal(1, "stale W survived reset"); end
        @(negedge clk); resetn = 0; @(posedge clk); @(negedge clk); resetn = 1;

        // Reset while B is stalled clears its response and restores CTRL reset value.
        send_aw(0); send_w(32'hFFFF_0000, 4'hF);
        while (!bvalid) @(posedge clk);
        @(negedge clk); resetn = 0; @(posedge clk); @(negedge clk);
        if (bvalid) $fatal(1, "reset failed to terminate stalled B response");
        resetn = 1;
        check_read(0, 0, OKAY);

        // Reset while R is stalled clears the pending read response.
        send_ar(4);
        while (!rvalid) @(posedge clk);
        @(negedge clk); resetn = 0; @(posedge clk); @(negedge clk);
        if (rvalid) $fatal(1, "reset failed to terminate stalled R response");
        resetn = 1;

        $display("PASS: bounded AXI4-Lite CSR scenarios completed");
        $finish;
    end
endmodule
