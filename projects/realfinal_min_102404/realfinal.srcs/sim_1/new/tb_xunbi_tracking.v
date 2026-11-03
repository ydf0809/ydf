`timescale 1ns / 1ps

module tb_xunbi_tracking;
    reg clk = 1'b0;
    always #15 clk = ~clk;
    reg rst_n = 1'b0;
    reg run_en = 1'b0;
    reg [4:0] pat = 5'b00100;
    wire signed [7:0] m1, m2, m3, m4;
    wire cmd_update;
    integer errors = 0;
    integer stop_sent;
    localparam integer MS_CYCLES = 33333;
    localparam integer FORWARD_NS = MS_CYCLES * 1000 * 30;
    time fwd_start;

    xunbi_core dut (
        .sys_clk(clk), .rst_n(rst_n), .run_en(run_en),
        .track_l2(pat[4]), .track_l1(pat[3]), .track_m(pat[2]),
        .track_r1(pat[1]), .track_r2(pat[0]),
        .us_trig(), .us_echo(1'b0),
        .out_m1(m1), .out_m2(m2), .out_m3(m3), .out_m4(m4),
        .cmd_update(cmd_update)
    );

    task check;
        input condition;
        input [8*96-1:0] label;
        begin
            if (condition !== 1'b1) begin
                $display("[FAIL] %0s @ %0t: motors %0d/%0d/%0d/%0d", label, $time, m1, m2, m3, m4);
                errors = errors + 1;
            end else $display("[ OK ] %0s", label);
        end
    endtask

    task wait_ms;
        input integer ms;
        begin
            repeat (MS_CYCLES * ms) @(posedge clk);
            #1;
        end
    endtask

    task invalid_then_search;
        input [4:0] invalid_pat;
        integer k;
        begin
            @(negedge clk);
            pat = invalid_pat;
            stop_sent = 0;
            for (k = 0; k < 3; k = k + 1) begin
                @(posedge clk); #1;
                if (cmd_update && m1 == 0 && m2 == 0 && m3 == 0 && m4 == 0)
                    stop_sent = 1;
            end
            check(m1 == 0 && m2 == 0 && m3 == 0 && m4 == 0,
                  "invalid input clears all motor commands within three clocks");
            check(stop_sent == 1, "invalid input issues a stop update without waiting 10ms");
            wait_ms(35);
            check(m1 == -16 && m2 == 16 && m3 == -16 && m4 == 16,
                  "confirmed loss preserves original left search");
            check(dut.corner_busy == 0, "all-on/all-off cannot start a corner");
            @(negedge clk); pat = 5'b00100;
            wait_ms(30);
            check(m1 == 18 && m2 == -18 && m3 == -18 && m4 == 18,
                  "valid center line restores forward PID");
        end
    endtask

    task corner_1000ms;
        input [4:0] corner_pat;
        input left_turn;
        begin
            @(negedge clk); pat = corner_pat;
            @(posedge dut.corner_busy);
            fwd_start = $time;
            #1;
            check(dut.corner_left_speed == 16 && dut.corner_right_speed == 16,
                  "confirmed corner starts straight forward phase");

            pat = 5'b11111;
            wait_ms(12);
            check(m1 == 16 && m2 == -16 && m3 == -16 && m4 == 16,
                  "confirmed corner sends straight motion to all four motors");
            repeat (MS_CYCLES * (1000 - 12) - 1) @(posedge clk);
            #1;
            check(dut.corner_left_speed == 16 && dut.corner_right_speed == 16,
                  "still straight one clock before 1000ms boundary");
            check(m1 == 16 && m2 == -16 && m3 == -16 && m4 == 16,
                  "all four motors remain straight until the 1000ms boundary");
            @(dut.u_corner_turn.state);
            check(($time - fwd_start) == FORWARD_NS,
                  "turn begins after exactly 1000 millisecond ticks");
            #1;
            if (left_turn)
                check(dut.corner_left_speed == -20 && dut.corner_right_speed == 20,
                      "left corner spins in correct direction");
            else
                check(dut.corner_left_speed == 20 && dut.corner_right_speed == -20,
                      "right corner spins in correct direction");
            wait_ms(12);
            if (left_turn)
                check(m1 == -20 && m2 == 20 && m3 == -20 && m4 == 20,
                      "left spin reaches four motor outputs");
            else
                check(m1 == 20 && m2 == -20 && m3 == 20 && m4 == -20,
                      "right spin reaches four motor outputs");
            @(negedge clk); run_en = 0;
            wait_ms(12);
            check(m1 == 0 && m2 == 0 && m3 == 0 && m4 == 0,
                  "mode exit cancels corner and stops motors");
            @(negedge clk); pat = 5'b00100; run_en = 1;
            wait_ms(30);
        end
    endtask

    initial begin
        $display("== tb_xunbi_tracking start ==");
        #100; rst_n = 1;
        @(negedge clk); run_en = 1;
        wait_ms(220);
        check(m1 == 18 && m2 == -18 && m3 == -18 && m4 == 18,
              "production startup reaches centered forward command");
        invalid_then_search(5'b11111);
        invalid_then_search(5'b00000);
        corner_1000ms(5'b00111, 1'b1);
        corner_1000ms(5'b11100, 1'b0);
        if (errors == 0) $display("== tb_xunbi_tracking PASS ==");
        else $display("== tb_xunbi_tracking FAIL: %0d error(s) ==", errors);
        $finish;
    end
    initial begin
        #(64'd5_000_000_000);
        $display("[FAIL] tb_xunbi_tracking watchdog timeout");
        $finish;
    end
endmodule
