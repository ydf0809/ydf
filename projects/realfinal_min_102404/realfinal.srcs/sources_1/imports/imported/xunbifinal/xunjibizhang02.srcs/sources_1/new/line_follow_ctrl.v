module line_follow_ctrl #(
    parameter integer CLK_FREQ_HZ          = 33_333_333,
    parameter integer SAMPLE_PERIOD_US     = 500,
    parameter integer VALID_CONFIRM_COUNT  = 2,
    parameter         STEER_REVERSE        = 1'b0,
    parameter signed [7:0] SPEED_FORWARD   = 8'sd16,
    parameter signed [7:0] SPEED_SOFT_IN   = 8'sd10,
    parameter signed [7:0] SPEED_SOFT_OUT  = 8'sd18,
    parameter signed [7:0] SPEED_HARD_IN   = 8'sd4,
    parameter signed [7:0] SPEED_HARD_OUT  = 8'sd20
)(
    input                    sys_clk,
    input                    rst_n,
    input                    track_l2,
    input                    track_l1,
    input                    track_m,
    input                    track_r1,
    input                    track_r2,
    output reg [4:0]         line_pattern,
    output reg               line_valid,
    output reg               line_lost,
    output reg signed [7:0]  left_speed,
    output reg signed [7:0]  right_speed
);

    localparam integer SAMPLE_TICKS = (CLK_FREQ_HZ / 1000000) * SAMPLE_PERIOD_US;

    reg [31:0] sample_cnt;
    reg [4:0]  raw_prev;
    reg [4:0]  candidate_pattern;
    reg        candidate_valid;
    reg [3:0]  valid_cnt;
    reg [4:0]  steer_pattern;

    wire [4:0] raw_pattern;

    assign raw_pattern = {track_l2, track_l1, track_m, track_r1, track_r2};

    function is_valid_pattern;
        input [4:0] pattern;
        begin
            if (pattern == 5'b00000 || pattern == 5'b11111 )
                is_valid_pattern = 1'b0;
            else
                is_valid_pattern = 1'b1;
        end
    endfunction

    always @(*) begin
        candidate_pattern = line_pattern;

        if ({raw_prev[4], raw_pattern[4]} == 2'b11)
            candidate_pattern[4] = 1'b1;
        else if ({raw_prev[4], raw_pattern[4]} == 2'b00)
            candidate_pattern[4] = 1'b0;

        if ({raw_prev[3], raw_pattern[3]} == 2'b11)
            candidate_pattern[3] = 1'b1;
        else if ({raw_prev[3], raw_pattern[3]} == 2'b00)
            candidate_pattern[3] = 1'b0;

        if ({raw_prev[2], raw_pattern[2]} == 2'b11)
            candidate_pattern[2] = 1'b1;
        else if ({raw_prev[2], raw_pattern[2]} == 2'b00)
            candidate_pattern[2] = 1'b0;

        if ({raw_prev[1], raw_pattern[1]} == 2'b11)
            candidate_pattern[1] = 1'b1;
        else if ({raw_prev[1], raw_pattern[1]} == 2'b00)
            candidate_pattern[1] = 1'b0;

        if ({raw_prev[0], raw_pattern[0]} == 2'b11)
            candidate_pattern[0] = 1'b1;
        else if ({raw_prev[0], raw_pattern[0]} == 2'b00)
            candidate_pattern[0] = 1'b0;

        candidate_valid = is_valid_pattern(candidate_pattern);
    end

    always @(*) begin
        if (STEER_REVERSE)
            steer_pattern = {line_pattern[0], line_pattern[1], line_pattern[2], line_pattern[3], line_pattern[4]};
        else
            steer_pattern = line_pattern;
    end

    reg signed [4:0] steer_error;

    always @(*) begin
        left_speed  = 8'sd0;
        right_speed = 8'sd0;
        steer_error = 5'sd0;

        if (steer_pattern[4]) steer_error = steer_error - 5'sd4;
        if (steer_pattern[3]) steer_error = steer_error - 5'sd2;
        if (steer_pattern[1]) steer_error = steer_error + 5'sd2;
        if (steer_pattern[0]) steer_error = steer_error + 5'sd4;

        if (steer_error <= -5'sd4) begin
            left_speed  = SPEED_HARD_IN;
            right_speed = SPEED_HARD_OUT;
        end else if (steer_error < 0) begin
            left_speed  = SPEED_SOFT_IN;
            right_speed = SPEED_SOFT_OUT;
        end else if (steer_error >= 5'sd4) begin
            left_speed  = SPEED_HARD_OUT;
            right_speed = SPEED_HARD_IN;
        end else if (steer_error > 0) begin
            left_speed  = SPEED_SOFT_OUT;
            right_speed = SPEED_SOFT_IN;
        end else begin
            left_speed  = SPEED_FORWARD;
            right_speed = SPEED_FORWARD;
        end
    end

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_cnt       <= 32'd0;
            raw_prev         <= 5'd0;
            line_pattern     <= 5'd0;
            valid_cnt        <= 4'd0;
            line_valid       <= 1'b0;
            line_lost        <= 1'b1;
        end else begin
            if (sample_cnt >= SAMPLE_TICKS - 1) begin
                sample_cnt   <= 32'd0;
                raw_prev     <= raw_pattern;
                line_pattern <= candidate_pattern;

                if (candidate_valid) begin
                    line_lost <= 1'b0;

                    if (valid_cnt < VALID_CONFIRM_COUNT)
                        valid_cnt <= valid_cnt + 1'b1;
                    else
                        valid_cnt <= valid_cnt;

                    if ((valid_cnt + 1'b1) >= VALID_CONFIRM_COUNT)
                        line_valid <= 1'b1;
                    else
                        line_valid <= 1'b0;
                end else begin
                    valid_cnt  <= 4'd0;
                    line_valid <= 1'b0;
                    line_lost  <= 1'b1;
                end
            end else begin
                sample_cnt <= sample_cnt + 1'b1;
            end
        end
    end

endmodule
