`timescale 1ns/1ps
module part_select_tb;
    logic signed [7:0] s;
    logic signed [8:0] whole, slice, recast;
    assign whole = s;
    assign slice = s[7:0];
    assign recast = $signed(s[7:0]);
    initial begin
        s = 8'hff;
        #1;
        if (whole !== -9'sd1 || slice !== 9'sd255 || recast !== -9'sd1)
            $fatal(1, "part-select signedness mismatch");
        $display("s=ff: whole=%0d slice=%0d recast=%0d", whole, slice, recast);
        s = 8'h80;
        #1;
        if (whole !== -9'sd128 || slice !== 9'sd128 || recast !== -9'sd128)
            $fatal(1, "part-select sign boundary mismatch");
        $display("s=80: whole=%0d slice=%0d recast=%0d", whole, slice, recast);
        $display("PASS part-select signedness");
        $finish;
    end
endmodule
