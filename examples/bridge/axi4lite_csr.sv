`timescale 1ns/1ps
// Small, deliberately bounded AXI4-Lite CSR slave for a 32-bit single-clock system.
// One AW slot, one W slot, one B response slot; one AR/R transaction at a time.
module axi4lite_csr #(
    parameter logic [31:0] ID_VALUE = 32'hA5C3_1234
) (
    input  logic        aclk,
    input  logic        aresetn, // synchronous, active low

    input  logic [31:0] awaddr,
    input  logic [2:0]  awprot,
    input  logic        awvalid,
    output logic        awready,

    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    input  logic        wvalid,
    output logic        wready,

    output logic [1:0]  bresp,
    output logic        bvalid,
    input  logic        bready,

    input  logic [31:0] araddr,
    input  logic [2:0]  arprot,
    input  logic        arvalid,
    output logic        arready,

    output logic [31:0] rdata,
    output logic [1:0]  rresp,
    output logic        rvalid,
    input  logic        rready
);
    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;

    logic [31:0] ctrl_q;
    logic        aw_pending_q, w_pending_q;
    logic [31:0] awaddr_q, wdata_q;
    logic [3:0]  wstrb_q;

    logic aw_hs, w_hs, ar_hs;
    logic wr_complete;
    logic [31:0] wr_addr, wr_data;
    logic [3:0]  wr_strb;
    logic [1:0]  wr_resp;
    logic [1:0]  rd_resp;
    logic [31:0] rd_data;
    integer lane;

    // READY is low while the corresponding one-entry slot (or response) is occupied.
    // AW and W are independent: either one can be accepted before its partner.
    assign awready = aresetn && !aw_pending_q && !bvalid;
    assign wready  = aresetn && !w_pending_q  && !bvalid;
    assign arready = aresetn && !rvalid;

    assign aw_hs = awvalid && awready;
    assign w_hs  = wvalid  && wready;
    assign ar_hs = arvalid && arready;

    // Select the stored half when present, otherwise the half arriving this edge.
    assign wr_addr = aw_pending_q ? awaddr_q : awaddr;
    assign wr_data = w_pending_q  ? wdata_q  : wdata;
    assign wr_strb = w_pending_q  ? wstrb_q  : wstrb;
    assign wr_complete = !bvalid && (aw_pending_q || aw_hs) && (w_pending_q || w_hs);

    always_comb begin
        if (wr_addr[1:0] != 2'b00 || wr_addr != 32'h0000_0000)
            wr_resp = RESP_SLVERR; // address 4 is read-only; every other address is unmapped
        else
            wr_resp = RESP_OKAY;

        if (araddr[1:0] != 2'b00 || (araddr != 32'h0000_0000 && araddr != 32'h0000_0004)) begin
            rd_data = 32'h0000_0000;
            rd_resp = RESP_SLVERR;
        end else if (araddr == 32'h0000_0000) begin
            rd_data = ctrl_q;
            rd_resp = RESP_OKAY;
        end else begin
            rd_data = ID_VALUE;
            rd_resp = RESP_OKAY;
        end
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            ctrl_q       <= 32'h0000_0000;
            aw_pending_q <= 1'b0;
            w_pending_q  <= 1'b0;
            awaddr_q     <= 32'h0000_0000;
            wdata_q      <= 32'h0000_0000;
            wstrb_q      <= 4'b0000;
            bvalid       <= 1'b0;
            bresp        <= RESP_OKAY;
            rvalid       <= 1'b0;
            rdata        <= 32'h0000_0000;
            rresp        <= RESP_OKAY;
        end else begin
            // Response slots retire only on VALID && READY. Payload stays unchanged
            // for the entire backpressure interval.
            if (bvalid && bready)
                bvalid <= 1'b0;
            if (rvalid && rready)
                rvalid <= 1'b0;

            if (aw_hs) begin
                awaddr_q     <= awaddr;
                aw_pending_q <= 1'b1;
            end
            if (w_hs) begin
                wdata_q      <= wdata;
                wstrb_q      <= wstrb;
                w_pending_q  <= 1'b1;
            end

            // Commit exactly once after both independent halves have arrived.
            // Later assignments intentionally clear pending bits even when the
            // second half is accepted in this same edge.
            if (wr_complete) begin
                aw_pending_q <= 1'b0;
                w_pending_q  <= 1'b0;
                bresp        <= wr_resp;
                bvalid       <= 1'b1;
                if (wr_resp == RESP_OKAY) begin
                    for (lane = 0; lane < 4; lane = lane + 1)
                        if (wr_strb[lane])
                            ctrl_q[lane*8 +: 8] <= wr_data[lane*8 +: 8];
                end
            end

            // A read snapshots its selected value/response when AR is accepted.
            if (ar_hs) begin
                rdata  <= rd_data;
                rresp  <= rd_resp;
                rvalid <= 1'b1;
            end
        end
    end

    // PROT is part of the optional AXI4-Lite signal set but intentionally ignored:
    // this small example provides no privilege/security filtering.
    logic unused_prot;
    assign unused_prot = ^{awprot, arprot};
endmodule
