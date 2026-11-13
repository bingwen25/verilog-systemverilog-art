# 附录H 三个案例的完整教学 RTL

本附录让纸书与离线阅读版也能完成“契约→实现”的阅读闭环。代码直接从配套源文件纳入，不维护第二份手工副本；`examples/` 中的源码是可执行版本的唯一来源。对应自检、配置和工具记录见文末验证记录。

这些实现用于教学。Timer/FIFO参数合法性检查中的`initial $fatal`用于仿真/构建诊断，不构成对所有ASIC综合工具的支持承诺；生产集成可把配置检查放在构建阶段。FIFO的组合读不承诺推断为块RAM。案例C不提供完整AXI协议认证或安全隔离。

## H.1 案例 A（Timer）的完整 RTL

第2章规定接受后第N个后续边沿完成；取消优先、忙时启动不接受，`period=0`不接受。参数W≥1，本次回归W=8。

```systemverilog
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
```

## H.2 案例 B（FIFO）的完整 RTL

单时钟、组合首字可见、空态无直通、满态保守回压；非二次幂地址显式绕回。本次回归WIDTH=16、DEPTH=1/3/4。

```systemverilog
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
```

## H.3 案例 C（AXI4-Lite CSR）的完整 RTL

32位数据，AW与W独立一槽，读写各一笔在途；响应背压保持，支持WSTRB，同沿读与写提交返回旧CTRL。

```systemverilog
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
```
