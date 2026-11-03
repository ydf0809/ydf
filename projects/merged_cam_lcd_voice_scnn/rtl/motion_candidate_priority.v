`timescale 1ns / 1ps

// Soft ranking of two spatially separate frame-difference candidates.
// Coordinates are in the 300x200 detector image (half the display preview).
// Eight consecutive observations, >=24 samples displacement on one axis (48 display
// pixels), >=3 meaningful steps and net/path >=1/2 identify coherent travel.
// Small jitter and two-position flicker get no bonus. Without a mature moving
// candidate, retain the original strongest-candidate choice.
module motion_candidate_priority #(
    parameter integer HISTORY = 8,
    parameter integer MIN_DISPLACEMENT = 24,
    parameter integer MIN_STEP = 2,
    parameter integer MIN_MOVING_STEPS = 3,
    parameter integer MAX_STEP = 48
) (
    input wire clk,
    input wire rst_n,
    input wire enable,
    input wire update,
    input wire primary_valid,
    input wire [8:0] primary_x,
    input wire [7:0] primary_y,
    input wire secondary_valid,
    input wire [8:0] secondary_x,
    input wire [7:0] secondary_y,
    output reg result_valid,
    output reg candidate_valid,
    output reg [8:0] candidate_x,
    output reg [7:0] candidate_y,
    output reg selected_secondary,
    output reg motion_preferred
);
    localparam integer COUNT_W = $clog2(HISTORY);
    reg [8:0] x_hist [0:1][0:HISTORY-2];
    reg [7:0] y_hist [0:1][0:HISTORY-2];
    reg [9:0] step_hist [0:1][0:HISTORY-2];
    reg [HISTORY-2:0] move_hist [0:1];
    reg [COUNT_W-1:0] history_count [0:1];
    reg [11:0] path_sum [0:1];
    reg sample_valid [0:1];
    reg [8:0] sample_x [0:1];
    reg [7:0] sample_y [0:1];
    reg restart_history [0:1];
    reg prefer [0:1];
    integer p_distance [0:1];
    integer s_distance [0:1];
    integer new_step [0:1];
    integer new_path [0:1];
    integer net_distance [0:1];
    integer axis_displacement [0:1];
    integer moving_steps [0:1];
    integer p_track, s_track;
    integer t, j, oldest;
    integer st, sj;
    reg primary_moving, secondary_moving;

    function integer distance;
        input [8:0] ax, bx;
        input [7:0] ay, by;
        begin
            distance = ((ax >= bx) ? ax-bx : bx-ax) +
                       ((ay >= by) ? ay-by : by-ay);
        end
    endfunction

    function integer axis_distance;
        input [8:0] ax, bx;
        input [7:0] ay, by;
        integer dx, dy;
        begin
            dx = (ax >= bx) ? ax-bx : bx-ax;
            dy = (ay >= by) ? ay-by : by-ay;
            axis_distance = (dx >= dy) ? dx : dy;
        end
    endfunction

    always @(*) begin
        for (t=0; t<2; t=t+1) begin
            p_distance[t] = 1024;
            s_distance[t] = 1024;
            if (history_count[t] != 0) begin
                p_distance[t] = distance(primary_x, x_hist[t][0], primary_y, y_hist[t][0]);
                s_distance[t] = distance(secondary_x, x_hist[t][0], secondary_y, y_hist[t][0]);
            end
            sample_valid[t] = 0;
            sample_x[t] = 0;
            sample_y[t] = 0;
            restart_history[t] = 1;
            prefer[t] = 0;
            new_step[t] = 0;
            new_path[t] = 0;
            net_distance[t] = 0;
            axis_displacement[t] = 0;
            moving_steps[t] = 0;
        end
        p_track = -1;
        s_track = -1;
        // Associate by position, not strength: changing brightness/strength
        // must not transfer one candidate's trajectory to the other.
        if (primary_valid) begin
            if ((p_distance[0] <= MAX_STEP) && (p_distance[0] <= p_distance[1]))
                p_track = 0;
            else if (p_distance[1] <= MAX_STEP)
                p_track = 1;
        end
        if (secondary_valid) begin
            if ((p_track != 0) && (s_distance[0] <= MAX_STEP) &&
                ((p_track == 1) || (s_distance[0] <= s_distance[1])))
                s_track = 0;
            else if ((p_track != 1) && (s_distance[1] <= MAX_STEP))
                s_track = 1;
        end
        if (primary_valid && (p_track < 0)) p_track = (s_track == 0) ? 1 : 0;
        if (secondary_valid && (s_track < 0)) s_track = (p_track == 0) ? 1 : 0;
        if (primary_valid) begin
            sample_valid[p_track] = 1;
            sample_x[p_track] = primary_x;
            sample_y[p_track] = primary_y;
        end
        if (secondary_valid) begin
            sample_valid[s_track] = 1;
            sample_x[s_track] = secondary_x;
            sample_y[s_track] = secondary_y;
        end
        oldest = 0;
        for (t=0; t<2; t=t+1) begin
            if (sample_valid[t] && (history_count[t] != 0)) begin
                new_step[t] = distance(sample_x[t], x_hist[t][0], sample_y[t], y_hist[t][0]);
                restart_history[t] = (new_step[t] > MAX_STEP);
                if (!restart_history[t]) begin
                    new_path[t] = path_sum[t] + new_step[t];
                    if (history_count[t] == HISTORY-1)
                        new_path[t] = new_path[t] - step_hist[t][HISTORY-2];
                    oldest = history_count[t] - 1;
                    net_distance[t] = distance(sample_x[t], x_hist[t][oldest],
                                               sample_y[t], y_hist[t][oldest]);
                    axis_displacement[t] = axis_distance(sample_x[t], x_hist[t][oldest],
                                                          sample_y[t], y_hist[t][oldest]);
                    moving_steps[t] = (new_step[t] >= MIN_STEP) ? 1 : 0;
                    for (j=0; j<HISTORY-2; j=j+1)
                        moving_steps[t] = moving_steps[t] + move_hist[t][j];
                    prefer[t] = (history_count[t] == HISTORY-1) &&
                                (axis_displacement[t] >= MIN_DISPLACEMENT) &&
                                (moving_steps[t] >= MIN_MOVING_STEPS) &&
                                ((net_distance[t] << 1) >= new_path[t]);
                end
            end
        end
        primary_moving = 0;
        secondary_moving = 0;
        if (p_track >= 0) primary_moving = prefer[p_track];
        if (s_track >= 0) secondary_moving = prefer[s_track];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_valid <= 0;
            candidate_valid <= 0;
            candidate_x <= 0;
            candidate_y <= 0;
            selected_secondary <= 0;
            motion_preferred <= 0;
            for (st=0; st<2; st=st+1) begin
                history_count[st] <= 0;
                move_hist[st] <= 0;
                path_sum[st] <= 0;
                for (sj=0; sj<HISTORY-1; sj=sj+1) begin
                    x_hist[st][sj] <= 0;
                    y_hist[st][sj] <= 0;
                    step_hist[st][sj] <= 0;
                end
            end
        end else begin
            result_valid <= 0;
            if (!enable) begin
                history_count[0] <= 0;
                history_count[1] <= 0;
                candidate_valid <= 0;
                motion_preferred <= 0;
            end else if (update) begin
                result_valid <= 1;
                candidate_valid <= primary_valid || secondary_valid;
                selected_secondary <= secondary_valid && (!primary_valid ||
                                                         (!primary_moving && secondary_moving));
                motion_preferred <= primary_moving || secondary_moving;
                if (secondary_valid && (!primary_valid || (!primary_moving && secondary_moving))) begin
                    candidate_x <= secondary_x;
                    candidate_y <= secondary_y;
                end else begin
                    candidate_x <= primary_x;
                    candidate_y <= primary_y;
                end
                for (st=0; st<2; st=st+1) begin
                    if (!sample_valid[st]) begin
                        history_count[st] <= 0;
                        move_hist[st] <= 0;
                        path_sum[st] <= 0;
                    end else if (restart_history[st]) begin
                        history_count[st] <= 1;
                        x_hist[st][0] <= sample_x[st];
                        y_hist[st][0] <= sample_y[st];
                        move_hist[st] <= 0;
                        path_sum[st] <= 0;
                        for (sj=0; sj<HISTORY-1; sj=sj+1)
                            step_hist[st][sj] <= 0;
                    end else begin
                        if (history_count[st] < HISTORY-1)
                            history_count[st] <= history_count[st] + 1'b1;
                        x_hist[st][0] <= sample_x[st];
                        y_hist[st][0] <= sample_y[st];
                        step_hist[st][0] <= new_step[st];
                        path_sum[st] <= new_path[st];
                        move_hist[st] <= {move_hist[st][HISTORY-3:0], (new_step[st] >= MIN_STEP)};
                        for (sj=1; sj<HISTORY-1; sj=sj+1) begin
                            x_hist[st][sj] <= x_hist[st][sj-1];
                            y_hist[st][sj] <= y_hist[st][sj-1];
                            step_hist[st][sj] <= step_hist[st][sj-1];
                        end
                    end
                end
            end
        end
    end
endmodule
