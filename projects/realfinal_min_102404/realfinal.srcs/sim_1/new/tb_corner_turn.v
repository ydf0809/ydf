`timescale 1ns / 1ps
//============================================================================
// tb_corner_turn.v -- self-check for corner_turn
//
// 1MHz clock, everything in ms. pat[4] is the leftmost sensor.
//   left three  = 5'b11100
//   right three = 5'b00111
//   centered    = 5'b00100
//============================================================================

module tb_corner_turn;

    parameter CLK_FREQ = 1000000;

    reg clk = 1'b0;
    always #500 clk = ~clk;

    integer errors = 0;

    reg  rst_n = 1'b0;
    reg  run_en = 1'b1;
    reg  [4:0] pat = 5'b00000;
    reg  line_valid = 1'b1;
    wire signed [7:0] dl, dr;
    wire busy;

    // STOP_ON_LINE = 1 : stop as soon as the center sensor sees the line again
    corner_turn #(
        .CLK_FREQ_HZ  (CLK_FREQ),
        .FORWARD_MS   (3),
        .SPIN_MS      (6),
        .MIN_SPIN_MS  (2),
        .TIMEOUT_MS   (30),
        .COOLDOWN_MS  (10),
        .CONFIRM_MS   (2),
        .FORWARD_SPEED(8'sd16),
        .SPIN_SPEED   (8'sd20),
        .STOP_ON_LINE (1'b1)
    ) dut (
        .clk(clk), .rst_n(rst_n), .run_en(run_en),
        .pat(pat), .line_valid(line_valid),
        .pid_left(8'sd5), .pid_right(8'sd5),
        .out_left(dl), .out_right(dr), .busy(busy)
    );

    // STOP_ON_LINE = 0 : pure timer
    reg  [4:0] pat2 = 5'b00000;
    wire signed [7:0] d2l, d2r;
    wire busy2;

    corner_turn #(
        .CLK_FREQ_HZ  (CLK_FREQ),
        .FORWARD_MS   (2),
        .SPIN_MS      (4),
        .MIN_SPIN_MS  (1),
        .TIMEOUT_MS   (30),
        .COOLDOWN_MS  (2),
        .CONFIRM_MS   (2),
        .FORWARD_SPEED(8'sd16),
        .SPIN_SPEED   (8'sd20),
        .STOP_ON_LINE (1'b0)
    ) dut2 (
        .clk(clk), .rst_n(rst_n), .run_en(run_en),
        .pat(pat2), .line_valid(line_valid),
        .pid_left(8'sd5), .pid_right(8'sd5),
        .out_left(d2l), .out_right(d2r), .busy(busy2)
    );

    task expect2;
        input [8*40-1:0] name;
        input integer gl, gr;
        input integer el, er;
        begin
            if ((gl !== el) || (gr !== er)) begin
                $display("[FAIL] %0s : got %0d/%0d, expect %0d/%0d", name, gl, gr, el, er);
                errors = errors + 1;
            end else begin
                $display("[ OK ] %0s : %0d/%0d", name, gl, gr);
            end
        end
    endtask

    task expect_busy;
        input [8*40-1:0] name;
        input integer gb;
        input integer eb;
        begin
            if (gb !== eb) begin
                $display("[FAIL] %0s : busy=%0d, expect %0d", name, gb, eb);
                errors = errors + 1;
            end else begin
                $display("[ OK ] %0s : busy=%0d", name, gb);
            end
        end
    endtask

    initial begin
        $display("== tb_corner_turn start ==");
        #20_000;
        rst_n = 1'b1;

        // ---- idle: PID passes through untouched ----
        #2_000_000;
        expect2("idle passthrough", dl, dr, 5, 5);
        expect_busy("idle not busy", busy, 0);

        // ---- left three -> short forward ----
        pat = 5'b11100;
        #3_500_000;                       // 2ms confirm + 1.5ms of forward
        expect_busy("left3 -> forward", busy, 1);
        expect2("forward straight", dl, dr, 16, 16);

        // ---- after FORWARD_MS -> spin left (left wheel back) ----
        #4_500_000;
        expect2("spin left", dl, dr, -20, 20);

        // ---- line drops out, then the leftmost sensor finds the new line ----
        pat = 5'b00000;
        #2_000_000;
        pat = 5'b10000;
        #4_000_000;
        expect_busy("line found -> idle", busy, 0);
        expect2("pid back in charge", dl, dr, 5, 5);

        // ---- same corner still there: cooldown must block it ----
        pat = 5'b11100;
        #3_000_000;
        expect_busy("cooldown blocks", busy, 0);

        // ---- after cooldown it may trigger again ----
        #8_000_000;
        expect_busy("retrigger after cooldown", busy, 1);

        // ---- finish this one, then test the right corner ----
        pat = 5'b00000;
        #4_000_000;
        pat = 5'b10000;
        #7_000_000;
        expect_busy("finish second turn", busy, 0);

        #7_000_000;                       // let cooldown expire
        pat = 5'b00111;                   // right three
        #8_000_000;
        expect2("spin right", dl, dr, 20, -20);

        // ---- timeout: never re-detect the line ----
        pat = 5'b00000;
        #32_000_000;
        expect_busy("timeout stops spin", busy, 0);

        // ---- pure timer path (dut2) ----
        pat2 = 5'b11100;
        #6_000_000;
        expect2("timer spin", d2l, d2r, -20, 20);
        pat2 = 5'b00000;                  // do not re-trigger on the same corner
        #6_000_000;
        expect_busy("timer finished", busy2, 0);
        expect2("timer back to pid", d2l, d2r, 5, 5);

        #2_000_000;
        if (errors == 0)
            $display("== tb_corner_turn PASS ==");
        else
            $display("== tb_corner_turn FAIL: %0d error(s) ==", errors);
        $finish;
    end

endmodule
