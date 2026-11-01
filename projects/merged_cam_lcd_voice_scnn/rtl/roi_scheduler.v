`timescale 1ns / 1ps
// RGB 128x128 crop search.  24 overlapping windows cover 600x400.
// Acquisition stays 3/5. Locked targets use the feifei periodic low-count
// policy and 45-frame lost-target verification; no one-second identity timeout.
module roi_scheduler #(
    parameter integer LOW_RECHECK_LIMIT = 5
)(
    input wire clk, rst_n, frame_sync, roi_hold,
    input wire run_en,        // 0 = 非防空模式：ROI 冻结在画面中心，不搜索也不跟踪
    input wire label_valid, is_drone, drone_count_low, recheck_tick,
    input wire motion_valid, motion_update,
    input wire [8:0] motion_x0, motion_x1,
    input wire [7:0] motion_y0, motion_y1,
    output reg [9:0] roi_x0,
    output reg [8:0] roi_y0,
    output wire tracking, verifying
);
    localparam [2:0] SEARCH=0, VERIFY=1, TRACK=2, LOST_CHECK=4, PERIODIC_CHECK=5;
    localparam [5:0] LOST_FRAME_LIMIT=45;
    localparam [9:0] CENTER_X0 = 10'd236;     // 128x128 框在 600x400 画面正中
    localparam [8:0] CENTER_Y0 = 9'd136;
    reg [2:0] mode;
    reg [2:0] samples, hits, scan_col;
    reg [1:0] scan_row;
    reg step_pending, proposal_pending, rejected_valid;
    reg [5:0] lost_not_count;
    localparam integer LOW_COUNT_W=(LOW_RECHECK_LIMIT>1)?$clog2(LOW_RECHECK_LIMIT):1;
    reg [LOW_COUNT_W-1:0] low_recheck_count;
    reg [9:0] proposal_x, rejected_x;
    reg [8:0] proposal_y, rejected_y;
    reg signed [10:0] velocity_x;
    reg signed [9:0] velocity_y;
    integer nx, ny, vx, vy;
    assign tracking=(mode==TRACK || mode==LOST_CHECK || mode==PERIODIC_CHECK);
    assign verifying=(mode==VERIFY || mode==LOST_CHECK || mode==PERIODIC_CHECK);
    function [9:0] scan_x(input [2:0] col);
        case(col)
            0:scan_x=0; 1:scan_x=96; 2:scan_x=192;
            3:scan_x=288; 4:scan_x=384; default:scan_x=472;
        endcase
    endfunction
    function [8:0] scan_y(input [1:0] row);
        case(row)
            0:scan_y=0; 1:scan_y=96; 2:scan_y=192; default:scan_y=272;
        endcase
    endfunction
    function [9:0] clamp_x(input integer x);
        clamp_x=(x<0)?0:((x>472)?472:x);
    endfunction
    function [8:0] clamp_y(input integer y);
        clamp_y=(y<0)?0:((y>272)?272:y);
    endfunction
    // Inclusive detector centre, converted directly from 300x200 to 600x400.
    wire [9:0] cx={1'b0,motion_x0}+{1'b0,motion_x1}+10'd1;
    wire [8:0] cy={1'b0,motion_y0}+{1'b0,motion_y1}+9'd1;
    wire [9:0] candidate_x=clamp_x($signed({1'b0,cx})-64);
    wire [8:0] candidate_y=clamp_y($signed({1'b0,cy})-64);
    wire [9:0] dx=(candidate_x>roi_x0)?candidate_x-roi_x0:roi_x0-candidate_x;
    wire [8:0] dy=(candidate_y>roi_y0)?candidate_y-roi_y0:roi_y0-candidate_y;
    wire [9:0] reject_dx=(proposal_x>rejected_x)?proposal_x-rejected_x:rejected_x-proposal_x;
    wire [8:0] reject_dy=(proposal_y>rejected_y)?proposal_y-rejected_y:rejected_y-proposal_y;
    wire proposal_allowed=proposal_pending &&
        (!rejected_valid || ({1'b0,reject_dx}+{2'b0,reject_dy}>64));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            mode<=SEARCH; samples<=0; hits<=0; scan_col<=0; scan_row<=0;
            step_pending<=0; lost_not_count<=0; low_recheck_count<=0;
            proposal_pending<=0; proposal_x<=236; proposal_y<=136;
            rejected_valid<=0; rejected_x<=0; rejected_y<=0;
            roi_x0<=CENTER_X0; roi_y0<=CENTER_Y0; velocity_x<=0; velocity_y<=0;
        end else if(!run_en) begin
            // 非防空模式（循迹/跟随/停下/装卸货/上电）：红框固定在画面中心不动，
            // 不扫描也不跟踪。重新进入防空后从这个位置开始一轮新的搜索。
            roi_x0<=CENTER_X0; roi_y0<=CENTER_Y0;
            mode<=SEARCH; samples<=0; hits<=0; scan_col<=0; scan_row<=0;
            step_pending<=0; proposal_pending<=0;
            rejected_valid<=0; lost_not_count<=0; low_recheck_count<=0;
            velocity_x<=0; velocity_y<=0;
        end else begin
            if(motion_update && motion_valid && !tracking) begin
                proposal_pending<=1; proposal_x<=candidate_x; proposal_y<=candidate_y;
            end
            if(!motion_valid && !tracking && motion_update)
                proposal_pending<=0;
            // Match feifei: busy timer requests are skipped, not queued.
            if(recheck_tick && mode==TRACK && !roi_hold) mode<=PERIODIC_CHECK;
            if(label_valid) begin
                if(tracking && !drone_count_low) low_recheck_count<=0;
                case(mode)
                    SEARCH: if(is_drone) begin
                        mode<=VERIFY; samples<=1; hits<=1; step_pending<=0;
                    end else step_pending<=1;
                    VERIFY: begin
                        samples<=samples+1'b1; hits<=hits+{2'b0,is_drone};
                        if(samples==4) begin
                            samples<=0; hits<=0;
                            if(hits+{2'b0,is_drone}>=3) begin
                                mode<=TRACK; lost_not_count<=0; low_recheck_count<=0;
                                proposal_pending<=0; velocity_x<=0; velocity_y<=0;
                            end else begin
                                mode<=SEARCH; step_pending<=1; rejected_valid<=1;
                                rejected_x<=roi_x0; rejected_y<=roi_y0;
                            end
                        end
                    end
                    LOST_CHECK: begin
                        samples<=samples+1'b1; hits<=hits+{2'b0,is_drone};
                        if(samples==4) begin
                            samples<=0; hits<=0; lost_not_count<=0;
                            if(hits+{2'b0,is_drone}>=3) mode<=TRACK;
                            else begin
                                mode<=SEARCH; step_pending<=0; low_recheck_count<=0;
                                proposal_pending<=0; rejected_valid<=0;
                                scan_col<=0; scan_row<=0; velocity_x<=0; velocity_y<=0;
                            end
                        end
                    end
                    PERIODIC_CHECK: begin
                        if(drone_count_low && low_recheck_count>=LOW_RECHECK_LIMIT-1) begin
                            mode<=SEARCH; step_pending<=0; low_recheck_count<=0;
                            samples<=0; hits<=0; lost_not_count<=0;
                            proposal_pending<=0; rejected_valid<=0;
                            scan_col<=0; scan_row<=0; velocity_x<=0; velocity_y<=0;
                            // Keep the last ROI while global motion search resumes.
                        end else begin
                            mode<=TRACK;
                            if(drone_count_low) low_recheck_count<=low_recheck_count+1'b1;
                        end
                    end
                    TRACK: begin end
                    default:mode<=SEARCH;
                endcase
            end
            if(frame_sync) begin
                // Count only idle TRACK frames, exactly as the donor policy.
                // This path has priority over a coincident periodic request.
                if(!roi_hold) begin
                    if(mode==TRACK) begin
                        if(motion_valid) lost_not_count<=0;
                        else if(lost_not_count>=LOST_FRAME_LIMIT-1'b1) begin
                            mode<=LOST_CHECK; samples<=0; hits<=0; lost_not_count<=0;
                        end else lost_not_count<=lost_not_count+1'b1;
                    end else if(mode==LOST_CHECK && motion_valid) begin
                        mode<=TRACK; samples<=0; hits<=0; lost_not_count<=0;
                    end
                end
                if(mode==TRACK) begin
                    // Resampler has its own latched crop.  Track may keep
                    // following while a previous RGB crop is in inference.
                    if(motion_valid && ({1'b0,dx}+{2'b0,dy}<=96)) begin
                        vx=$signed({1'b0,candidate_x})-$signed({1'b0,roi_x0});
                        vy=$signed({1'b0,candidate_y})-$signed({1'b0,roi_y0});
                        velocity_x<=(vx>16)?16:((vx< -16)?-16:vx);
                        velocity_y<=(vy>16)?16:((vy< -16)?-16:vy);
                        roi_x0<=candidate_x; roi_y0<=candidate_y;
                    end else if(!motion_valid) begin
                        nx=$signed({1'b0,roi_x0})+velocity_x;
                        ny=$signed({1'b0,roi_y0})+velocity_y;
                        roi_x0<=clamp_x(nx); roi_y0<=clamp_y(ny);
                        velocity_x<=velocity_x/2; velocity_y<=velocity_y/2;
                    end
                end else if(!roi_hold && !label_valid) begin
                    if(mode==SEARCH) begin
                        if(proposal_allowed) begin
                            roi_x0<=proposal_x; roi_y0<=proposal_y;
                            proposal_pending<=0; mode<=VERIFY;
                            samples<=0; hits<=0; step_pending<=0;
                        end else if(step_pending) begin
                            roi_x0<=scan_x(scan_col); roi_y0<=scan_y(scan_row);
                            step_pending<=0;
                            if(scan_col==5) begin
                                scan_col<=0; scan_row<=scan_row+1'b1;
                                // Revisit a rejected location after one full
                                // scan, not after a one-frame motion gap.
                                if(scan_row==3) rejected_valid<=0;
                            end else scan_col<=scan_col+1'b1;
                        end
                    end else if(mode==VERIFY && motion_valid && ({1'b0,dx}+{2'b0,dy}<=64)) begin
                        roi_x0<=candidate_x; roi_y0<=candidate_y;
                    end
                end
            end

        end
    end
endmodule
