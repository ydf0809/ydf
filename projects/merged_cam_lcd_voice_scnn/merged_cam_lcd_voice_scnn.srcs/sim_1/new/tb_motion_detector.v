`timescale 1ns / 1ps

module tb_motion_detector;
    reg clk;
    reg rst_n;
    reg frame_sync;
    reg pix_we;
    reg [8:0] pix_x;
    reg [7:0] pix_y;
    reg [15:0] pix_rgb565;
    reg track_enable;
    reg [9:0] track_x0;
    reg [8:0] track_y0;

    wire box_valid;
    wire track_found;
    wire [8:0] box_x0, box_x1;
    wire [7:0] box_y0, box_y1;
    wire [13:0] motion_count;
    wire [6:0] dbg_best;
    wire [15:0] dbg_total;

    integer x, y, errors;
    integer obj_x, obj_y, obj_on;
    integer white_x, white_y, white_on;
    integer dark2_x, dark2_y, dark2_on;
    integer bg_luma;
    integer box_cx, box_cy;
    integer locked_cx, locked_cy;
    integer frame_index;

    always #15 clk = ~clk;

    motion_detector dut (
        .clk(clk),
        .rst_n(rst_n),
        .frame_sync(frame_sync),
        .pix_we(pix_we),
        .pix_x(pix_x),
        .pix_y(pix_y),
        .pix_rgb565(pix_rgb565),
        .track_enable(track_enable),
        .track_x0(track_x0),
        .track_y0(track_y0),
        .box_valid(box_valid),
        .track_found(track_found),
        .box_x0(box_x0),
        .box_x1(box_x1),
        .box_y0(box_y0),
        .box_y1(box_y1),
        .motion_count(motion_count),
        .dbg_best(dbg_best),
        .dbg_total(dbg_total)
    );

    function [15:0] gray565(input [7:0] v);
        gray565 = {v[7:3], v[7:2], v[7:3]};
    endfunction

    task drive_frame;
        begin
            for (y = 0; y < 200; y = y + 1) begin
                for (x = 0; x < 300; x = x + 1) begin
                    pix_rgb565 = gray565(bg_luma[7:0]);
                    if (obj_on && (x >= obj_x) && (x < obj_x + 20) &&
                        (y >= obj_y) && (y < obj_y + 20))
                        pix_rgb565 = 16'h0000; // dark moving candidate
                    if (white_on && (x >= white_x) && (x < white_x + 20) &&
                        (y >= white_y) && (y < white_y + 20))
                        pix_rgb565 = 16'hFFFF; // bright moving distractor
                    if (dark2_on && (x >= dark2_x) && (x < dark2_x + 8) &&
                        (y >= dark2_y) && (y < dark2_y + 8))
                        pix_rgb565 = 16'h0000; // isolated dark background patch
                    pix_we = 1'b1;
                    pix_x = x[8:0];
                    pix_y = y[7:0];
                    @(posedge clk);
                end
            end
            pix_we = 1'b0;
            repeat (3) @(posedge clk);
            frame_sync = 1'b1;
            @(posedge clk);
            frame_sync = 1'b0;
            repeat (5300) @(posedge clk);
        end
    endtask

    task do_reset;
        begin
            rst_n = 0;
            repeat (4) @(posedge clk);
            rst_n = 1;
            repeat (2) @(posedge clk);
        end
    endtask

    task check_box_near;
        input [8*20-1:0] tag;
        input integer ex, ey;
        begin
            box_cx = (box_x0 + box_x1 + 1) / 2;
            box_cy = (box_y0 + box_y1 + 1) / 2;
            $display("MOTION %0s valid=%b centre=(%0d,%0d) box=x%0d..%0d y%0d..%0d best=%0d total=%0d",
                     tag, box_valid, box_cx, box_cy,
                     box_x0, box_x1, box_y0, box_y1, dbg_best, dbg_total);
            $display("MOTION_DBG weight=%0d sumx=%0d sumy=%0d qx=%0d qy=%0d",
                     dut.weight_acc, dut.weighted_x_sum, dut.weighted_y_sum,
                     dut.div_quot_x[6:0], dut.div_quot_y[6:0]);
            if (!box_valid || (box_cx < ex - 6) || (box_cx > ex + 6) ||
                (box_cy < ey - 6) || (box_cy > ey + 6)) begin
                $display("ERROR: %0s box centre mismatch", tag);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        frame_sync = 0;
        pix_we = 0;
        pix_x = 0;
        pix_y = 0;
        pix_rgb565 = 0;
        track_enable = 0;
        track_x0 = 0;
        track_y0 = 0;
        errors = 0;
        bg_luma = 40;
        obj_on = 1;
        obj_x = 20;
        obj_y = 20;
        white_on = 0;
        white_x = 0;
        white_y = 0;
        dark2_on = 0;
        dark2_x = 0;
        dark2_y = 0;

        do_reset;

        pix_rgb565 = 16'h07e0;
        #1;
        if (dut.luma != 8'd159) begin
            $display("ERROR: green luminance=%0d expected=159", dut.luma);
            errors = errors + 1;
        end
        pix_rgb565 = 16'hffff;
        #1;
        if (dut.luma != 8'd255) begin
            $display("ERROR: white luminance=%0d expected=255", dut.luma);
            errors = errors + 1;
        end
        pix_rgb565 = 16'd0;

        pix_x = 9'd299;
        pix_y = 8'd199;
        #1;
        if (dut.frame_wr_addr != 17'd59999 ||
            dut.frame_rd_addr != 17'd119999) begin
            $display("ERROR: first-bank tail addresses=%0d/%0d",
                     dut.frame_wr_addr, dut.frame_rd_addr);
            errors = errors + 1;
        end
        pix_x = 9'd0;
        pix_y = 8'd0;

        // First frame is the reference.
        drive_frame;
        pix_x = 9'd299;
        pix_y = 8'd199;
        #1;
        if (dut.frame_wr_addr != 17'd119999 ||
            dut.frame_rd_addr != 17'd59999) begin
            $display("ERROR: second-bank tail addresses=%0d/%0d",
                     dut.frame_wr_addr, dut.frame_rd_addr);
            errors = errors + 1;
        end
        pix_x = 9'd0;
        pix_y = 8'd0;
        if (box_valid) begin
            $display("ERROR: first reference frame produced a box");
            errors = errors + 1;
        end

        // AEC brightness step: the first step is a one-frame full-screen
        // candidate, and the next frame validates compensation.
        bg_luma = 90;
        drive_frame;
        $display("MOTION_DBG aec1 valid=%b best=%0d total=%0d found=%b prev_cand=%b mean=%0d haves=%b sums=%0d/%0d",
                 box_valid, dbg_best, dbg_total, dut.found, dut.prev_cand,
                 dut.mean_shift, dut.have_prev, dut.sum_cur, dut.sum_last);
        drive_frame;
        $display("MOTION_DBG aec2 valid=%b best=%0d total=%0d found=%b prev_cand=%b mean=%0d haves=%b sums=%0d/%0d",
                 box_valid, dbg_best, dbg_total, dut.found, dut.prev_cand,
                 dut.mean_shift, dut.have_prev, dut.sum_cur, dut.sum_last);
        if (box_valid) begin
            $display("ERROR: AEC brightness step produced a box");
            errors = errors + 1;
        end

        // First displacement only arms a candidate.
        obj_x = 40;
        drive_frame;
        $display("MOTION_DBG move1 valid=%b best=%0d total=%0d found=%b prev_cand=%b",
                 box_valid, dbg_best, dbg_total, dut.found, dut.prev_cand);
        if (box_valid) begin
            $display("ERROR: one-frame candidate placed a box");
            errors = errors + 1;
        end

        // Second consecutive displacement confirms the dark moving block.
        obj_x = 60;
        drive_frame;
        check_box_near("dark-motion", 60, 30);

        // The held box may persist briefly after the object becomes static.
        drive_frame;
        if (!box_valid) begin
            $display("ERROR: tracking hold did not retain the box");
            errors = errors + 1;
        end
        repeat (31) drive_frame;
        if (box_valid) begin
            $display("ERROR: held box did not expire");
            errors = errors + 1;
        end

        // Move a dark and a bright block in parallel.  The dark block has a
        // two-vote confidence weight and must define the selected cluster.
        obj_x = 100;
        obj_y = 100;
        white_on = 1;
        white_x = 230;
        white_y = 140;
        drive_frame;
        obj_x = 120;
        obj_y = 120;
        white_x = 250;
        white_y = 160;
        drive_frame;
        if (box_valid) begin
            $display("ERROR: one far-away jump was accepted as a new target");
            errors = errors + 1;
        end
        obj_x = 140;
        obj_y = 140;
        white_x = 270;
        white_y = 180;
        drive_frame;
        check_box_near("dark-over-bright", 140, 140);

        // Pixel-stream integration: a stronger patch flickers at one fixed
        // location while a weaker 8x8 target travels across the image.
        // Mature coherent motion must eventually win the global candidate.
        do_reset;
        track_enable = 0;
        bg_luma = 120;
        obj_x = 20; obj_y = 20; obj_on = 1;
        white_on = 0;
        dark2_on = 1; dark2_x = 140; dark2_y = 120;
        drive_frame;
        for (frame_index=0; frame_index<12; frame_index=frame_index+1) begin
            obj_on = frame_index % 2;
            dark2_x = 140 + frame_index*5;
            drive_frame;
        end
        box_cx = (box_x0 + box_x1 + 1)/2;
        box_cy = (box_y0 + box_y1 + 1)/2;
        if (!box_valid || !dut.ranked_moving || box_cx < 170 || box_cy < 100) begin
            $display("ERROR: fixed strong flicker beat weaker coherent travel x=%0d y=%0d preferred=%b primary=%0d,%0d secondary=%0d,%0d",
                     box_cx, box_cy, dut.ranked_moving, dut.primary_cx, dut.primary_cy,
                     dut.secondary_cx, dut.secondary_cy);
            errors=errors+1;
        end

        // Locked tracking uses a dense central dark patch.  A sparse dark
        // distractor in another ROI cell must not pull the box away.
        do_reset;
        track_enable = 1;
        track_x0 = 10'd200;
        track_y0 = 9'd160;
        obj_on = 1;
        obj_x = 124;
        obj_y = 104;
        dark2_on = 0;
        drive_frame;
        if (track_found) begin
            $display("ERROR: lock became valid before collecting a full frame");
            errors = errors + 1;
        end
        drive_frame;
        if (!track_found) begin
            $display("ERROR: dense locked target was not found");
            errors = errors + 1;
        end
        check_box_near("locked-dark-patch", 134, 114);
        locked_cx = (box_x0 + box_x1 + 1) / 2;
        locked_cy = (box_y0 + box_y1 + 1) / 2;

        // An equally dark background patch must not steal an established
        // target simply because its grid cell is scanned first.
        dark2_on = 1;
        dark2_x = 108;
        dark2_y = 88;
        drive_frame;
        box_cx = (box_x0 + box_x1 + 1) / 2;
        box_cy = (box_y0 + box_y1 + 1) / 2;
        if (!track_found || (box_cx < locked_cx - 8) ||
            (box_cx > locked_cx + 8) || (box_cy < locked_cy - 8) ||
            (box_cy > locked_cy + 8)) begin
            $display("ERROR: nearby dark background stole locked target");
            errors = errors + 1;
        end

        dark2_on = 0;
        obj_x = 140;
        obj_y = 108;
        drive_frame;
        box_cx = (box_x0 + box_x1 + 1) / 2;
        box_cy = (box_y0 + box_y1 + 1) / 2;
        if (!track_found || (box_cx < locked_cx + 5) ||
            (box_cx > locked_cx + 16) || (box_cy < locked_cy - 16) ||
            (box_cy > locked_cy + 16)) begin
            $display("ERROR: accelerated target was not followed within the 16-pixel limit x=%0d from=%0d",
                     box_cx, locked_cx);
            errors = errors + 1;
        end

        obj_on = 0;
        dark2_on = 0;
        drive_frame;
        if (track_found) begin
            $display("ERROR: locked target remained valid after a blank frame");
            errors = errors + 1;
        end

        // ROI y0 may be 272 in a 400-pixel picture.  The tracking input must
        // preserve the ninth bit or it will inspect the wrong rows.
        do_reset;
        dark2_on = 0;
        obj_on = 1;
        obj_x = 124;
        obj_y = 156;
        track_enable = 1;
        track_x0 = 10'd200;
        track_y0 = 9'd272;
        drive_frame;
        drive_frame;
        if (!track_found) begin
            $display("ERROR: target near bottom of preview was not tracked");
            errors = errors + 1;
        end
        track_enable = 0;
        drive_frame;
        if (box_valid) begin
            $display("ERROR: old TRACK box persisted into SEARCH state=%0d prev=%b best=%0d total=%0d",
                     dut.state, dut.prev_cand, dbg_best, dbg_total);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TEST_RESULT: PASS");
        else
            $display("TEST_RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #300_000_000;
        $display("TEST_RESULT: FAIL (timeout)");
        $finish;
    end
endmodule
