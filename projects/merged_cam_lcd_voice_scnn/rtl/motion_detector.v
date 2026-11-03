`timescale 1ns / 1ps

// Frame-difference detector with dark-pixel confidence weighting.
//
// Input is a 300x200 luminance map sampled every two source pixels.  Motion is
// measured against the previous frame after compensating the global brightness
// change caused by camera AEC/AWB.  "Dark" does not gate motion: it doubles the
// vote of a moving sample, so a bright or partially reflective drone can still
// produce a candidate.
//
// A 5x5-cell block vote rejects isolated noise.  The strongest block defines a
// local cluster; the centre of that cluster is the weighted centroid of every
// qualifying cell, followed by a small dead-band and 1/4-rate IIR smoothing.
module motion_detector #(
    parameter integer W = 300,
    parameter integer H = 200,
    parameter integer BLK = 10,
    parameter [7:0] PIXEL_THRESHOLD = 8'd20,
    parameter [6:0] BLOCK_MIN = 7'd4,
    parameter [7:0] DARK_THRESHOLD = 8'd80,
    parameter integer GLOBAL_MOTION_LIMIT = 20000,
    parameter integer HOLD_FRAMES = 30,
    parameter integer CLUSTER_RADIUS = 4,
    parameter integer JUMP_DISTANCE = 32,
    parameter integer CENTER_DEADBAND = 2
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_sync,
    input  wire        pix_we,
    input  wire [8:0]  pix_x,
    input  wire [7:0]  pix_y,
    input  wire [15:0] pix_rgb565,
    input  wire        track_enable,
    input  wire [9:0]  track_x0,
    input  wire [8:0]  track_y0,

    output reg         box_valid,
    output reg         track_found,
    output reg  [8:0]  box_x0,
    output reg  [8:0]  box_x1,
    output reg  [7:0]  box_y0,
    output reg  [7:0]  box_y1,
    output reg  [13:0] motion_count,
    output reg  [6:0]  dbg_best,
    output reg  [15:0] dbg_total
);
    localparam integer SAMPLES = W * H;       // 60000
    localparam integer NBX = W / BLK;         // 60
    localparam integer NBY = H / BLK;         // 40
    localparam integer NB  = NBX * NBY;       // 2400
    localparam integer BOX_HALF = 32;         // 64 samples = 128 display px

    localparam [3:0] ST_IDLE     = 4'd0;
    localparam [3:0] ST_PASS1    = 4'd1;
    localparam [3:0] ST_PASS2    = 4'd2;
    localparam [3:0] ST_DIV_PREP = 4'd3;
    localparam [3:0] ST_DIVIDE   = 4'd4;
    localparam [3:0] ST_FINISH   = 4'd5;
    localparam [3:0] ST_SECOND_SEED = 4'd6;
    localparam [3:0] ST_DIV_DONE = 4'd7;
    localparam [3:0] ST_RANK = 4'd8;

    reg [7:0] frame_mem [0:2*SAMPLES-1];
    reg       write_bank;
    reg [7:0] prev_q;

    reg       pipe_valid;
    reg [8:0] pipe_x;
    reg [7:0] pipe_y;
    reg [7:0] pipe_luma;

    reg       prev_hit;
    reg [8:0] prev_hit_x;
    reg [7:0] prev_hit_y;

    // The pass-2 scan also clears these counters for the next frame.
    reg [6:0] blk_count [0:NB-1];
    reg [15:0] motion_total;

    reg [23:0] sum_cur;
    reg [23:0] sum_last;
    reg signed [8:0] mean_shift;

    reg        have_prev;
    reg        prev_cand;
    reg [8:0]  prev_cand_x;
    reg [7:0]  prev_cand_y;
    reg [5:0]  hold_count;

    reg [3:0]  state;
    reg [11:0] scan_idx;
    reg [5:0]  scan_col;
    reg [5:0]  scan_row;
    reg [6:0]  best_cnt;
    reg [5:0]  best_col;
    reg [5:0]  best_row;
    reg        found;
    reg [6:0] second_best_cnt;
    reg [5:0] second_best_col, second_best_row;
    reg second_found;
    reg [13:0] second_weight_acc;
    reg [22:0] second_x_sum;
    reg [19:0] second_y_sum;
    reg div_second;
    reg [8:0] primary_cx, secondary_cx;
    reg [7:0] primary_cy, secondary_cy;

    reg [13:0] weight_acc;
    reg [22:0] weighted_x_sum;
    reg [19:0] weighted_y_sum;
    reg [13:0] div_den;
    reg [22:0] div_num_x;
    reg [22:0] div_num_y;
    reg [14:0] rem_x;
    reg [14:0] rem_y;
    reg [22:0] div_quot_x;
    reg [22:0] div_quot_y;
    reg [4:0]  div_count;

    reg [8:0] smooth_cx;
    reg [7:0] smooth_cy;
    reg       center_valid;

    reg       track_enable_lat;
    reg [8:0] track_x0_lat;
    reg [7:0] track_y0_lat;
    // A 6x6 search area leaves an 8-sample guard at each ROI edge.  The old
    // 4x4 centre-only search could lose an accelerating target before the ROI
    // had time to catch up.
    reg [6:0] dark_bin_count [0:35];
    reg [5:0] dark_bin_min_x [0:35];
    reg [5:0] dark_bin_max_x [0:35];
    reg [5:0] dark_bin_min_y [0:35];
    reg [5:0] dark_bin_max_y [0:35];
    reg [6:0] best_dark_count;
    reg [5:0] best_dark_bin;
    reg signed [8:0] best_dark_score;

    integer k;
    reg [6:0] c;
    reg       candidate_now;
    integer cx, cy, bx, by;
    integer smooth_x, smooth_y;
    integer diff_x, diff_y;
    integer manhattan;

    wire [4:0] r5 = pix_rgb565[15:11];
    wire [5:0] g6 = pix_rgb565[10:5];
    wire [4:0] b5 = pix_rgb565[4:0];
    wire [7:0] r8 = {r5, r5[4:2]};
    wire [7:0] g8 = {g6, g6[5:4]};
    wire [7:0] b8 = {b5, b5[4:2]};
    wire [8:0] r2 = {r8, 1'b0};
    wire [9:0] g4 = {g8, 2'b00};
    wire [10:0] g5w = {1'b0, g4} + {3'b000, g8};
    wire [10:0] luma_sum = {2'b00, r2} + g5w + {3'b000, b8};
    wire [7:0] luma = luma_sum[10:3];
    wire [5:0] rel_track_x = pix_x - track_x0_lat;
    wire [5:0] rel_track_y = pix_y - track_y0_lat;
    wire [2:0] dark_bin_x = rel_track_x[5:3] - 3'd1;
    wire [2:0] dark_bin_y = rel_track_y[5:3] - 3'd1;
    wire [5:0] dark_bin_index = ({3'b000, dark_bin_y} << 2) +
                                ({3'b000, dark_bin_y} << 1) +
                                {3'b000, dark_bin_x};
    wire dark_track_hit = track_enable_lat && (luma < DARK_THRESHOLD) &&
                          (pix_x >= track_x0_lat) &&
                          (pix_x < track_x0_lat + 9'd64) &&
                          (pix_y >= track_y0_lat) &&
                          (pix_y < track_y0_lat + 8'd64) &&
                          (rel_track_x >= 6'd8) && (rel_track_x < 6'd56) &&
                          (rel_track_y >= 6'd8) && (rel_track_y < 6'd56);

    wire [8:0] track_ref_x = center_valid ? smooth_cx :
                             (track_x0_lat + 9'd32);
    wire [7:0] track_ref_y = center_valid ? smooth_cy :
                             (track_y0_lat + 8'd32);
    wire [2:0] ref_bin_x = (track_ref_x > track_x0_lat) ?
                           ((track_ref_x - track_x0_lat) >> 3) : 3'd0;
    wire [2:0] ref_bin_y = (track_ref_y > track_y0_lat) ?
                           ((track_ref_y - track_y0_lat) >> 3) : 3'd0;
    wire [2:0] current_bin_x = dark_bin_x + 3'd1;
    wire [2:0] current_bin_y = dark_bin_y + 3'd1;
    wire [3:0] dark_distance = ((current_bin_x > ref_bin_x) ?
                               (current_bin_x - ref_bin_x) :
                               (ref_bin_x - current_bin_x)) +
                               ((current_bin_y > ref_bin_y) ?
                               (current_bin_y - ref_bin_y) :
                               (ref_bin_y - current_bin_y));
    wire [6:0] dark_next_count = dark_bin_count[dark_bin_index] + 1'b1;
    wire signed [8:0] dark_score =
        $signed({2'b00, dark_next_count}) -
        $signed({4'b0000, dark_distance, 1'b0});
    wire [15:0] addr = pix_y * W + pix_x;
    wire [16:0] banked_addr = SAMPLES + {1'b0, addr};
    wire [16:0] frame_wr_addr = write_bank ? banked_addr : {1'b0, addr};
    wire [16:0] frame_rd_addr = write_bank ? {1'b0, addr} : banked_addr;

    // Divide the 60000-pixel frame sum by 65536; this underestimates the
    // average brightness change by about 8.4%.
    wire signed [24:0] sum_diff = {1'b0, sum_cur} - {1'b0, sum_last};
    wire signed [8:0] delta = {1'b0, pipe_luma} - {1'b0, prev_q};
    wire signed [9:0] corr = {delta[8], delta} - {mean_shift[8], mean_shift};
    wire [9:0] mag = corr[9] ? (~corr + 1'b1) : corr;
    wire hit = (mag > {2'b00, PIXEL_THRESHOLD});
    wire pair_hit = hit && prev_hit && (prev_hit_y == pipe_y) &&
                    (prev_hit_x + 9'd1 == pipe_x);
    wire dark_motion = (pipe_luma < DARK_THRESHOLD);
    wire [6:0] pair_weight = dark_motion ? 7'd2 : 7'd1;

    wire [5:0] blk_col = pipe_x / BLK;
    wire [5:0] blk_row = pipe_y / BLK;
    wire [11:0] blk_idx = blk_row * NBX + blk_col;
    wire [6:0] blk_thresh = ((best_cnt >> 1) > BLOCK_MIN) ?
                            (best_cnt >> 1) : BLOCK_MIN;

    wire [5:0] col_delta = (scan_col > best_col) ?
                           (scan_col - best_col) : (best_col - scan_col);
    wire [5:0] row_delta = (scan_row > best_row) ?
                           (scan_row - best_row) : (best_row - scan_row);
    wire in_cluster = (col_delta <= CLUSTER_RADIUS) &&
                      (row_delta <= CLUSTER_RADIUS);
    wire [5:0] second_col_delta = (scan_col > second_best_col) ?
                                  scan_col-second_best_col : second_best_col-scan_col;
    wire [5:0] second_row_delta = (scan_row > second_best_row) ?
                                  scan_row-second_best_row : second_best_row-scan_row;
    wire [6:0] second_thresh = ((second_best_cnt >> 1) > BLOCK_MIN) ?
                               (second_best_cnt >> 1) : BLOCK_MIN;
    wire in_second_cluster = (second_col_delta <= CLUSTER_RADIUS) &&
                             (second_row_delta <= CLUSTER_RADIUS) && !in_cluster;
    wire primary_candidate_valid = found && (best_cnt >= BLOCK_MIN) &&
                                    (weight_acc != 0) && have_prev &&
                                    (motion_total < GLOBAL_MOTION_LIMIT);
    wire secondary_candidate_valid = second_found && (second_best_cnt >= BLOCK_MIN) &&
                                      (second_weight_acc != 0) && have_prev &&
                                      (motion_total < GLOBAL_MOTION_LIMIT);
    wire ranked_result_valid, ranked_candidate_valid;
    wire [8:0] ranked_cx;
    wire [7:0] ranked_cy;
    wire ranked_secondary, ranked_moving;
    motion_candidate_priority #(
        .HISTORY(8), .MIN_DISPLACEMENT(24), .MIN_MOVING_STEPS(3)
    ) u_candidate_priority (
        .clk(clk), .rst_n(rst_n), .enable(!track_enable_lat),
        .update(state == ST_RANK),
        .primary_valid(primary_candidate_valid), .primary_x(primary_cx), .primary_y(primary_cy),
        .secondary_valid(secondary_candidate_valid), .secondary_x(secondary_cx), .secondary_y(secondary_cy),
        .result_valid(ranked_result_valid), .candidate_valid(ranked_candidate_valid),
        .candidate_x(ranked_cx), .candidate_y(ranked_cy),
        .selected_secondary(ranked_secondary), .motion_preferred(ranked_moving)
    );
    wire [14:0] rem_x_shift = {rem_x[13:0], div_num_x[22]};
    wire [15:0] rem_y_shift = {rem_y[14:0], div_num_y[22]};

    // Ping-pong luminance banks.  The write bank is never read in the same
    // frame, avoiding read-during-write ambiguity and giving an unambiguous
    // previous frame for every comparison.
    always @(posedge clk) begin
        if (pix_we) begin
            frame_mem[frame_wr_addr] <= luma;
            prev_q                   <= frame_mem[frame_rd_addr];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_valid    <= 1'b0;
            pipe_x        <= 9'd0;
            pipe_y        <= 8'd0;
            pipe_luma     <= 8'd0;
            prev_hit      <= 1'b0;
            prev_hit_x    <= 9'd0;
            prev_hit_y    <= 8'd0;
            motion_total  <= 16'd0;
            sum_cur       <= 24'd0;
            sum_last      <= 24'd0;
            mean_shift    <= 9'sd0;
            write_bank    <= 1'b0;
            have_prev     <= 1'b0;
            prev_cand     <= 1'b0;
            prev_cand_x   <= 9'd0;
            prev_cand_y   <= 8'd0;
            second_best_cnt <= 0;
            second_best_col <= 0;
            second_best_row <= 0;
            second_found <= 0;
            second_weight_acc <= 0;
            second_x_sum <= 0;
            second_y_sum <= 0;
            div_second <= 0;
            primary_cx <= 0; primary_cy <= 0;
            secondary_cx <= 0; secondary_cy <= 0;
            hold_count    <= 6'd0;
            state         <= ST_IDLE;
            scan_idx      <= 12'd0;
            scan_col      <= 6'd0;
            scan_row      <= 6'd0;
            best_cnt      <= 7'd0;
            best_col      <= 6'd0;
            best_row      <= 6'd0;
            found         <= 1'b0;
            weight_acc    <= 14'd0;
            weighted_x_sum<= 23'd0;
            weighted_y_sum<= 20'd0;
            div_den       <= 14'd0;
            div_num_x     <= 23'd0;
            div_num_y     <= 23'd0;
            rem_x         <= 15'd0;
            rem_y         <= 15'd0;
            div_quot_x    <= 23'd0;
            div_quot_y    <= 23'd0;
            div_count     <= 5'd0;
            box_valid     <= 1'b0;
            track_found   <= 1'b0;
            box_x0        <= 9'd0;
            box_x1        <= 9'd0;
            box_y0        <= 8'd0;
            box_y1        <= 8'd0;
            smooth_cx     <= 9'd0;
            smooth_cy     <= 8'd0;
            center_valid  <= 1'b0;
            track_enable_lat <= 1'b0;
            track_x0_lat <= 9'd0;
            track_y0_lat <= 8'd0;
            best_dark_count <= 7'd0;
            best_dark_bin <= 6'd0;
            best_dark_score <= -9'sd255;
            for (k = 0; k < 36; k = k + 1) begin
                dark_bin_count[k] <= 7'd0;
                dark_bin_min_x[k] <= 6'd63;
                dark_bin_max_x[k] <= 6'd0;
                dark_bin_min_y[k] <= 6'd63;
                dark_bin_max_y[k] <= 6'd0;
            end
            motion_count  <= 14'd0;
            dbg_best      <= 7'd0;
            dbg_total     <= 16'd0;
        end else begin
            if (frame_sync) begin
                // Keep the best dark cell incrementally while pixels arrive.
                // A single 36-cell priority chain would not meet camera timing.
                best_dark_count <= 7'd0;
                best_dark_bin <= 6'd0;
                best_dark_score <= -9'sd255;
                // A held TRACK box is not a fresh SEARCH candidate.  Clear it
                // as soon as tracking ends so the full-frame detector can
                // accept the next two actual motion frames.
                if (track_enable_lat && !track_enable) begin
                    box_valid    <= 1'b0;
                    prev_cand    <= 1'b0;
                    hold_count   <= 6'd0;
                    center_valid <= 1'b0;
                end
                if (track_enable_lat && !track_enable) begin
                    track_found <= 1'b0;
                end else if (track_enable_lat) begin
                    track_found <= (best_dark_count >= 7'd12);
                    if (best_dark_count >= 7'd12) begin
                        cx = track_x0_lat +
                             ((dark_bin_min_x[best_dark_bin] +
                               dark_bin_max_x[best_dark_bin]) >> 1);
                        cy = track_y0_lat +
                             ((dark_bin_min_y[best_dark_bin] +
                               dark_bin_max_y[best_dark_bin]) >> 1);
                        if (!center_valid) begin
                            smooth_x = cx;
                            smooth_y = cy;
                        end else begin
                            diff_x = cx - smooth_cx;
                            diff_y = cy - smooth_cy;
                            if (diff_x > 16) diff_x = 16;
                            if (diff_x < -16) diff_x = -16;
                            if (diff_y > 16) diff_y = 16;
                            if (diff_y < -16) diff_y = -16;
                            smooth_x = smooth_cx + diff_x;
                            smooth_y = smooth_cy + diff_y;
                        end

                        if (smooth_x < BOX_HALF) smooth_x = BOX_HALF;
                        if (smooth_y < BOX_HALF) smooth_y = BOX_HALF;
                        if (smooth_x > W - 1 - BOX_HALF)
                            smooth_x = W - 1 - BOX_HALF;
                        if (smooth_y > H - 1 - BOX_HALF)
                            smooth_y = H - 1 - BOX_HALF;

                        bx = smooth_x - BOX_HALF;
                        by = smooth_y - BOX_HALF;
                        box_x0 <= bx[8:0];
                        box_x1 <= bx + 2 * BOX_HALF - 1;
                        box_y0 <= by[7:0];
                        box_y1 <= by + 2 * BOX_HALF - 1;
                        smooth_cx <= smooth_x[8:0];
                        smooth_cy <= smooth_y[7:0];
                        center_valid <= 1'b1;
                        box_valid <= 1'b1;
                        hold_count <= 6'd0;
                        motion_count <= {7'd0, best_dark_count};
                    end
                end else begin
                    track_found <= 1'b0;
                end

                track_enable_lat <= track_enable;
                track_x0_lat <= track_x0 >> 1;
                track_y0_lat <= track_y0 >> 1;
                for (k = 0; k < 36; k = k + 1) begin
                    dark_bin_count[k] <= 7'd0;
                    dark_bin_min_x[k] <= 6'd63;
                    dark_bin_max_x[k] <= 6'd0;
                    dark_bin_min_y[k] <= 6'd63;
                    dark_bin_max_y[k] <= 6'd0;
                end
            end
            pipe_valid <= pix_we;
            if (pix_we) begin
                pipe_x    <= pix_x;
                pipe_y    <= pix_y;
                pipe_luma <= luma;
                sum_cur   <= sum_cur + {16'd0, luma};
            end

            if (pix_we && dark_track_hit) begin
                dark_bin_count[dark_bin_index] <= dark_next_count;
                if ((dark_next_count >= 7'd12) &&
                    (dark_score > best_dark_score)) begin
                    best_dark_score <= dark_score;
                    best_dark_count <= dark_next_count;
                    best_dark_bin <= dark_bin_index;
                end
                if (rel_track_x < dark_bin_min_x[dark_bin_index])
                    dark_bin_min_x[dark_bin_index] <= rel_track_x;
                if (rel_track_x > dark_bin_max_x[dark_bin_index])
                    dark_bin_max_x[dark_bin_index] <= rel_track_x;
                if (rel_track_y < dark_bin_min_y[dark_bin_index])
                    dark_bin_min_y[dark_bin_index] <= rel_track_y;
                if (rel_track_y > dark_bin_max_y[dark_bin_index])
                    dark_bin_max_y[dark_bin_index] <= rel_track_y;
            end

            if (pipe_valid) begin
                prev_hit   <= hit;
                prev_hit_x <= pipe_x;
                prev_hit_y <= pipe_y;
            end

            if (pipe_valid && have_prev && (state == ST_IDLE) && pair_hit) begin
                blk_count[blk_idx] <= blk_count[blk_idx] + pair_weight;
                motion_total       <= motion_total + {9'd0, pair_weight};
            end

            case (state)
                ST_IDLE: begin
                    if (frame_sync) begin
                        write_bank   <= ~write_bank;
                        state        <= ST_PASS1;
                        scan_idx     <= 12'd0;
                        scan_col     <= 6'd0;
                        scan_row     <= 6'd0;
                        best_cnt     <= 7'd0;
                        best_col     <= 6'd0;
                        best_row     <= 6'd0;
                        found        <= 1'b0;
                        second_best_cnt <= 0;
                        second_best_col <= 0;
                        second_best_row <= 0;
                        second_found <= 0;
                        second_weight_acc <= 0;
                        second_x_sum <= 0;
                        second_y_sum <= 0;
                        weight_acc   <= 14'd0;
                        weighted_x_sum <= 23'd0;
                        weighted_y_sum <= 20'd0;
                        sum_last     <= sum_cur;
                        sum_cur      <= 24'd0;
                        if (have_prev)
                            mean_shift <= sum_diff >>> 16;
                    end
                end

                ST_PASS1: begin
                    c = blk_count[scan_idx];
                    if (c > best_cnt) begin
                        best_cnt <= c;
                        best_col <= scan_col;
                        best_row <= scan_row;
                    end

                    if (scan_idx == NB - 1) begin
                        state    <= ST_SECOND_SEED;
                        scan_idx <= 12'd0;
                        scan_col <= 6'd0;
                        scan_row <= 6'd0;
                    end else begin
                        scan_idx <= scan_idx + 1'b1;
                        if (scan_col == NBX - 1) begin
                            scan_col <= 6'd0;
                            scan_row <= scan_row + 1'b1;
                        end else begin
                            scan_col <= scan_col + 1'b1;
                        end
                    end
                end

                ST_SECOND_SEED: begin
                    c = blk_count[scan_idx];
                    if (!in_cluster && (c > second_best_cnt)) begin
                        second_best_cnt <= c;
                        second_best_col <= scan_col;
                        second_best_row <= scan_row;
                    end
                    if (scan_idx == NB-1) begin
                        state <= ST_PASS2;
                        scan_idx <= 0;
                        scan_col <= 0;
                        scan_row <= 0;
                    end else begin
                        scan_idx <= scan_idx + 1'b1;
                        if (scan_col == NBX-1) begin
                            scan_col <= 0;
                            scan_row <= scan_row + 1'b1;
                        end else scan_col <= scan_col + 1'b1;
                    end
                end

                ST_PASS2: begin
                    c = blk_count[scan_idx];
                    if ((c >= blk_thresh) && in_cluster) begin
                        found          <= 1'b1;
                        weight_acc     <= weight_acc + c;
                        weighted_x_sum <= weighted_x_sum +
                                          c * (({1'b0, scan_col} << 1) + 1'b1);
                        weighted_y_sum <= weighted_y_sum +
                                          c * (({1'b0, scan_row} << 1) + 1'b1);
                    end
                    if ((second_best_cnt >= BLOCK_MIN) &&
                        (c >= second_thresh) && in_second_cluster) begin
                        second_found <= 1;
                        second_weight_acc <= second_weight_acc + c;
                        second_x_sum <= second_x_sum + c * (({1'b0,scan_col} << 1) + 1'b1);
                        second_y_sum <= second_y_sum + c * (({1'b0,scan_row} << 1) + 1'b1);
                    end
                    blk_count[scan_idx] <= 7'd0;

                    if (scan_idx == NB - 1) begin
                        state <= ST_DIV_PREP;
                    end else begin
                        scan_idx <= scan_idx + 1'b1;
                        if (scan_col == NBX - 1) begin
                            scan_col <= 6'd0;
                            scan_row <= scan_row + 1'b1;
                        end else begin
                            scan_col <= scan_col + 1'b1;
                        end
                    end
                end

                ST_DIV_PREP: begin
                    dbg_best  <= best_cnt;
                    dbg_total <= motion_total;
                    div_den   <= weight_acc;
                    div_num_x <= weighted_x_sum;
                    div_num_y <= {3'b000, weighted_y_sum};
                    rem_x     <= 15'd0;
                    rem_y     <= 15'd0;
                    div_quot_x<= 23'd0;
                    div_quot_y<= 23'd0;
                    div_count <= 5'd0;
                    div_second <= 0;
                    state     <= (found && (weight_acc != 0)) ? ST_DIVIDE : ST_RANK;
                end

                ST_DIVIDE: begin
                    div_num_x <= {div_num_x[21:0], 1'b0};
                    div_num_y <= {div_num_y[21:0], 1'b0};
                    if (rem_x_shift >= {1'b0, div_den}) begin
                        rem_x       <= rem_x_shift - {1'b0, div_den};
                        div_quot_x <= {div_quot_x[21:0], 1'b1};
                    end else begin
                        rem_x       <= rem_x_shift;
                        div_quot_x <= {div_quot_x[21:0], 1'b0};
                    end

                    if (rem_y_shift >= {2'b00, div_den}) begin
                        rem_y       <= rem_y_shift[14:0] - div_den;
                        div_quot_y <= {div_quot_y[21:0], 1'b1};
                    end else begin
                        rem_y       <= rem_y_shift[14:0];
                        div_quot_y <= {div_quot_y[21:0], 1'b0};
                    end

                    if (div_count == 5'd22)
                        state <= ST_DIV_DONE;
                    else
                        div_count <= div_count + 1'b1;
                end

                ST_DIV_DONE: begin
                    if (!div_second) begin
                        primary_cx <= (div_quot_x[6:0] * BLK) >> 1;
                        primary_cy <= (div_quot_y[6:0] * BLK) >> 1;
                        if (secondary_candidate_valid) begin
                            div_second <= 1;
                            div_den <= second_weight_acc;
                            div_num_x <= second_x_sum;
                            div_num_y <= {3'b000, second_y_sum};
                            rem_x <= 0; rem_y <= 0;
                            div_quot_x <= 0; div_quot_y <= 0;
                            div_count <= 0;
                            state <= ST_DIVIDE;
                        end else state <= ST_RANK;
                    end else begin
                        secondary_cx <= (div_quot_x[6:0] * BLK) >> 1;
                        secondary_cy <= (div_quot_y[6:0] * BLK) >> 1;
                        state <= ST_RANK;
                    end
                end

                ST_RANK: state <= ST_FINISH;

                ST_FINISH: if (track_enable_lat || ranked_result_valid) begin
                    candidate_now = !track_enable_lat && ranked_result_valid && ranked_candidate_valid;
                    prev_cand <= candidate_now;

                    if (candidate_now) begin
                        cx = ranked_cx;
                        cy = ranked_cy;
                        diff_x = cx - prev_cand_x;
                        diff_y = cy - prev_cand_y;
                        manhattan = ((diff_x >= 0) ? diff_x : -diff_x) +
                                    ((diff_y >= 0) ? diff_y : -diff_y);
                        prev_cand_x <= cx[8:0];
                        prev_cand_y <= cy[7:0];
                    end

                    if (candidate_now && prev_cand && (manhattan <= 48)) begin
                        // quot_x/y average (2*block+1), so multiply by BLK/2.
                        if (!center_valid) begin
                            smooth_x = cx;
                            smooth_y = cy;
                        end else begin
                            diff_x = cx - smooth_cx;
                            diff_y = cy - smooth_cy;
                            manhattan = ((diff_x >= 0) ? diff_x : -diff_x) +
                                        ((diff_y >= 0) ? diff_y : -diff_y);
                            if (manhattan > JUMP_DISTANCE) begin
                                smooth_x = cx;
                                smooth_y = cy;
                            end else if (manhattan <= CENTER_DEADBAND) begin
                                smooth_x = smooth_cx;
                                smooth_y = smooth_cy;
                            end else begin
                                smooth_x = smooth_cx + (diff_x >>> 2);
                                smooth_y = smooth_cy + (diff_y >>> 2);
                            end
                        end

                        if (smooth_x < BOX_HALF) smooth_x = BOX_HALF;
                        if (smooth_y < BOX_HALF) smooth_y = BOX_HALF;
                        if (smooth_x > W - 1 - BOX_HALF)
                            smooth_x = W - 1 - BOX_HALF;
                        if (smooth_y > H - 1 - BOX_HALF)
                            smooth_y = H - 1 - BOX_HALF;

                        bx = smooth_x - BOX_HALF;
                        by = smooth_y - BOX_HALF;
                        box_x0       <= bx[8:0];
                        box_x1       <= bx + 2 * BOX_HALF - 1;
                        box_y0       <= by[7:0];
                        box_y1       <= by + 2 * BOX_HALF - 1;
                        smooth_cx    <= smooth_x[8:0];
                        smooth_cy    <= smooth_y[7:0];
                        center_valid <= 1'b1;
                        box_valid    <= 1'b1;
                        hold_count   <= 6'd0;
                        motion_count <= {7'd0, best_cnt};
                    end else if (box_valid) begin
                        if (hold_count >= HOLD_FRAMES) begin
                            box_valid    <= 1'b0;
                            center_valid <= 1'b0;
                        end else begin
                            hold_count <= hold_count + 1'b1;
                        end
                    end

                    have_prev    <= 1'b1;
                    motion_total <= 16'd0;
                    state        <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
