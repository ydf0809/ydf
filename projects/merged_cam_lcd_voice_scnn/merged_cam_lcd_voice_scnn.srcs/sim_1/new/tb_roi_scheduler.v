`timescale 1ns / 1ps

module tb_roi_scheduler;
    reg clk, rst_n;
    reg frame_sync, roi_hold, label_valid, is_drone;
    reg drone_count_low, recheck_tick;
    reg motion_valid;
    reg [8:0] motion_x0, motion_x1;
    reg [7:0] motion_y0, motion_y1;

    wire [9:0] roi_x0;
    wire [8:0] roi_y0;
    wire tracking, verifying;

    integer i, errors;
    always #15 clk = ~clk;

    roi_scheduler dut (
        .clk(clk),
        .rst_n(rst_n),
        .frame_sync(frame_sync),
        .roi_hold(roi_hold),
        .label_valid(label_valid),
        .is_drone(is_drone),
        .drone_count_low(drone_count_low),
        .recheck_tick(recheck_tick),
        .motion_valid(motion_valid),
        .motion_x0(motion_x0),
        .motion_x1(motion_x1),
        .motion_y0(motion_y0),
        .motion_y1(motion_y1),
        .roi_x0(roi_x0),
        .roi_y0(roi_y0),
        .tracking(tracking),
        .verifying(verifying)
    );

    task pulse_frame;
        begin
            @(negedge clk);
            frame_sync = 1'b1;
            @(negedge clk);
            frame_sync = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task pulse_label;
        input drone;
        begin
            @(negedge clk);
            is_drone = drone;
            label_valid = 1'b1;
            @(negedge clk);
            label_valid = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task pulse_three_of_five;
        input integer positives_first;
        begin
            if (positives_first != 0) begin
                pulse_label(1'b1);
                pulse_label(1'b1);
                pulse_label(1'b0);
                pulse_label(1'b1);
                pulse_label(1'b0);
            end else begin
                pulse_label(1'b1);
                pulse_label(1'b0);
                pulse_label(1'b1);
                pulse_label(1'b0);
                pulse_label(1'b0);
            end
        end
    endtask

    task set_motion;
        input [8:0] x0, x1;
        input [7:0] y0, y1;
        begin
            motion_x0 = x0;
            motion_x1 = x1;
            motion_y0 = y0;
            motion_y1 = y1;
            motion_valid = 1'b1;
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        frame_sync = 0;
        roi_hold = 0;
        label_valid = 0;
        is_drone = 0;
        drone_count_low = 0;
        recheck_tick = 0;
        motion_valid = 0;
        motion_x0 = 0;
        motion_x1 = 0;
        motion_y0 = 0;
        motion_y1 = 0;
        errors = 0;

        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        if (tracking || verifying || roi_x0 != 236 || roi_y0 != 136) begin
            $display("ERROR: bad initial SEARCH ROI");
            errors = errors + 1;
        end

        // Three positive results in a five-result window enter TRACK.
        pulse_label(1'b1);
        if (tracking || verifying) begin
            $display("ERROR: incomplete SEARCH history entered TRACK");
            errors = errors + 1;
        end
        pulse_label(1'b1);
        pulse_label(1'b0);
        pulse_label(1'b1);
        pulse_label(1'b0);
        if (!tracking || roi_x0 != 236 || roi_y0 != 136) begin
            $display("ERROR: 3-of-5 SEARCH results did not enter TRACK");
            errors = errors + 1;
        end

        // Brief misses retain lock.  After 45 misses, the last ROI is checked
        // again by the network before SEARCH can resume.
        motion_valid = 1'b0;
        for (i = 0; i < 44; i = i + 1) pulse_frame;
        if (!tracking || roi_x0 != 236 || roi_y0 != 136) begin
            $display("ERROR: brief loss unexpectedly dropped TRACK");
            errors = errors + 1;
        end
        pulse_frame;
        if (!tracking || !verifying || roi_x0 != 236 || roi_y0 != 136) begin
            $display("ERROR: 45 no-motion misses did not start recheck");
            errors = errors + 1;
        end
        pulse_three_of_five(1);
        if (!tracking || verifying) begin
            $display("ERROR: positive recheck did not retain TRACK");
            errors = errors + 1;
        end
        for (i = 0; i < 45; i = i + 1) pulse_frame;
        pulse_three_of_five(0);
        if (tracking || verifying || roi_x0 != 236 || roi_y0 != 136) begin
            $display("ERROR: negative recheck did not return to SEARCH");
            errors = errors + 1;
        end

        pulse_frame; // clear the old TRACK candidate before re-arming SEARCH
        set_motion(9'd80, 9'd99, 8'd60, 8'd79);
        pulse_frame;
        if (tracking || !verifying || roi_x0 != 116 || roi_y0 != 76) begin
            $display("ERROR: motion did not enter VERIFY x=%0d y=%0d", roi_x0, roi_y0);
            errors = errors + 1;
        end
        pulse_label(1'b1);
        if (!verifying || tracking) begin
            $display("ERROR: incomplete VERIFY history entered TRACK");
            errors = errors + 1;
        end
        pulse_label(1'b1);
        pulse_label(1'b0);
        pulse_label(1'b1);
        pulse_label(1'b0);
        if (!tracking || verifying || roi_x0 != 116 || roi_y0 != 76) begin
            $display("ERROR: 3-of-5 VERIFY results did not enter TRACK");
            errors = errors + 1;
        end

        // A local motion update follows immediately.
        set_motion(9'd85, 9'd104, 8'd60, 8'd79);
        roi_hold = 1'b1;
        pulse_frame;
        if (!tracking || roi_x0 != 116 || roi_y0 != 76) begin
            $display("ERROR: ROI moved while its classification was pending");
            errors = errors + 1;
        end
        pulse_label(1'b0);
        if (!tracking || roi_x0 != 116 || roi_y0 != 76) begin
            $display("ERROR: pending result changed the held ROI");
            errors = errors + 1;
        end
        roi_hold = 1'b0;
        pulse_frame;
        if (!tracking || roi_x0 != 126 || roi_y0 != 76) begin
            $display("ERROR: local TRACK update failed x=%0d y=%0d", roi_x0, roi_y0);
            errors = errors + 1;
        end

        // A single remote candidate must not move the red ROI.
        set_motion(9'd220, 9'd239, 8'd150, 8'd169);
        pulse_frame;
        if (!tracking || roi_x0 != 126 || roi_y0 != 76) begin
            $display("ERROR: one remote motion moved the ROI");
            errors = errors + 1;
        end
        pulse_frame;
        if (!tracking || roi_x0 != 126 || roi_y0 != 76) begin
            $display("ERROR: two remote motion frames moved the ROI");
            errors = errors + 1;
        end
        pulse_frame;
        if (tracking || !verifying || roi_x0 != 396 || roi_y0 != 256) begin
            $display("ERROR: third remote frame did not enter REACQUIRE");
            errors = errors + 1;
        end

        // Failed remote verification (only two positives) restores the old ROI.
        pulse_three_of_five(0);
        if (!tracking || verifying || roi_x0 != 126 || roi_y0 != 76) begin
            $display("ERROR: failed REACQUIRE did not restore previous ROI");
            errors = errors + 1;
        end

        // A persistent remote candidate that passes 3-of-5 classifications may
        // replace the old target.
        pulse_frame;
        pulse_frame;
        pulse_frame;
        if (!verifying) begin
            $display("ERROR: persistent remote candidate did not re-enter VERIFY");
            errors = errors + 1;
        end
        pulse_three_of_five(1);
        if (!tracking || roi_x0 != 396 || roi_y0 != 256) begin
            $display("ERROR: verified remote candidate did not become new TRACK");
            errors = errors + 1;
        end

        // Classification flicker while motion exists cannot end TRACK.
        for (i = 0; i < 20; i = i + 1)
            pulse_label(1'b0);
        if (!tracking) begin
            $display("ERROR: motion-present classification flicker dropped TRACK");
            errors = errors + 1;
        end

        // At a noncentral ROI, the same recheck keeps the previous coordinates
        // while the classifier decides whether the target was truly lost.
        motion_valid = 1'b0;
        for (i = 0; i < 44; i = i + 1) pulse_frame;
        if (!tracking) begin
            $display("ERROR: TRACK dropped before 45 no-motion misses");
            errors = errors + 1;
        end
        pulse_frame;
        if (!tracking || !verifying || roi_x0 != 396 || roi_y0 != 256) begin
            $display("ERROR: 45th miss did not recheck at the last ROI");
            errors = errors + 1;
        end
        pulse_three_of_five(0);
        if (tracking || verifying || roi_x0 != 396 || roi_y0 != 256) begin
            $display("ERROR: negative recheck did not preserve last SEARCH ROI");
            errors = errors + 1;
        end

        for (i = 0; i < 4; i = i + 1) pulse_frame;
        if (tracking || verifying || roi_x0 != 396 || roi_y0 != 256) begin
            $display("ERROR: idle global SEARCH recentered the last tracked ROI");
            errors = errors + 1;
        end
        // VERIFY is abandoned when its motion candidate disappears.
        set_motion(9'd80, 9'd99, 8'd60, 8'd79);
        pulse_frame;
        pulse_label(1'b1);
        motion_valid = 1'b0;
        pulse_frame;
        if (tracking || verifying || roi_x0 != 116 || roi_y0 != 76) begin
            $display("ERROR: lost VERIFY candidate did not preserve SEARCH position");
            errors = errors + 1;
        end

        for (i = 0; i < 4; i = i + 1) pulse_frame;
        if (tracking || verifying || roi_x0 != 116 || roi_y0 != 76) begin
            $display("ERROR: idle global SEARCH recentered the last candidate ROI");
            errors = errors + 1;
        end

        // A result for the old crop must arrive before VERIFY can switch to
        // a new motion candidate.
        set_motion(9'd80, 9'd99, 8'd60, 8'd79);
        pulse_frame;
        if (!verifying || roi_x0 != 116 || roi_y0 != 76) begin
            $display("ERROR: setup for held VERIFY failed");
            errors = errors + 1;
        end
        roi_hold = 1'b1;
        set_motion(9'd220, 9'd239, 8'd150, 8'd169);
        pulse_frame;
        pulse_label(1'b1);
        if (!verifying || tracking || roi_x0 != 116 || roi_y0 != 76) begin
            $display("ERROR: held VERIFY attributed a result to a new ROI");
            errors = errors + 1;
        end
        roi_hold = 1'b0;
        pulse_frame;
        if (!verifying || roi_x0 != 396 || roi_y0 != 256) begin
            $display("ERROR: VERIFY did not resume after the result");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("ROI_TEST: PASS (local sticky follow)");
        else
            $display("ROI_TEST: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("ROI_TEST: FAIL (timeout)");
        $finish;
    end
endmodule
