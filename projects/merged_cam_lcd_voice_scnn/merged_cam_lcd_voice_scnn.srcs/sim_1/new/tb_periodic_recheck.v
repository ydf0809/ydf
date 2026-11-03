`timescale 1ns / 1ps

module tb_periodic_recheck;
    reg clk = 0;
    always #15 clk = ~clk;
    reg rst_n = 0;
    reg timer_tracking = 0;
    wire request_toggle;
    periodic_recheck_timer #(.INTERVAL_CYCLES(10)) timer (
        .clk(clk), .rst_n(rst_n), .tracking(timer_tracking),
        .request_toggle(request_toggle)
    );
    wire default_toggle;
    periodic_recheck_timer default_timer (
        .clk(clk), .rst_n(rst_n), .tracking(1'b0),
        .request_toggle(default_toggle)
    );

    reg frame_sync = 0, roi_hold = 0, label_valid = 0, is_drone = 0;
    reg drone_count_low = 0, recheck_tick = 0, motion_valid = 0;
    wire [9:0] roi_x0;
    wire [8:0] roi_y0;
    wire tracking, verifying;
    integer errors = 0;
    integer i;
    reg saved_toggle;
    roi_scheduler dut (
        .clk(clk), .rst_n(rst_n), .frame_sync(frame_sync),
        .roi_hold(roi_hold), .label_valid(label_valid), .is_drone(is_drone),
        .drone_count_low(drone_count_low), .recheck_tick(recheck_tick),
        .motion_valid(motion_valid),
        .motion_x0(9'd80), .motion_x1(9'd99),
        .motion_y0(8'd60), .motion_y1(8'd79),
        .roi_x0(roi_x0), .roi_y0(roi_y0),
        .tracking(tracking), .verifying(verifying)
    );
    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (!condition) begin
                $display("ERROR: %0s", message);
                errors = errors + 1;
            end
        end
    endtask
    task label;
        input margin_drone;
        input [5:0] raw_drone_spikes;
        begin
            @(negedge clk);
            is_drone = margin_drone;
            drone_count_low = (raw_drone_spikes <= 10);
            label_valid = 1;
            @(negedge clk); label_valid = 0;
            @(posedge clk); #1;
        end
    endtask
    task request_check;
        begin
            @(negedge clk); recheck_tick = 1;
            @(negedge clk); recheck_tick = 0;
            @(posedge clk); #1;
        end
    endtask
    task low_check;
        begin
            request_check;
            check(tracking && verifying, "periodic check dropped lock or did not request capture");
            label(1'b0, 6'd10);
        end
    endtask
    task frame;
        begin
            @(negedge clk); frame_sync = 1;
            @(negedge clk); frame_sync = 0;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        check(default_timer.INTERVAL_CYCLES == 66666666 &&
              default_timer.LAST_COUNT == 66666665,
              "default timer is not nominally 2 seconds at 33.333333 MHz");
        timer_tracking = 1;
        repeat (9) begin @(posedge clk); #1; end
        check(request_toggle == 0, "timer requested early");
        @(posedge clk); #1;
        check(request_toggle == 1, "timer missed its exact 10-cycle interval");
        repeat (10) begin @(posedge clk); #1; end
        check(request_toggle == 0, "timer did not repeat at the configured interval");
        repeat (10) begin @(posedge clk); #1; end
        @(negedge clk); timer_tracking = 0;
        saved_toggle = request_toggle;
        repeat (25) begin @(posedge clk); #1; end
        check(request_toggle == saved_toggle, "disabling timer generated an extra request");
        @(negedge clk); timer_tracking = 1;
        repeat (9) begin @(posedge clk); #1; end
        check(request_toggle == saved_toggle, "timer failed to restart with a full interval");
        @(posedge clk); #1;
        check(request_toggle != saved_toggle, "timer failed after re-enabling");
        @(negedge clk); timer_tracking = 0;

        // Initial acquisition keeps the original margin-qualified 3-of-5 rule.
        motion_valid = 1; frame;
        label(1, 10); label(1, 10); label(0, 11); label(1, 10); label(0, 11);
        check(tracking && !verifying && roi_x0 == 116 && roi_y0 == 76,
              "failed to acquire noncentral target with original 3-of-5 rule");
        for (i=0; i<4; i=i+1) begin
            low_check;
            check(tracking && !verifying, "fewer than five low results dropped lock");
        end
        request_check;
        // Busy ticks and valid local motion must not cancel the active check.
        request_check; frame;
        check(tracking && verifying, "local motion or duplicate tick cancelled check");
        label(0, 11);
        check(tracking && !verifying && dut.low_recheck_count == 0,
              "count 11 did not clear all preceding low results");
        check(!is_drone, "count-11 test accidentally met acquisition margin");
        for (i=0; i<4; i=i+1) begin
            low_check;
            check(tracking, "low streak did not restart after count 11");
        end
        request_check; label(0, 11);
        check(tracking && dut.low_recheck_count == 0,
              "second count-11 result failed to retain lock");

        roi_hold = 1; request_check;
        check(tracking && !verifying, "busy result hold accepted a periodic request");
        roi_hold = 0;
        // No classification completion means no zero may be counted.
        request_check;
        repeat (6) frame;
        check(tracking && verifying && dut.low_recheck_count == 0,
              "frames without completed results were counted as low results");
        label(0, 0);
        for (i=0; i<3; i=i+1) low_check;
        check(tracking && dut.low_recheck_count == 4,
              "four completed low results were not retained");
        low_check;
        check(!tracking && !verifying && roi_x0 == 116 && roi_y0 == 76,
              "fifth consecutive low failed to unlock and retain last ROI");

        // The explicitly retained old loss path takes precedence over a
        // coincident periodic tick and still uses its original 3-of-5 rule.
        motion_valid=0; frame;
        motion_valid=1; frame;
        for(i=0;i<5;i=i+1) label(1,50);
        check(tracking,"setup for old-loss-path regression failed");
        motion_valid=0;
        for(i=0;i<44;i=i+1) frame;
        recheck_tick=1; frame; recheck_tick=0;
        check(tracking && verifying && dut.mode==dut.MODE_LOST_CHECK,
              "periodic tick overrode the original 45-frame lost-target check");
        // Nonzero but margin-negative results retain lock in periodic mode,
        // but the original lost-target path is deliberately unchanged.
        for(i=0;i<5;i=i+1) label(0,11);
        check(!tracking && !verifying,"old loss rule was silently replaced by the low-threshold periodic rule");

        if (errors == 0) $display("PERIODIC_RECHECK_TEST: PASS");
        else $display("PERIODIC_RECHECK_TEST: FAIL (%0d errors)", errors);
        $finish;
    end
    initial begin
        #2000000;
        $display("PERIODIC_RECHECK_TEST: FAIL (timeout)");
        $finish;
    end
endmodule
