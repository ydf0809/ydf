// Execute arm pose sequences; stop and home requests are handled by the shared servo packet path.
module arm_pick_place_once_top #(
    parameter integer CLK_HZ = 33300000,
    parameter integer STARTUP_WAIT_MS = 10000,
    parameter integer TCON_ACTIVE_HIGH = 1,
    parameter integer LOOP_EN = 0
)(
    input  wire sys_clk,
    input  wire rst_n,
    input  wire run_en,
    input  wire stop_i,
    input  wire home_i,
    output wire arm_uart,
    output wire tcon
);

    localparam [7:0] CMD_MOVE_TIME_WAIT_WRITE = 8'd7;
    localparam [7:0] CMD_MOVE_START           = 8'd11;
    localparam [7:0] CMD_MOVE_STOP            = 8'd12;
    localparam [7:0] LEN_MOVE_TIME_WAIT_WRITE = 8'd7;
    localparam [7:0] LEN_MOVE_START           = 8'd3;
    localparam [7:0] LEN_MOVE_STOP            = 8'd3;
    localparam [7:0] BROADCAST_ID             = 8'd254;

    localparam integer MS_TICK = CLK_HZ / 1000;
    localparam integer STARTUP_TICKS = STARTUP_WAIT_MS * MS_TICK;

    localparam [3:0] S_POWERUP    = 4'd0;
    localparam [3:0] S_PREP_SERVO = 4'd1;
    localparam [3:0] S_WAIT_SERVO = 4'd2;
    localparam [3:0] S_PREP_START = 4'd3;
    localparam [3:0] S_WAIT_START = 4'd4;
    localparam [3:0] S_HOLD       = 4'd5;
    localparam [3:0] S_DONE       = 4'd6;
    localparam [3:0] S_STOP_PREP  = 4'd7;
    localparam [3:0] S_STOP_WAIT  = 4'd8;

    reg [3:0] state;
    reg [3:0] step_idx;
    reg [2:0] servo_idx;

    reg [31:0] startup_cnt;
    reg [31:0] hold_cnt;

    reg        send_req;
    reg        home_only;

    reg [7:0] servo_id_r;
    reg [7:0] frame_len_r;
    reg [7:0] cmd_r;
    reg [2:0] param_count_r;
    reg [7:0] param1_r;
    reg [7:0] param2_r;
    reg [7:0] param3_r;
    reg [7:0] param4_r;

    reg [15:0] pose_pos_current;
    reg [15:0] step_time_current;

    wire [31:0] hold_limit_ticks;
    wire tx_oe;
    wire pkt_busy;
    wire pkt_done;

    assign tcon = TCON_ACTIVE_HIGH ? tx_oe : ~tx_oe;
    assign hold_limit_ticks = step_time_current * MS_TICK;

    always @(*) begin
        case (step_idx)
            4'd1:  step_time_current = 16'd1000;
            4'd2:  step_time_current = 16'd1000;
            4'd3:  step_time_current = 16'd1000;
            4'd4:  step_time_current = 16'd1000;
            4'd5:  step_time_current = 16'd500;
            4'd6:  step_time_current = 16'd1000;
            4'd7:  step_time_current = 16'd1000;
            4'd8:  step_time_current = 16'd1000;
            4'd9:  step_time_current = 16'd1000;
            4'd10: step_time_current = 16'd500;
            4'd11: step_time_current = 16'd1000;
            4'd12: step_time_current = 16'd1000;
            default: step_time_current = 16'd1000;
        endcase
    end

    always @(*) begin
        pose_pos_current = 16'd500;

        case (step_idx)
            4'd1: begin
                case (servo_idx)
                    3'd1: pose_pos_current = 16'd220;
                    3'd2: pose_pos_current = 16'd500;
                    3'd3: pose_pos_current = 16'd700;
                    3'd4: pose_pos_current = 16'd300;
                    3'd5: pose_pos_current = 16'd250;
                    3'd6: pose_pos_current = 16'd500;
                    default: pose_pos_current = 16'd500;
                endcase
            end

            4'd2: begin
                case (servo_idx)
                    3'd1: pose_pos_current = 16'd220;
                    3'd2: pose_pos_current = 16'd500;
                    3'd3: pose_pos_current = 16'd700;
                    3'd4: pose_pos_current = 16'd300;
                    3'd5: pose_pos_current = 16'd250;
                    3'd6: pose_pos_current = 16'd750;
                    default: pose_pos_current = 16'd500;
                endcase
            end

            4'd3: begin
                case (servo_idx)
                    3'd1: pose_pos_current = 16'd220;
                    3'd2: pose_pos_current = 16'd500;
                    3'd3: pose_pos_current = 16'd700;
                    3'd4: pose_pos_current = 16'd300;
                    3'd5: pose_pos_current = 16'd700;
                    3'd6: pose_pos_current = 16'd750;
                    default: pose_pos_current = 16'd500;
                endcase
            end

            4'd4: begin
                case (servo_idx)
                    3'd1: pose_pos_current = 16'd220;
                    3'd2: pose_pos_current = 16'd500;
                    3'd3: pose_pos_current = 16'd680;
                    3'd4: pose_pos_current = 16'd250;
                    3'd5: pose_pos_current = 16'd700;
                    3'd6: pose_pos_current = 16'd750;
                    default: pose_pos_current = 16'd500;
                endcase
            end

            4'd5: begin
                case (servo_idx)
                    3'd1: pose_pos_current = 16'd500;
                    3'd2: pose_pos_current = 16'd500;
                    3'd3: pose_pos_current = 16'd680;
                    3'd4: pose_pos_current = 16'd250;
                    3'd5: pose_pos_current = 16'd700;
                    3'd6: pose_pos_current = 16'd750;
                    default: pose_pos_current = 16'd500;
                endcase
            end

            4'd6: begin
                case (servo_idx)
                    3'd1: pose_pos_current = 16'd500;
                    3'd2: pose_pos_current = 16'd500;
                    3'd3: pose_pos_current = 16'd700;
                    3'd4: pose_pos_current = 16'd300;
                    3'd5: pose_pos_current = 16'd250;
                    3'd6: pose_pos_current = 16'd750;
                    default: pose_pos_current = 16'd500;
                endcase
            end

            4'd7: begin
                case (servo_idx)
                    3'd1: pose_pos_current = 16'd500;
                    3'd2: pose_pos_current = 16'd500;
                    3'd3: pose_pos_current = 16'd700;
                    3'd4: pose_pos_current = 16'd300;
                    3'd5: pose_pos_current = 16'd250;
                    3'd6: pose_pos_current = 16'd210;
                    default: pose_pos_current = 16'd500;
                endcase
            end

            4'd8: begin
                case (servo_idx)
                    3'd1: pose_pos_current = 16'd500;
                    3'd2: pose_pos_current = 16'd500;
                    3'd3: pose_pos_current = 16'd800;
                    3'd4: pose_pos_current = 16'd350;
                    3'd5: pose_pos_current = 16'd700;
                    3'd6: pose_pos_current = 16'd210;
                    default: pose_pos_current = 16'd500;
                endcase
            end

            4'd9: begin
                case (servo_idx)
                    3'd1: pose_pos_current = 16'd500;
                    3'd2: pose_pos_current = 16'd500;
                    3'd3: pose_pos_current = 16'd700;
                    3'd4: pose_pos_current = 16'd270;
                    3'd5: pose_pos_current = 16'd700;
                    3'd6: pose_pos_current = 16'd210;
                    default: pose_pos_current = 16'd500;
                endcase
            end

            4'd10: begin
                case (servo_idx)
                    3'd1: pose_pos_current = 16'd220;
                    3'd2: pose_pos_current = 16'd500;
                    3'd3: pose_pos_current = 16'd700;
                    3'd4: pose_pos_current = 16'd270;
                    3'd5: pose_pos_current = 16'd700;
                    3'd6: pose_pos_current = 16'd210;
                    default: pose_pos_current = 16'd500;
                endcase
            end

            4'd11: begin
                case (servo_idx)
                    3'd1: pose_pos_current = 16'd220;
                    3'd2: pose_pos_current = 16'd500;
                    3'd3: pose_pos_current = 16'd700;
                    3'd4: pose_pos_current = 16'd300;
                    3'd5: pose_pos_current = 16'd250;
                    3'd6: pose_pos_current = 16'd210;
                    default: pose_pos_current = 16'd500;
                endcase
            end

            4'd12: begin
                case (servo_idx)
                    3'd1: pose_pos_current = 16'd220;
                    3'd2: pose_pos_current = 16'd500;
                    3'd3: pose_pos_current = 16'd700;
                    3'd4: pose_pos_current = 16'd300;
                    3'd5: pose_pos_current = 16'd250;
                    3'd6: pose_pos_current = 16'd500;
                    default: pose_pos_current = 16'd500;
                endcase
            end

            default: begin
                pose_pos_current = 16'd500;
            end
        endcase
    end

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_POWERUP;
            step_idx      <= 4'd1;
            servo_idx     <= 3'd1;
            startup_cnt   <= 32'd0;
            hold_cnt      <= 32'd0;
            send_req      <= 1'b0;
            home_only     <= 1'b0;
            servo_id_r    <= 8'd0;
            frame_len_r   <= 8'd0;
            cmd_r         <= 8'd0;
            param_count_r <= 3'd0;
            param1_r      <= 8'd0;
            param2_r      <= 8'd0;
            param3_r      <= 8'd0;
            param4_r      <= 8'd0;
        end else begin
            send_req <= 1'b0;

            if (stop_i) begin

                home_only <= 1'b0;
                state     <= S_STOP_PREP;
            end
            else if (home_i && !run_en) begin

                step_idx  <= 4'd1;
                servo_idx <= 3'd1;
                hold_cnt  <= 32'd0;
                home_only <= 1'b1;
                state     <= S_PREP_SERVO;
            end
            else if (!run_en && !home_only &&
                     (state != S_STOP_PREP) && (state != S_STOP_WAIT)) begin

                state       <= S_POWERUP;
                startup_cnt <= 32'd0;
                hold_cnt    <= 32'd0;
                step_idx    <= 4'd1;
                servo_idx   <= 3'd1;
            end
            else case (state)
                S_POWERUP: begin
                    step_idx  <= 4'd1;
                    servo_idx <= 3'd1;
                    if (startup_cnt < STARTUP_TICKS - 1) begin
                        startup_cnt <= startup_cnt + 1'b1;
                    end else begin
                        startup_cnt <= 32'd0;
                        state       <= S_PREP_SERVO;
                    end
                end

                S_PREP_SERVO: begin
                    if (!pkt_busy) begin
                        servo_id_r    <= {5'd0, servo_idx};
                        frame_len_r   <= LEN_MOVE_TIME_WAIT_WRITE;
                        cmd_r         <= CMD_MOVE_TIME_WAIT_WRITE;
                        param_count_r <= 3'd4;
                        param1_r      <= pose_pos_current[7:0];
                        param2_r      <= pose_pos_current[15:8];
                        param3_r      <= step_time_current[7:0];
                        param4_r      <= step_time_current[15:8];
                        send_req      <= 1'b1;
                        state         <= S_WAIT_SERVO;
                    end
                end

                S_WAIT_SERVO: begin
                    if (pkt_done) begin
                        if (servo_idx == 3'd6) begin
                            state <= S_PREP_START;
                        end else begin
                            servo_idx <= servo_idx + 1'b1;
                            state     <= S_PREP_SERVO;
                        end
                    end
                end

                S_PREP_START: begin
                    if (!pkt_busy) begin
                        servo_id_r    <= BROADCAST_ID;
                        frame_len_r   <= LEN_MOVE_START;
                        cmd_r         <= CMD_MOVE_START;
                        param_count_r <= 3'd0;
                        param1_r      <= 8'd0;
                        param2_r      <= 8'd0;
                        param3_r      <= 8'd0;
                        param4_r      <= 8'd0;
                        send_req      <= 1'b1;
                        state         <= S_WAIT_START;
                    end
                end

                S_WAIT_START: begin
                    if (pkt_done) begin
                        hold_cnt <= 32'd0;
                        if (home_only) begin
                            home_only <= 1'b0;
                            state     <= S_POWERUP;
                        end
                        else
                            state <= S_HOLD;
                    end
                end

                S_HOLD: begin
                    if (hold_cnt < hold_limit_ticks - 1) begin
                        hold_cnt <= hold_cnt + 1'b1;
                    end else begin
                        hold_cnt  <= 32'd0;
                        servo_idx <= 3'd1;

                        if (step_idx == 4'd12) begin
                            if (LOOP_EN) begin
                                step_idx <= 4'd1;
                                state    <= S_PREP_SERVO;
                            end else begin
                                state    <= S_DONE;
                            end
                        end else begin
                            step_idx <= step_idx + 1'b1;
                            state    <= S_PREP_SERVO;
                        end
                    end
                end

                S_DONE: begin
                    state <= S_DONE;
                end

                S_STOP_PREP: begin
                    if (!pkt_busy) begin
                        servo_id_r    <= BROADCAST_ID;
                        frame_len_r   <= LEN_MOVE_STOP;
                        cmd_r         <= CMD_MOVE_STOP;
                        param_count_r <= 3'd0;
                        param1_r      <= 8'd0;
                        param2_r      <= 8'd0;
                        param3_r      <= 8'd0;
                        param4_r      <= 8'd0;
                        send_req      <= 1'b1;
                        state         <= S_STOP_WAIT;
                    end
                end

                S_STOP_WAIT: begin
                    if (pkt_done) begin
                        hold_cnt <= 32'd0;
                        state    <= S_POWERUP;
                    end
                end

                default: begin
                    state <= S_POWERUP;
                end
            endcase
        end
    end

    bus_servo_packet_tx #(
        .CLK_HZ(CLK_HZ),
        .BAUD(115200)
    ) u_bus_servo_packet_tx (
        .sys_clk(sys_clk),
        .rst_n(rst_n),
        .send_req(send_req),
        .servo_id(servo_id_r),
        .frame_len(frame_len_r),
        .cmd(cmd_r),
        .param_count(param_count_r),
        .param1(param1_r),
        .param2(param2_r),
        .param3(param3_r),
        .param4(param4_r),
        .txd(arm_uart),
        .tx_oe(tx_oe),
        .busy(pkt_busy),
        .done(pkt_done)
    );

endmodule
