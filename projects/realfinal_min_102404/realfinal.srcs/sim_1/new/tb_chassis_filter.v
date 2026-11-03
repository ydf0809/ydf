`timescale 1ns / 1ps

module tb_chassis_filter;

parameter CLK_FREQ = 33333333;

localparam CLK_PERIOD = 1000000000 / CLK_FREQ;

reg        clk;
reg        rst_n;
reg        sw;
reg [10:0] bx, by, bw, bh;
wire [7:0] m1, m2, m3, m4;
wire       upd;
integer    errors;
integer    k;

chassis_control #(.REF_DELAY(2000)) u_chassis(
    .clk        (clk),
    .rst_n      (rst_n),
    .sw         (sw),
    .box_x      (bx),
    .box_y      (by),
    .box_w      (bw),
    .box_h      (bh),
    .out_m1     (m1),
    .out_m2     (m2),
    .out_m3     (m3),
    .out_m4     (m4),
    .cmd_update (upd)
);

initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

task wait_tick;
    begin
        @(posedge upd);
        #1;
    end
endtask

function integer s8;
    input [7:0] v;
    begin
        s8 = (v[7]) ? (v - 256) : v;
    end
endfunction

initial begin
    errors = 0;
    rst_n  = 1'b0;
    sw     = 1'b0;
    bx = 11'd150; by = 11'd200; bw = 11'd100; bh = 11'd100;
    repeat(10) @(posedge clk);
    rst_n = 1'b1;
    repeat(10) @(posedge clk);

    $display("==================================================");
    $display(" tb_chassis_filter: CLK_FREQ=%0d", CLK_FREQ);
    $display("==================================================");

    $display("--- 1) sw=0: all speeds 0 ---");
    wait_tick;
    if((s8(m1) != 0) || (s8(m2) != 0) || (s8(m3) != 0) || (s8(m4) != 0)) begin
        $display("[FAIL] disabled: %0d %0d %0d %0d", s8(m1), s8(m2), s8(m3), s8(m4));
        errors = errors + 1;
    end
    else
        $display("[ OK ] disabled -> all speeds 0");

    $display("--- 2) enable with the box at its reference size ---");
    @(posedge clk);
    sw <= 1'b1;
    wait_tick;
    wait_tick;
    if((s8(m1) != 0) || (s8(m4) != 0)) begin
        $display("[FAIL] at reference size: m1=%0d m4=%0d (expected 0)", s8(m1), s8(m4));
        errors = errors + 1;
    end
    else
        $display("[ OK ] at reference size -> 0 (inside the dead band)");

    $display("--- 3) +20 px size error: filtered, not a jump ---");
    bw = 11'd80; bh = 11'd80;
    wait_tick;
    $display("      first tick: m1=%0d m2=%0d m3=%0d m4=%0d", s8(m1), s8(m2), s8(m3), s8(m4));
    if((s8(m1) < 2) || (s8(m1) > 3)) begin
        $display("[FAIL] first tick m1=%0d, expected about 2 (filtered, half gain)", s8(m1));
        errors = errors + 1;
    end
    else
        $display("[ OK ] first tick is about 2, not 10 -> filter + half gain working");
    for(k = 0; k < 10; k = k + 1) wait_tick;
    $display("      after 10 ticks: m1=%0d m2=%0d", s8(m1), s8(m2));
    if((s8(m1) < 8) || (s8(m1) > 10)) begin
        $display("[FAIL] after 10 ticks m1=%0d, expected to approach the clamp", s8(m1));
        errors = errors + 1;
    end
    else
        $display("[ OK ] converged towards the full error");
    if((s8(m2) > -8) || (s8(m2) < -10)) begin
        $display("[FAIL] m2=%0d, expected about -10 (opposite wheel pair)", s8(m2));
        errors = errors + 1;
    end
    else
        $display("[ OK ] opposite wheel pair gets the opposite sign");

    $display("--- 4) large error stays inside the +-12 clamp ---");
    bw = 11'd10; bh = 11'd10;
    for(k = 0; k < 12; k = k + 1) wait_tick;
    $display("      saturated: m1=%0d m2=%0d", s8(m1), s8(m2));
    if((s8(m1) != 12) || (s8(m2) != -12)) begin
        $display("[FAIL] clamp: m1=%0d m2=%0d (expected 12 / -12)", s8(m1), s8(m2));
        errors = errors + 1;
    end
    else
        $display("[ OK ] clamped at +-10");

    $display("--- 5) turning: target above / below centre ---");
    bw = 11'd100; bh = 11'd100;
    by = 11'd260;
    for(k = 0; k < 12; k = k + 1) wait_tick;
    $display("      box_y=260: m1=%0d m2=%0d m3=%0d m4=%0d", s8(m1), s8(m2), s8(m3), s8(m4));

    if(!((s8(m1) > 0) && (s8(m3) > 0) && (s8(m2) < 0) && (s8(m4) < 0))) begin
        $display("[FAIL] turning sign for box_y>200 looks wrong");
        errors = errors + 1;
    end
    else
        $display("[ OK ] turning response has the expected sign pair");
    by = 11'd140;
    for(k = 0; k < 20; k = k + 1) wait_tick;
    $display("      box_y=140: m1=%0d m2=%0d m3=%0d m4=%0d", s8(m1), s8(m2), s8(m3), s8(m4));
    if(!((s8(m1) < 0) && (s8(m3) < 0) && (s8(m2) > 0) && (s8(m4) > 0))) begin
        $display("[FAIL] turning sign for box_y<200 looks wrong");
        errors = errors + 1;
    end
    else
        $display("[ OK ] turning response flips with the target side");

    $display("==================================================");
    if(errors == 0)
        $display(" RESULT: all passed (errors=0)");
    else
        $display(" RESULT: %0d checks failed", errors);
    $display("==================================================");
    $finish;
end

endmodule
