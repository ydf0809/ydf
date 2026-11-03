// Arbitrate line following, corner turns and obstacle avoidance before motor-command output.
`timescale 1ns / 1ps

module xunbi_core(
    input        sys_clk,
    input        rst_n,
    input        run_en,
    input        track_l2,
    input        track_l1,
    input        track_m,
    input        track_r1,
    input        track_r2,
    output       us_trig,
    input        us_echo,
    output reg signed [7:0] out_m1,
    output reg signed [7:0] out_m2,
    output reg signed [7:0] out_m3,
    output reg signed [7:0] out_m4,
    output reg              cmd_update
);

    localparam integer CLK_FREQ = 33_333_333;
    localparam signed [7:0] SPEED_MAX  = 8'sd20;
    localparam signed [7:0] SPEED_MIN  = -8'sd20;

    localparam integer STARTUP_DELAY_CYCLES = CLK_FREQ / 5;
    localparam integer UPDATE_PERIOD_CYCLES = CLK_FREQ / 100;
    localparam integer REFRESH_PERIOD_TICKS = 10;

    wire                   line_valid;
    wire [4:0]             line_pattern;
    wire signed [7:0]      pid_left_speed;
    wire signed [7:0]      pid_right_speed;
    wire signed [7:0]      corner_left_speed;
    wire signed [7:0]      corner_right_speed;
    wire                   corner_busy;
    wire                   pid_active;
    wire                   pid_search_active;
    wire [4:0]             track_phys = {track_r2, track_r1, track_m, track_l1, track_l2};
    wire                   track_invalid = (track_phys == 5'b00000) || (track_phys == 5'b11111);

    wire                   stop_for_loss = track_invalid & ~corner_busy & ~pid_search_active;
    wire                   avoid_active;
    wire                   pid_run    = run_en & ~corner_busy & ~avoid_active;

    reg signed [7:0] left_cmd;
    reg signed [7:0] right_cmd;
    reg signed [8:0] left_cmd_ext;
    reg signed [8:0] right_cmd_ext;

    reg signed [7:0] motor1_target;
    reg signed [7:0] motor2_target;
    reg signed [7:0] motor3_target;
    reg signed [7:0] motor4_target;

    reg [31:0] startup_cnt;
    reg [31:0] update_cnt;
    reg [3:0]  refresh_tick;
    reg        startup_done;

    wire target_changed;

    function signed [7:0] clamp_speed;
        input signed [8:0] raw_speed;
        begin
            if (raw_speed > SPEED_MAX)
                clamp_speed = SPEED_MAX;
            else if (raw_speed < SPEED_MIN)
                clamp_speed = SPEED_MIN;
            else
                clamp_speed = raw_speed[7:0];
        end
    endfunction

    assign target_changed =
        (out_m1 != motor1_target) ||
        (out_m2 != motor2_target) ||
        (out_m3 != motor3_target) ||
        (out_m4 != motor4_target);

    line_follow_ctrl #(
        .CLK_FREQ_HZ(CLK_FREQ), .SAMPLE_PERIOD_US(500),
        .VALID_CONFIRM_COUNT(2), .STEER_REVERSE(1'b1)
    ) u_line_follow_ctrl (
        .sys_clk(sys_clk), .rst_n(rst_n),
        .track_l2(track_l2), .track_l1(track_l1), .track_m(track_m), .track_r1(track_r1), .track_r2(track_r2),
        .line_pattern(line_pattern), .line_valid(line_valid), .line_lost(),
        .left_speed(), .right_speed()
    );

    line_pid_ctrl #(
        .CLK_FREQ_HZ  (CLK_FREQ),
        .PERIOD_MS    (10),
        .STEER_REVERSE(1'b1),
        .SPEED_BASE   (8'sd18),
        .SPEED_MAX    (SPEED_MAX),
        .TURN_MAX     (8'sd20),
        .CURVE_SHIFT  (1),
        .KP_SHIFT     (4),
        .ERR_DEADBAND (64),
        .KI_SHIFT     (0),
        .KD_SHIFT     (0),
        .LOST_CONFIRM (2),
        .SEARCH_EN    (1),
        .SEARCH_MS    (320),
        .SEARCH_SWING_MS(80),
        .SEARCH_SPEED (8'sd16)
    ) u_line_pid_ctrl (
        .clk(sys_clk), .rst_n(rst_n),
        .run_en(pid_run),
        .track_pat(line_pattern), .line_valid(line_valid & ~track_invalid),
        .left_speed(pid_left_speed), .right_speed(pid_right_speed),
        .active(pid_active), .search_active(pid_search_active)
    );

    corner_turn #(
        .CLK_FREQ_HZ  (CLK_FREQ),
        .FORWARD_MS   (1000),
        .SPIN_MS      (700),
        .MIN_SPIN_MS  (250),
        .TIMEOUT_MS   (2000),
        .COOLDOWN_MS  (500),
        .CONFIRM_MS   (3),
        .FORWARD_SPEED(8'sd16),
        .SPIN_SPEED   (8'sd20),
        .STOP_ON_LINE (1)
    ) u_corner_turn (
        .clk(sys_clk), .rst_n(rst_n), .run_en(run_en),
        .pat(track_phys), .line_valid(line_valid),
        .pid_left(pid_left_speed), .pid_right(pid_right_speed),
        .out_left(corner_left_speed), .out_right(corner_right_speed),
        .busy(corner_busy)
    );

    obstacle_avoid_ctrl #(
        .CLK_FREQ_HZ(CLK_FREQ), .MEASURE_PERIOD_MS(30),
        .TRIG_PULSE_US(10), .ECHO_TIMEOUT_MS(25),
        .OBSTACLE_ENTER_CM(10), .OBSTACLE_EXIT_CM(12),
        .ENTER_CONFIRM_COUNT(2), .EXIT_CONFIRM_COUNT(2), .AVOID_HOLD_MS(100)
    ) u_obstacle_avoid_ctrl (
        .sys_clk(sys_clk), .rst_n(rst_n),
        .trig(us_trig), .echo(us_echo),
        .avoid_active(avoid_active), .distance_cm(), .sample_valid()
    );

    localparam integer RAMP_TICKS = 32;
    reg [19:0] ramp_div;
    reg [5:0]  ramp_cnt;
    reg        avoid_d;

    wire ramp_div_tick = (ramp_div >= 20'd333333);
    wire avoid_fall    = avoid_d & ~avoid_active;

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            ramp_div <= 20'd0;
            ramp_cnt <= 6'd0;
            avoid_d  <= 1'b0;
        end else begin
            avoid_d  <= avoid_active;
            ramp_div <= ramp_div_tick ? 20'd0 : ramp_div + 1'b1;

            if (avoid_active)
                ramp_cnt <= 6'd0;
            else if (avoid_fall)
                ramp_cnt <= 6'd1;
            else if (ramp_div_tick && ramp_cnt != 6'd0 && ramp_cnt < RAMP_TICKS)
                ramp_cnt <= ramp_cnt + 1'b1;
        end
    end

    wire [14:0] ramp_prod  = ramp_cnt * SPEED_MAX;
    wire signed [7:0] ramp_limit = (ramp_cnt == 6'd0) ? SPEED_MAX : (ramp_prod >> 5);

    always @(*) begin
        if (avoid_active || stop_for_loss) begin
            left_cmd  = 8'sd0;
            right_cmd = 8'sd0;
        end else if (corner_busy) begin
            left_cmd  = corner_left_speed;
            right_cmd = corner_right_speed;
        end else if (pid_active) begin
            left_cmd  = corner_left_speed;
            right_cmd = corner_right_speed;
        end else begin
            left_cmd  = 8'sd0;
            right_cmd = 8'sd0;
        end

        if (ramp_cnt != 6'd0) begin
            if (left_cmd > ramp_limit)
                left_cmd = ramp_limit;
            else if (left_cmd < -ramp_limit)
                left_cmd = -ramp_limit;

            if (right_cmd > ramp_limit)
                right_cmd = ramp_limit;
            else if (right_cmd < -ramp_limit)
                right_cmd = -ramp_limit;
        end

        left_cmd_ext  = {left_cmd[7], left_cmd};
        right_cmd_ext = {right_cmd[7], right_cmd};

        motor1_target = clamp_speed(left_cmd_ext);
        motor2_target = clamp_speed(-left_cmd_ext);
        motor3_target = clamp_speed(-right_cmd_ext);
        motor4_target = clamp_speed(right_cmd_ext);
    end

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            startup_cnt    <= 32'd0; update_cnt <= 32'd0; refresh_tick <= 4'd0;
            startup_done   <= 1'b0; cmd_update <= 1'b0;
            out_m1 <= 8'sd0; out_m2 <= 8'sd0; out_m3 <= 8'sd0; out_m4 <= 8'sd0;
        end else begin
            cmd_update <= 1'b0;
            if (!startup_done) begin
                if (startup_cnt >= STARTUP_DELAY_CYCLES - 1) begin
                    startup_cnt  <= 32'd0; update_cnt <= 32'd0; refresh_tick <= 4'd0;
                    startup_done <= 1'b1;
                    out_m1 <= motor1_target; out_m2 <= motor2_target; out_m3 <= motor3_target; out_m4 <= motor4_target;
                    cmd_update <= 1'b1;
                end else begin
                    startup_cnt <= startup_cnt + 1'b1;
                end
            end else if (stop_for_loss && target_changed) begin

                out_m1 <= motor1_target; out_m2 <= motor2_target;
                out_m3 <= motor3_target; out_m4 <= motor4_target;
                cmd_update <= 1'b1;
                update_cnt <= 32'd0;
                refresh_tick <= 4'd0;
            end else begin
                if (update_cnt >= UPDATE_PERIOD_CYCLES - 1) begin
                    update_cnt <= 32'd0;
                    if (target_changed || (refresh_tick >= REFRESH_PERIOD_TICKS - 1)) begin
                        out_m1 <= motor1_target; out_m2 <= motor2_target; out_m3 <= motor3_target; out_m4 <= motor4_target;
                        cmd_update <= 1'b1; refresh_tick <= 4'd0;
                    end else begin
                        refresh_tick <= refresh_tick + 1'b1;
                    end
                end else begin
                    update_cnt <= update_cnt + 1'b1;
                end
            end
        end
    end
endmodule
