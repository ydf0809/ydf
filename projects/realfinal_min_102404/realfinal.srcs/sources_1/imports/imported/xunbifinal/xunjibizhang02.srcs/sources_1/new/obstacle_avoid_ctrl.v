module obstacle_avoid_ctrl #(
    parameter integer CLK_FREQ_HZ           = 33_333_333,
    parameter integer MEASURE_PERIOD_MS     = 30,
    parameter integer TRIG_PULSE_US         = 10,
    parameter integer ECHO_TIMEOUT_MS       = 25,
    parameter integer OBSTACLE_ENTER_CM     = 10,
    parameter integer OBSTACLE_EXIT_CM      = 12,
    parameter integer ENTER_CONFIRM_COUNT   = 2,
    parameter integer EXIT_CONFIRM_COUNT    = 2,
    parameter integer AVOID_HOLD_MS         = 100
)(
    input              sys_clk,
    input              rst_n,
    output reg         trig,
    input              echo,
    output reg         avoid_active,
    output reg [7:0]   distance_cm,
    output reg         sample_valid
);

    localparam integer TRIG_TICKS       = (CLK_FREQ_HZ * TRIG_PULSE_US) / 1000000;
    localparam integer PERIOD_TICKS     = (CLK_FREQ_HZ / 1000) * MEASURE_PERIOD_MS;
    localparam integer TIMEOUT_TICKS    = (CLK_FREQ_HZ / 1000) * ECHO_TIMEOUT_MS;
    localparam integer TICKS_PER_CM     = (CLK_FREQ_HZ * 58) / 1000000;
    localparam integer AVOID_HOLD_TICKS = (CLK_FREQ_HZ / 1000) * AVOID_HOLD_MS;

    localparam [1:0] ST_IDLE      = 2'd0;
    localparam [1:0] ST_TRIG      = 2'd1;
    localparam [1:0] ST_WAIT_RISE = 2'd2;
    localparam [1:0] ST_WAIT_FALL = 2'd3;

    reg [1:0]  state;
    reg        echo_d1;
    reg        echo_d2;
    reg        echo_d3;
    reg [31:0] tick_cnt;
    reg [31:0] echo_cnt;
    reg [31:0] hold_cnt;
    reg [3:0]  near_cnt;
    reg [3:0]  far_cnt;

    wire       echo_rise;
    wire [7:0] echo_cm;

    function [7:0] count_to_cm;
        input [31:0] echo_ticks;
        reg   [31:0] dist_value;
        begin
            dist_value = (echo_ticks + (TICKS_PER_CM / 2)) / TICKS_PER_CM;
            if (dist_value > 32'd255)
                count_to_cm = 8'd255;
            else
                count_to_cm = dist_value[7:0];
        end
    endfunction

    assign echo_rise = echo_d2 & ~echo_d3;
    assign echo_cm   = count_to_cm(echo_cnt);

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            echo_d1 <= 1'b0;
            echo_d2 <= 1'b0;
            echo_d3 <= 1'b0;
        end else begin
            echo_d1 <= echo;
            echo_d2 <= echo_d1;
            echo_d3 <= echo_d2;
        end
    end

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            hold_cnt <= 32'd0;
        end else if (avoid_active) begin
            if (hold_cnt < AVOID_HOLD_TICKS)
                hold_cnt <= hold_cnt + 1'b1;
            else
                hold_cnt <= hold_cnt;
        end else begin
            hold_cnt <= 32'd0;
        end
    end

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            trig         <= 1'b0;
            avoid_active <= 1'b0;
            distance_cm  <= 8'd255;
            sample_valid <= 1'b0;
            tick_cnt     <= 32'd0;
            echo_cnt     <= 32'd0;
            near_cnt     <= 4'd0;
            far_cnt      <= 4'd0;
        end else begin
            sample_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    trig     <= 1'b0;
                    echo_cnt <= 32'd0;

                    if (tick_cnt >= PERIOD_TICKS - 1) begin
                        tick_cnt <= 32'd0;
                        trig     <= 1'b1;
                        state    <= ST_TRIG;
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end

                ST_TRIG: begin
                    trig <= 1'b1;

                    if (tick_cnt >= TRIG_TICKS - 1) begin
                        tick_cnt <= 32'd0;
                        trig     <= 1'b0;
                        state    <= ST_WAIT_RISE;
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end

                ST_WAIT_RISE: begin
                    trig <= 1'b0;

                    if (echo_rise || echo_d2) begin
                        tick_cnt <= 32'd0;
                        echo_cnt <= 32'd0;
                        state    <= ST_WAIT_FALL;
                    end else if (tick_cnt >= TIMEOUT_TICKS - 1) begin
                        tick_cnt     <= 32'd0;
                        echo_cnt     <= 32'd0;
                        distance_cm  <= 8'd255;
                        sample_valid <= 1'b1;
                        state        <= ST_IDLE;
                        near_cnt     <= 4'd0;

                        if (avoid_active) begin
                            if (far_cnt < EXIT_CONFIRM_COUNT)
                                far_cnt <= far_cnt + 1'b1;
                            else
                                far_cnt <= far_cnt;

                            if ((far_cnt >= EXIT_CONFIRM_COUNT - 1) && (hold_cnt >= AVOID_HOLD_TICKS))
                                avoid_active <= 1'b0;
                        end else begin
                            far_cnt <= 4'd0;
                        end
                    end else begin
                        tick_cnt <= tick_cnt + 1'b1;
                    end
                end

                ST_WAIT_FALL: begin
                    trig <= 1'b0;

                    if (echo_d2) begin
                        if (echo_cnt >= TIMEOUT_TICKS - 1) begin
                            tick_cnt     <= 32'd0;
                            echo_cnt     <= 32'd0;
                            distance_cm  <= 8'd255;
                            sample_valid <= 1'b1;
                            state        <= ST_IDLE;
                            near_cnt     <= 4'd0;

                            if (avoid_active) begin
                                if (far_cnt < EXIT_CONFIRM_COUNT)
                                    far_cnt <= far_cnt + 1'b1;
                                else
                                    far_cnt <= far_cnt;

                                if ((far_cnt >= EXIT_CONFIRM_COUNT - 1) && (hold_cnt >= AVOID_HOLD_TICKS))
                                    avoid_active <= 1'b0;
                            end else begin
                                far_cnt <= 4'd0;
                            end
                        end else begin
                            echo_cnt <= echo_cnt + 1'b1;
                        end
                    end else begin
                        tick_cnt     <= 32'd0;
                        echo_cnt     <= 32'd0;
                        distance_cm  <= echo_cm;
                        sample_valid <= 1'b1;
                        state        <= ST_IDLE;

                        if (echo_cm > 8'd2 && echo_cm <= OBSTACLE_ENTER_CM) begin
                            far_cnt <= 4'd0;

                            if (near_cnt < ENTER_CONFIRM_COUNT)
                                near_cnt <= near_cnt + 1'b1;
                            else
                                near_cnt <= near_cnt;

                            if (near_cnt >= ENTER_CONFIRM_COUNT - 1)
                                avoid_active <= 1'b1;
                        end else if (echo_cm >= OBSTACLE_EXIT_CM) begin
                            near_cnt <= 4'd0;

                            if (avoid_active) begin
                                if (far_cnt < EXIT_CONFIRM_COUNT)
                                    far_cnt <= far_cnt + 1'b1;
                                else
                                    far_cnt <= far_cnt;

                                if ((far_cnt >= EXIT_CONFIRM_COUNT - 1) && (hold_cnt >= AVOID_HOLD_TICKS))
                                    avoid_active <= 1'b0;
                            end else begin
                                far_cnt <= 4'd0;
                            end
                        end else begin
                            near_cnt <= 4'd0;
                            far_cnt  <= 4'd0;
                        end
                    end
                end

                default: begin
                    state    <= ST_IDLE;
                    trig     <= 1'b0;
                    tick_cnt <= 32'd0;
                    echo_cnt <= 32'd0;
                end
            endcase
        end
    end

endmodule