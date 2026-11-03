// Camera-domain ROI state machine. roi_hold freezes coordinates during an SCNN transaction.
`timescale 1ns / 1ps

module roi_scheduler #(
    parameter integer LOW_RECHECK_LIMIT = 5
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        frame_sync,
    input  wire        roi_hold,
    input  wire        label_valid,
    input  wire        is_drone,
    input  wire        drone_count_low,
    input  wire        recheck_tick,

    input  wire        motion_valid,
    input  wire [8:0]  motion_x0,
    input  wire [8:0]  motion_x1,
    input  wire [7:0]  motion_y0,
    input  wire [7:0]  motion_y1,

    output reg  [9:0]  roi_x0,
    output reg  [8:0]  roi_y0,
    output wire        tracking,
    output wire        verifying
);
    localparam [2:0] MODE_SEARCH     = 3'd0;
    localparam [2:0] MODE_VERIFY     = 3'd1;
    localparam [2:0] MODE_TRACK      = 3'd2;
    localparam [2:0] MODE_REACQUIRE  = 3'd3;
    localparam [2:0] MODE_LOST_CHECK = 3'd4;
    localparam [2:0] MODE_PERIODIC_CHECK = 3'd5;

    localparam integer ROI_SIDE = 128;
    localparam integer ROI_HALF = ROI_SIDE / 2;
    localparam [9:0] SEARCH_X = 10'd236;
    localparam [8:0] SEARCH_Y = 9'd136;
    localparam [2:0] CONFIRM_WINDOW = 3'd5;
    localparam [2:0] CONFIRM_HITS = 3'd3;
    localparam [1:0] REMOTE_CONFIRM_FRAMES = 2'd3;
    localparam [5:0] LOST_FRAME_LIMIT = 6'd45;
    localparam [9:0] LOCAL_GATE = 10'd96;

    reg [2:0] mode;
    reg       motion_armed;
    reg [2:0] confirm_score;
    reg [4:0] drone_hist;
    reg [2:0] hist_count;
    reg [1:0] remote_count;
    reg [5:0] lost_not_count;
    reg [9:0] saved_roi_x;
    reg [8:0] saved_roi_y;
    localparam integer LOW_COUNT_W = (LOW_RECHECK_LIMIT > 1) ?
                                       $clog2(LOW_RECHECK_LIMIT) : 1;
    reg [LOW_COUNT_W-1:0] low_recheck_count;

    assign tracking  = (mode == MODE_TRACK) || (mode == MODE_LOST_CHECK) ||
                       (mode == MODE_PERIODIC_CHECK);
    assign verifying = (mode == MODE_VERIFY) || (mode == MODE_REACQUIRE) ||
                       (mode == MODE_LOST_CHECK) || (mode == MODE_PERIODIC_CHECK);

    wire [9:0] mx_sum = {1'b0, motion_x0} + {1'b0, motion_x1} + 1'b1;
    wire [8:0] my_sum = {1'b0, motion_y0} + {1'b0, motion_y1} + 1'b1;
    wire [9:0] motion_cx = {1'b0, mx_sum[9:1]} << 1;
    wire [8:0] motion_cy = {1'b0, my_sum[8:1]} << 1;

    wire [9:0] cand_x_tmp = (motion_cx >= ROI_HALF) ?
                            (motion_cx - ROI_HALF) : 10'd0;
    wire [8:0] cand_y_tmp = (motion_cy >= ROI_HALF) ?
                            (motion_cy - ROI_HALF) : 9'd0;
    wire [9:0] cand_x0 = ((cand_x_tmp + ROI_SIDE) > 10'd600) ?
                         (10'd600 - ROI_SIDE) : cand_x_tmp;
    wire [8:0] cand_y0 = ((cand_y_tmp + ROI_SIDE) > 9'd400) ?
                         (9'd400 - ROI_SIDE) : cand_y_tmp;

    wire [9:0] roi_center_x = roi_x0 + ROI_HALF;
    wire [8:0] roi_center_y = roi_y0 + ROI_HALF;

    wire [9:0] dx = (motion_cx > roi_center_x) ?
                    (motion_cx - roi_center_x) : (roi_center_x - motion_cx);
    wire [8:0] dy = (motion_cy > roi_center_y) ?
                    (motion_cy - roi_center_y) : (roi_center_y - motion_cy);
    wire [9:0] motion_distance = {1'b0, dx} + {2'b00, dy};
    wire motion_moved = motion_distance > 10'd4;
    wire motion_far = motion_distance > LOCAL_GATE;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode           <= MODE_SEARCH;
            motion_armed   <= 1'b1;
            confirm_score  <= 3'd0;
            drone_hist     <= 5'd0;
            hist_count     <= 3'd0;
            remote_count   <= 2'd0;
            lost_not_count <= 6'd0;
            saved_roi_x    <= SEARCH_X;
            saved_roi_y    <= SEARCH_Y;
            roi_x0         <= SEARCH_X;
            roi_y0         <= SEARCH_Y;
            low_recheck_count <= {LOW_COUNT_W{1'b0}};
        end else begin
            if (!motion_valid)
                motion_armed <= 1'b1;

            if (recheck_tick && (mode == MODE_TRACK) && !roi_hold)
                mode <= MODE_PERIODIC_CHECK;

            if (label_valid) begin

                if (tracking && !drone_count_low)
                    low_recheck_count <= {LOW_COUNT_W{1'b0}};
                case (mode)
                    MODE_SEARCH, MODE_VERIFY: begin
                        drone_hist <= {drone_hist[3:0], is_drone};
                        if (hist_count < CONFIRM_WINDOW)
                            hist_count <= hist_count + 1'b1;
                        if ((hist_count >= CONFIRM_WINDOW - 1'b1) &&
                            ((drone_hist[3] + drone_hist[2] + drone_hist[1] +
                              drone_hist[0] + is_drone) >= CONFIRM_HITS)) begin
                                mode           <= MODE_TRACK;
                                confirm_score  <= CONFIRM_HITS;
                                drone_hist     <= 5'd0;
                                hist_count     <= 3'd0;
                                remote_count   <= 2'd0;
                                lost_not_count <= 6'd0;
                                low_recheck_count <= {LOW_COUNT_W{1'b0}};
                        end
                    end
                    MODE_REACQUIRE: begin
                        drone_hist <= {drone_hist[3:0], is_drone};
                        if (hist_count < CONFIRM_WINDOW)
                            hist_count <= hist_count + 1'b1;
                        if (hist_count >= CONFIRM_WINDOW - 1'b1) begin
                            if ((drone_hist[3] + drone_hist[2] + drone_hist[1] +
                                 drone_hist[0] + is_drone) >= CONFIRM_HITS) begin
                                mode <= MODE_TRACK;
                                confirm_score <= CONFIRM_HITS;
                                drone_hist <= 5'd0;
                                hist_count <= 3'd0;
                                remote_count <= 2'd0;
                                lost_not_count <= 6'd0;
                                low_recheck_count <= {LOW_COUNT_W{1'b0}};
                            end else begin
                                mode <= MODE_TRACK;
                                confirm_score <= CONFIRM_HITS;
                                drone_hist <= 5'd0;
                                hist_count <= 3'd0;
                                remote_count <= 2'd0;
                                lost_not_count <= 6'd0;
                                roi_x0 <= saved_roi_x;
                                roi_y0 <= saved_roi_y;
                            end
                            drone_hist <= 5'd0;
                            hist_count <= 3'd0;
                        end
                    end
                    MODE_LOST_CHECK: begin
                        drone_hist <= {drone_hist[3:0], is_drone};
                        if (hist_count < CONFIRM_WINDOW)
                            hist_count <= hist_count + 1'b1;
                        if (hist_count >= CONFIRM_WINDOW - 1'b1) begin
                            if ((drone_hist[3] + drone_hist[2] + drone_hist[1] +
                                 drone_hist[0] + is_drone) >= CONFIRM_HITS) begin
                                mode <= MODE_TRACK;
                            end else begin
                                mode <= MODE_SEARCH;
                                motion_armed <= 1'b0;
                                low_recheck_count <= {LOW_COUNT_W{1'b0}};
                            end
                            drone_hist <= 5'd0;
                            hist_count <= 3'd0;
                            lost_not_count <= 6'd0;
                        end
                    end
                    MODE_PERIODIC_CHECK: begin
                        if (drone_count_low &&
                            (low_recheck_count >= LOW_RECHECK_LIMIT - 1)) begin
                            mode <= MODE_SEARCH;
                            motion_armed <= 1'b0;
                            low_recheck_count <= {LOW_COUNT_W{1'b0}};
                            drone_hist <= 5'd0;
                            hist_count <= 3'd0;
                            confirm_score <= 3'd0;
                            remote_count <= 2'd0;
                            lost_not_count <= 6'd0;

                        end else begin
                            mode <= MODE_TRACK;
                            if (drone_count_low)
                                low_recheck_count <= low_recheck_count + 1'b1;
                        end
                    end
                    default: begin end
                endcase
            end

            if (frame_sync && !roi_hold) begin
                if (mode == MODE_TRACK) begin
                    if (motion_valid)
                        lost_not_count <= 6'd0;
                    else if (lost_not_count >= LOST_FRAME_LIMIT - 1'b1) begin
                        mode           <= MODE_LOST_CHECK;
                        confirm_score  <= 3'd0;
                        drone_hist     <= 5'd0;
                        hist_count     <= 3'd0;
                        remote_count   <= 2'd0;
                        lost_not_count <= 6'd0;
                    end else
                        lost_not_count <= lost_not_count + 1'b1;
                end
                if (!motion_valid) begin
                    remote_count <= 2'd0;
                    case (mode)
                        MODE_VERIFY: begin
                            mode          <= MODE_SEARCH;
                            confirm_score <= 3'd0;
                            drone_hist    <= 5'd0;
                            hist_count    <= 3'd0;

                        end
                        MODE_REACQUIRE: begin
                            mode           <= MODE_TRACK;
                            confirm_score  <= CONFIRM_HITS;
                            lost_not_count <= 6'd0;
                            roi_x0         <= saved_roi_x;
                            roi_y0         <= saved_roi_y;
                        end
                        default: begin
                        end
                    endcase
                end else begin
                    case (mode)
                        MODE_SEARCH: begin
                            if (motion_armed) begin
                                roi_x0        <= cand_x0;
                                roi_y0        <= cand_y0;
                                mode          <= MODE_VERIFY;
                                confirm_score <= 2'd0;
                                motion_armed  <= 1'b0;
                            end
                        end

                        MODE_VERIFY: begin
                            if (motion_far) begin

                                roi_x0        <= cand_x0;
                                roi_y0        <= cand_y0;
                                confirm_score <= 2'd0;
                                drone_hist    <= 5'd0;
                                hist_count    <= 3'd0;
                            end else if (motion_moved) begin
                                roi_x0 <= cand_x0;
                                roi_y0 <= cand_y0;
                            end
                        end

                        MODE_TRACK: begin
                            if (motion_far) begin

                                if (remote_count >= REMOTE_CONFIRM_FRAMES - 1'b1) begin
                                    saved_roi_x   <= roi_x0;
                                    saved_roi_y   <= roi_y0;
                                    roi_x0        <= cand_x0;
                                    roi_y0        <= cand_y0;
                                    mode          <= MODE_REACQUIRE;
                                    confirm_score <= 2'd0;
                                    drone_hist    <= 5'd0;
                                    hist_count    <= 3'd0;
                                    remote_count  <= 2'd0;
                                    lost_not_count<= 6'd0;
                                end else begin
                                    remote_count <= remote_count + 1'b1;
                                end
                            end else begin
                                remote_count <= 2'd0;
                                if (motion_moved) begin
                                    roi_x0 <= cand_x0;
                                    roi_y0 <= cand_y0;
                                end
                            end
                        end

                        MODE_REACQUIRE: begin
                            if (motion_far) begin
                                roi_x0 <= cand_x0;
                                roi_y0 <= cand_y0;
                            end else if (motion_moved) begin
                                roi_x0 <= cand_x0;
                                roi_y0 <= cand_y0;
                            end
                        end
                        MODE_LOST_CHECK: begin

                            mode <= MODE_TRACK;
                            drone_hist <= 5'd0;
                            hist_count <= 3'd0;
                            lost_not_count <= 6'd0;
                        end
                        default: begin end
                    endcase
                end
            end
        end
    end
endmodule
