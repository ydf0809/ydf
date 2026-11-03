`timescale 1ns / 1ps

module tb_line_pid;
    parameter CLK_FREQ = 1000000;
    localparam PERIOD_MS = 1;
    reg clk = 1'b0;
    always #500 clk = ~clk;
    integer errors = 0;

    reg rst_n, run_en, line_valid;
    reg [4:0] track_pat;
    wire signed [7:0] l, r;
    line_pid_ctrl #(
        .CLK_FREQ_HZ(CLK_FREQ), .PERIOD_MS(PERIOD_MS), .STEER_REVERSE(1'b1),
        .SPEED_BASE(8'sd16), .SPEED_MAX(8'sd20), .TURN_MAX(8'sd16),
        .CURVE_SHIFT(1), .KP_SHIFT(5), .ERR_DEADBAND(0),
        .KI_SHIFT(0), .KD_SHIFT(0), .LOST_CONFIRM(2), .SEARCH_EN(0)
    ) dut (
        .clk(clk), .rst_n(rst_n), .run_en(run_en),
        .track_pat(track_pat), .line_valid(line_valid), .left_speed(l), .right_speed(r)
    );

    reg i_run, i_valid;
    reg [4:0] i_pat;
    wire signed [7:0] il, ir;
    line_pid_ctrl #(
        .CLK_FREQ_HZ(CLK_FREQ), .PERIOD_MS(PERIOD_MS), .STEER_REVERSE(1'b1),
        .SPEED_BASE(8'sd8), .SPEED_MAX(8'sd20), .TURN_MAX(8'sd12),
        .CURVE_SHIFT(0), .KP_SHIFT(6), .ERR_DEADBAND(0),
        .KI_SHIFT(12), .KD_SHIFT(0), .LOST_CONFIRM(2), .SEARCH_EN(0)
    ) dut_i (
        .clk(clk), .rst_n(rst_n), .run_en(i_run),
        .track_pat(i_pat), .line_valid(i_valid), .left_speed(il), .right_speed(ir)
    );

    reg d_run;
    reg [4:0] d_pat;
    wire signed [7:0] dl, dr;
    reg track_dmax = 1'b0;
    integer dmax = 0;
    always @(posedge clk)
        if (track_dmax && (dl > dmax)) dmax <= dl;
    line_pid_ctrl #(
        .CLK_FREQ_HZ(CLK_FREQ), .PERIOD_MS(PERIOD_MS), .STEER_REVERSE(1'b1),
        .SPEED_BASE(8'sd8), .SPEED_MAX(8'sd20), .TURN_MAX(8'sd12),
        .CURVE_SHIFT(0), .KP_SHIFT(6), .ERR_DEADBAND(0),
        .KI_SHIFT(0), .KD_SHIFT(6), .LOST_CONFIRM(2), .SEARCH_EN(0)
    ) dut_d (
        .clk(clk), .rst_n(rst_n), .run_en(d_run),
        .track_pat(d_pat), .line_valid(1'b1), .left_speed(dl), .right_speed(dr)
    );

    reg s_run = 1'b1;
    reg s_valid = 1'b1;
    reg [4:0] s_pat = 5'b00100;
    wire signed [7:0] sl, sr;
    wire s_active;
    line_pid_ctrl #(
        .CLK_FREQ_HZ(CLK_FREQ), .PERIOD_MS(PERIOD_MS), .STEER_REVERSE(1'b1),
        .SPEED_BASE(8'sd8), .SPEED_MAX(8'sd20), .TURN_MAX(8'sd12),
        .CURVE_SHIFT(0), .KP_SHIFT(6), .ERR_DEADBAND(0),
        .KI_SHIFT(0), .KD_SHIFT(0), .LOST_CONFIRM(2), .SEARCH_EN(1),
        .SEARCH_MS(16), .SEARCH_SWING_MS(4), .SEARCH_SPEED(8'sd8)
    ) dut_s (
        .clk(clk), .rst_n(rst_n), .run_en(s_run),
        .track_pat(s_pat), .line_valid(s_valid),
        .left_speed(sl), .right_speed(sr), .active(s_active)
    );

    reg [4:0] db_pat = 5'b00100;
    wire signed [7:0] dbl, dbr;
    line_pid_ctrl #(
        .CLK_FREQ_HZ(CLK_FREQ), .PERIOD_MS(PERIOD_MS), .STEER_REVERSE(1'b1),
        .SPEED_BASE(8'sd16), .SPEED_MAX(8'sd20), .TURN_MAX(8'sd16),
        .CURVE_SHIFT(1), .KP_SHIFT(5), .ERR_DEADBAND(96),
        .KI_SHIFT(0), .KD_SHIFT(0), .LOST_CONFIRM(2), .SEARCH_EN(0)
    ) dut_db (
        .clk(clk), .rst_n(rst_n), .run_en(1'b1),
        .track_pat(db_pat), .line_valid(1'b1), .left_speed(dbl), .right_speed(dbr)
    );

    task expect2;
        input [8*46-1:0] name;
        input integer got_l, got_r;
        input integer exp_l, exp_r;
        begin
            if ((got_l !== exp_l) || (got_r !== exp_r)) begin
                $display("[FAIL] %0s : got L=%0d R=%0d, expect L=%0d R=%0d",
                         name, got_l, got_r, exp_l, exp_r);
                errors = errors + 1;
            end else
                $display("[ OK ] %0s : L=%0d R=%0d", name, got_l, got_r);
        end
    endtask

    task search_tick;
        begin
            @(posedge clk);
            while (dut_s.period_cnt != (CLK_FREQ / 1000) * PERIOD_MS - 1)
                @(posedge clk);
            #1;
        end
    endtask

    task expect_active;
        input expected;
        begin
            if (s_active !== expected) begin
                $display("[FAIL] search active=%b expected=%b", s_active, expected);
                errors = errors + 1;
            end
        end
    endtask

    task start_loss;
        input [4:0] invalid_pat;
        integer held_l, held_r;
        begin
            held_l = sl;
            held_r = sr;
            @(negedge clk);
            s_pat = invalid_pat;
            s_valid = 1'b0;
            search_tick;
            expect2("loss confirmation stops immediately", sl, sr, 0, 0);
            search_tick;
        end
    endtask

    task full_scan;
        input [8*46-1:0] name;
        integer idx;
        begin
            $display("-- %0s --", name);
            for (idx = 0; idx < 16; idx = idx + 1) begin
                if (idx != 0) search_tick;
                $display("search output index %0d", idx);
                if (idx >= 4 && idx < 12)
                    expect2(name, sl, sr, 8, -8);
                else
                    expect2(name, sl, sr, -8, 8);
                expect_active(1'b1);
                if (dut_s.search_cnt !== idx) begin
                    $display("[FAIL] search_cnt=%0d expected=%0d", dut_s.search_cnt, idx);
                    errors = errors + 1;
                end
            end
            search_tick;
            expect2("scan complete stops on next tick", sl, sr, 0, 0);
            expect_active(1'b0);
            search_tick;
            expect2("timeout stays stopped", sl, sr, 0, 0);
        end
    endtask

    task reacquire;
        input [4:0] valid_pat;
        input integer expected_l, expected_r;
        begin
            @(negedge clk);
            s_pat = valid_pat;
            s_valid = 1'b1;
            search_tick;
            expect2("reacquire on first control tick", sl, sr, expected_l, expected_r);
            expect_active(1'b1);
            if (dut_s.searching !== 1'b0 || dut_s.give_up !== 1'b0 ||
                dut_s.search_cnt !== 0 || dut_s.integ !== 0) begin
                $display("[FAIL] reacquire did not clear search/history state");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("== tb_line_pid start ==");
        rst_n = 1'b0;
        run_en = 1'b0;
        line_valid = 1'b1;
        track_pat = 5'b00100;
        i_run = 1'b0;
        i_valid = 1'b1;
        i_pat = 5'b01100;
        d_run = 1'b0;
        d_pat = 5'b00100;
        #20_000;
        rst_n = 1'b1;
        #3_000_000;
        expect2("run_en=0 stop", l, r, 0, 0);
        run_en = 1'b1;
        #3_000_000;
        expect2("center straight", l, r, 16, 16);
        track_pat = 5'b00110;
        #3_000_000;
        expect2("one step left", l, r, 10, 18);
        track_pat = 5'b01100;
        #3_000_000;
        expect2("one step right", l, r, 18, 10);
        track_pat = 5'b00011;
        #3_000_000;
        expect2("two left (centroid)", l, r, -2, 20);
        track_pat = 5'b00001;
        #3_000_000;
        expect2("far left reverses inner", l, r, -8, 20);
        track_pat = 5'b10000;
        #3_000_000;
        expect2("far right reverses inner", l, r, 20, -8);
        line_valid = 1'b0;
        #3_000_000;
        expect2("line lost stop", l, r, 0, 0);
        track_pat = 5'b00100;
        line_valid = 1'b1;
        #3_000_000;
        expect2("line reacquired", l, r, 16, 16);
        i_run = 1'b1;
        #5_000_000;
        expect2("I: p only @5ms", il, ir, 10, 6);
        #115_000_000;
        expect2("I: integral @120ms", il, ir, 13, 3);
        d_run = 1'b1;
        #5_000_000;
        expect2("D: settled", dl, dr, 8, 8);
        d_pat = 5'b01100;
        track_dmax = 1'b1;
        #3_000_000;
        track_dmax = 1'b0;
        if (dmax !== 12) begin
            $display("[FAIL] D: kick ; peak L=%0d, expect 12", dmax);
            errors = errors + 1;
        end else
            $display("[ OK ] D: kick peak L=%0d", dmax);
        expect2("D: back to P", dl, dr, 10, 6);

        start_loss(5'b00000);
        full_scan("all zero invalid: left4/right8/left4");
        reacquire(5'b00100, 8, 8);
        start_loss(5'b11111);
        full_scan("all one invalid: left4/right8/left4");
        reacquire(5'b00001, 0, 16);
        start_loss(5'b00000);
        full_scan("hard left loss: left4/right8/left4");
        reacquire(5'b10000, 16, 0);
        start_loss(5'b00000);
        full_scan("hard right loss: left4/right8/left4");
        reacquire(5'b00100, 8, 8);

        start_loss(5'b00000);
        repeat (5) search_tick;
        expect2("search right before reacquire", sl, sr, 8, -8);
        reacquire(5'b01100, 10, 6);
        start_loss(5'b11111);
        repeat (5) search_tick;
        @(negedge clk);
        s_run = 1'b0;
        @(posedge clk);
        #1;
        expect2("mode off stops immediately", sl, sr, 0, 0);
        expect_active(1'b0);
        if (dut_s.period_cnt !== 0 || dut_s.lost_cnt !== 0 ||
            dut_s.search_cnt !== 0 || dut_s.searching !== 0 ||
            dut_s.give_up !== 0 || dut_s.integ !== 0 || dut_s.err_prev !== 0) begin
            $display("[FAIL] mode off did not clear state");
            errors = errors + 1;
        end
        @(negedge clk);
        s_run = 1'b1;
        search_tick;
        expect2("restart confirms loss from zero", sl, sr, 0, 0);
        search_tick;
        full_scan("mode restart: left4/right8/left4");
        reacquire(5'b00100, 8, 8);

        s_pat = 5'b11111;
        s_valid = 1'b1;
        search_tick;
        expect2("all-one remains stopped", sl, sr, 0, 0);
        s_pat = 5'b00000;
        search_tick;
        expect2("all-zero enters search after confirmation", sl, sr, -8, 8);

        db_pat = 5'b00110;
        #3_000_000;
        expect2("deadband half pitch", dbl, dbr, 15, 17);
        db_pat = 5'b00010;
        #3_000_000;
        expect2("deadband one pitch", dbl, dbr, 9, 19);
        #2_000_000;
        if (errors == 0)
            $display("== tb_line_pid PASS ==");
        else
            $display("== tb_line_pid FAIL: %0d error(s) ==", errors);
        $finish;
    end
endmodule
