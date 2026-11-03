`timescale 1ns / 1ps
module tb_motion_candidate_priority;
    reg clk=0;
    always #15 clk=~clk;
    reg rst_n=0, enable=1, update=0;
    reg pv=1, sv=1;
    reg [8:0] px=50, sx=150;
    reg [7:0] py=40, sy=120;
    wire ready, valid, secondary, preferred;
    wire [8:0] cx;
    wire [7:0] cy;
    integer errors=0, i;
    motion_candidate_priority dut (
        .clk(clk),.rst_n(rst_n),.enable(enable),.update(update),
        .primary_valid(pv),.primary_x(px),.primary_y(py),
        .secondary_valid(sv),.secondary_x(sx),.secondary_y(sy),
        .result_valid(ready),.candidate_valid(valid),.candidate_x(cx),.candidate_y(cy),
        .selected_secondary(secondary),.motion_preferred(preferred)
    );
    task check;
        input condition;
        input [8*110-1:0] message;
        begin
            if (!condition) begin
                $display("ERROR: %0s selected=%0d x=%0d y=%0d preferred=%0d",message,secondary,cx,cy,preferred);
                errors=errors+1;
            end
        end
    endtask
    task reset;
        begin
            @(negedge clk); rst_n=0;
            repeat(3) @(negedge clk);
            rst_n=1; enable=1; pv=1; sv=1;
            px=50; py=40; sx=150; sy=120;
        end
    endtask
    task sample;
        begin
            @(negedge clk); update=1;
            @(posedge clk); #1;
            check(ready,"candidate update did not produce a result");
            @(negedge clk); update=0;
        end
    endtask
    initial begin
        reset;

        for(i=0;i<8;i=i+1) begin
            px=50+(i%2); sx=150+4*i;
            sample;
            if(i<7) check(valid && !secondary && !preferred,"trajectory bonus applied before eight observations");
        end
        check(valid && secondary && preferred && cx==178,"weaker moving candidate did not outrank static flicker");

        px=182; py=120; sx=50; sy=40;
        sample;
        check(valid && !secondary && preferred && cx==182,"strength swap lost the moving target identity");
        px=50; py=40; sx=186; sy=120;
        sample;
        check(secondary && preferred && cx==186,"second strength swap transferred history to the wrong target");

        reset;
        for(i=0;i<12;i=i+1) begin
            px=50+(i%2); sx=150+(i%3);
            sample;
            check(valid && !secondary && !preferred,"small-region jitter received a motion bonus");
        end
        reset;
        for(i=0;i<12;i=i+1) begin
            sx=150+((i%2)*30);
            sample;
            check(valid && !secondary && !preferred,"two alternating distant spots were treated as coherent travel");
        end
        reset;
        for(i=0;i<8;i=i+1) begin
            sx=(i==0)?150:180;
            sample;
            check(!secondary && !preferred,"one displacement followed by rest received a motion bonus");
        end
        reset;
        for(i=0;i<8;i=i+1) begin
            sx=150+3*i;
            sample;
        end
        check(!secondary && !preferred,"42-display-pixel displacement passed the 48-pixel threshold");
        sx=174; sample;
        check(!secondary && !preferred,"sliding eight-frame window incorrectly included a ninth old observation");

        reset;
        for(i=0;i<8;i=i+1) begin
            sx=150+((i<7)?4*i:24);
            sample;
        end
        check(secondary && preferred,"exactly 48 preview pixels failed to reach the motion threshold");

        reset;
        for(i=0;i<8;i=i+1) begin sx=150+4*i; sample; end
        check(secondary && preferred,"setup for continuity reset failed");
        sv=0; sample;
        check(valid && !secondary,"missing mover did not preserve the stationary fallback");
        sv=1;
        for(i=0;i<7;i=i+1) begin
            sx=180+4*i; sample;
            check(!secondary && !preferred,"missing observations did not reset motion history");
        end
        sx=208; sample;
        check(secondary && preferred,"mover did not recover after eight new observations");
        sx=290; sample;
        check(!secondary && !preferred,"teleport beyond continuity gate retained motion bonus");
        @(negedge clk); enable=0;
        @(posedge clk); #1;
        check(!valid && !ready && !preferred,"entering local tracking did not flush global history");
        @(negedge clk); enable=1; pv=0; sv=0;
        sample;
        check(!valid,"absent candidates produced a valid result");
        if(errors==0) $display("MOTION_PRIORITY_TEST: PASS");
        else $display("MOTION_PRIORITY_TEST: FAIL (%0d errors)",errors);
        $finish;
    end
    initial begin #1000000; $display("MOTION_PRIORITY_TEST: FAIL (timeout)"); $finish; end
endmodule
