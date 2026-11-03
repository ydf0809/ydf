`timescale 1ns / 1ps

// Image-position tracker for servos 4/3 (cascaded pitch) and 6 (yaw).
//
// target_pitch and target_yaw are the target box CENTRE coordinates after
// converting the upper camera image into the operator-visible LCD orientation.
// Box width and height are not used by the controller. Servo 4 is the primary pitch axis.
// Servo 3 starts adjusting only after servo 4 reaches its configured limit
// while the target still drives farther in the same direction.
// Servos 1/2/5 receive one fixed startup pose and never move while tracking.
//
// home_i: a one-cycle pulse asking for the air-defence initial pose again. It is
// latched, so a pulse that arrives mid-packet is not lost; the six pose writes
// are sent with HOME_TIME_MS (the same 1000 ms the pick-place home uses) while
// normal tracking updates keep MOVE_TIME_MS. Saying "air defence" again while
// already in air-defence mode re-runs this.
module compat_arm_red_track #(
    parameter integer CLK_HZ           = 33_333_333,
    parameter integer BAUD             = 115_200,
    parameter integer CENTER_PITCH     = 150,
    parameter integer CENTER_YAW       = 200,
    parameter integer PITCH_MIN        = 200,
    parameter integer PITCH_MAX        = 400,
    parameter integer YAW_MIN          = 100,
    parameter integer YAW_MAX          = 850,
    parameter integer PITCH3_MIN       = 600,
    parameter integer PITCH3_MAX       = 800,
    parameter integer PITCH_CASCADE_LOW  = 200,
    parameter integer PITCH_CASCADE_HIGH = 400,
    parameter integer POS4_INIT        = 300,
    parameter integer POS6_INIT        = 500,
    parameter integer POS1_AIR         = 220,
    parameter integer POS2_AIR         = 500,
    parameter integer POS3_INIT        = 700,
    parameter integer POS5_AIR         = 400,
    parameter integer DEADBAND         = 16,
    parameter integer KP_SHIFT         = 3,
    parameter integer STEP_MAX         = 20,
    parameter integer MOVE_TIME_MS     = 100,
    parameter integer HOME_TIME_MS     = 1000,
    parameter integer UPDATE_PERIOD_MS = 100,
    parameter integer PITCH_SIGN       = 1,
    parameter integer PITCH3_SIGN      = -1,
    parameter integer YAW_SIGN         = 1
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [10:0] target_pitch,
    input  wire [10:0] target_yaw,
    input  wire        target_valid,
    input  wire        home_i,          // one pulse: send the initial pose again

    output wire        arm_uart,
    output wire        tx_oe,

    output wire [15:0] dbg_move_time,
    output wire [15:0] dbg_pos3,
    output wire [15:0] dbg_pos4,
    output wire [15:0] dbg_pos6,
    output wire [7:0]  dbg_servo_id,
    output wire        dbg_send,
    output wire        dbg_busy
);

    localparam [7:0] CMD_MOVE_TIME_WAIT_WRITE = 8'd7;
    localparam [7:0] CMD_MOVE_START           = 8'd11;
    localparam [7:0] LEN_MOVE_TIME_WAIT_WRITE = 8'd7;
    localparam [7:0] LEN_MOVE_START           = 8'd3;
    localparam [7:0] BROADCAST_ID             = 8'd254;

    localparam [15:0] MOVE_TIME_16 = MOVE_TIME_MS;
    localparam [15:0] HOME_TIME_16 = HOME_TIME_MS;

    localparam [3:0] S_IDLE  = 4'd0;
    localparam [3:0] S_WAIT1 = 4'd1;
    localparam [3:0] S_WAIT2 = 4'd2;
    localparam [3:0] S_WAIT3 = 4'd3;
    localparam [3:0] S_WAIT5 = 4'd4;
    localparam [3:0] S_WAIT6 = 4'd5;
    localparam [3:0] S_WAIT4 = 4'd6;
    localparam [3:0] S_START = 4'd7;
    localparam [3:0] S_WAIT3_TRACK = 4'd8;

    (* ASYNC_REG = "TRUE" *) reg [10:0] pitch_meta, yaw_meta;
    (* ASYNC_REG = "TRUE" *) reg [10:0] pitch_sync, yaw_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pitch_meta <= CENTER_PITCH;
            yaw_meta   <= CENTER_YAW;
            pitch_sync <= CENTER_PITCH;
            yaw_sync   <= CENTER_YAW;
        end else begin
            pitch_meta <= target_pitch;
            yaw_meta   <= target_yaw;
            pitch_sync <= pitch_meta;
            yaw_sync   <= yaw_meta;
        end
    end

    wire signed [11:0] pitch_error =
        $signed({1'b0, pitch_sync}) - $signed(CENTER_PITCH);
    wire signed [11:0] yaw_error =
        $signed({1'b0, yaw_sync}) - $signed(CENTER_YAW);

    wire signed [11:0] pitch_unsigned_step =
        (pitch_error > DEADBAND) ? (pitch_error >>> KP_SHIFT) :
        (pitch_error < -DEADBAND) ? (pitch_error >>> KP_SHIFT) :
        12'sd0;
    wire signed [11:0] yaw_unsigned_step =
        (yaw_error > DEADBAND) ? (yaw_error >>> KP_SHIFT) :
        (yaw_error < -DEADBAND) ? (yaw_error >>> KP_SHIFT) :
        12'sd0;
    wire signed [11:0] pitch_step =
        (PITCH_SIGN > 0) ? pitch_unsigned_step : -pitch_unsigned_step;
    wire signed [11:0] yaw_step =
        (YAW_SIGN > 0) ? yaw_unsigned_step : -yaw_unsigned_step;

    function signed [5:0] clamp_step;
        input signed [11:0] value;
        begin
            if (value > STEP_MAX)
                clamp_step = STEP_MAX;
            else if (value < -STEP_MAX)
                clamp_step = -STEP_MAX;
            else
                clamp_step = value[5:0];
        end
    endfunction

    function [15:0] clamp_pitch;
        input signed [16:0] value;
        begin
            if (value < PITCH_MIN)
                clamp_pitch = PITCH_MIN;
            else if (value > PITCH_MAX)
                clamp_pitch = PITCH_MAX;
            else
                clamp_pitch = value[15:0];
        end
    endfunction

    function [15:0] clamp_yaw;
        input signed [16:0] value;
        begin
            if (value < YAW_MIN)
                clamp_yaw = YAW_MIN;
            else if (value > YAW_MAX)
                clamp_yaw = YAW_MAX;
            else
                clamp_yaw = value[15:0];
        end
    endfunction

    function [15:0] clamp_pitch3;
        input signed [16:0] value;
        begin
            if (value < PITCH3_MIN)
                clamp_pitch3 = PITCH3_MIN;
            else if (value > PITCH3_MAX)
                clamp_pitch3 = PITCH3_MAX;
            else
                clamp_pitch3 = value[15:0];
        end
    endfunction

    wire signed [5:0] pitch_delta = clamp_step(pitch_step);
    wire signed [5:0] yaw_delta   = clamp_step(yaw_step);

    reg [15:0] pos3, pos4, pos6;
    reg        pitch3_active;
    wire signed [16:0] pos4_with_delta =
        $signed({1'b0, pos4}) + $signed({{11{pitch_delta[5]}}, pitch_delta});
    wire signed [16:0] pos6_with_delta =
        $signed({1'b0, pos6}) + $signed({{11{yaw_delta[5]}}, yaw_delta});
    wire [15:0] next_pos4 = clamp_pitch(pos4_with_delta);
    wire [15:0] next_pos6 = clamp_yaw(pos6_with_delta);

    // Servo 3 is a secondary pitch axis. Once it takes over at a servo-4 end
    // stop, servo 4 holds until servo 3 has returned to its 700 home position.
    wire pitch4_cascade_low =
        (pos4 <= PITCH_CASCADE_LOW) && (pitch_step < 0);
    wire pitch4_cascade_high =
        (pos4 >= PITCH_CASCADE_HIGH) && (pitch_step > 0);
    wire pitch3_start =
        !pitch3_active && (pitch4_cascade_low || pitch4_cascade_high);
    wire signed [5:0] pitch3_follow_delta =
        (PITCH3_SIGN > 0) ? pitch_delta : -pitch_delta;
    wire signed [5:0] pitch3_home_delta =
        (pos3 < POS3_INIT) ? STEP_MAX :
        ((pos3 > POS3_INIT) ? -STEP_MAX : 6'sd0);
    wire signed [5:0] pitch3_delta =
        pitch3_active ? ((pitch_delta != 0) ?
                         pitch3_follow_delta : pitch3_home_delta) :
        (pitch3_start ? pitch3_follow_delta : 6'sd0);
    wire signed [16:0] pos3_with_delta =
        $signed({1'b0, pos3}) + $signed({{11{pitch3_delta[5]}}, pitch3_delta});
    wire [15:0] pitch3_clamped = clamp_pitch3(pos3_with_delta);
    wire pitch3_crosses_home =
        ((pos3 < POS3_INIT) && (pitch3_clamped > POS3_INIT)) ||
        ((pos3 > POS3_INIT) && (pitch3_clamped < POS3_INIT));
    wire [15:0] next_pos3 =
        (pitch3_active && pitch3_crosses_home) ? POS3_INIT : pitch3_clamped;

    localparam [31:0] UPDATE_TICKS = (CLK_HZ / 1000) * UPDATE_PERIOD_MS;
    reg [31:0] update_wait;
    reg        startup_pending;
    reg        home_pending;
    reg        home_seq;          // 1 while the six-pose initial sequence is running
    reg        update_pending;

    reg [3:0] state;
    reg       send_req;
    reg [7:0] servo_id;
    reg [7:0] frame_len;
    reg [7:0] cmd;
    reg [2:0] param_count;
    reg [7:0] p1, p2, p3, p4;
    reg [15:0] send_pos3;
    reg [15:0] send_pos4;
    reg        send_pitch3;

    wire pkt_busy;
    wire pkt_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            send_req        <= 1'b0;
            servo_id        <= 8'd0;
            frame_len       <= 8'd0;
            cmd             <= 8'd0;
            param_count     <= 3'd0;
            p1 <= 8'd0; p2 <= 8'd0; p3 <= 8'd0; p4 <= 8'd0;
            pos3            <= POS3_INIT;
            pos4            <= POS4_INIT;
            pos6            <= POS6_INIT;
            send_pos3       <= POS3_INIT;
            send_pos4       <= POS4_INIT;
            send_pitch3     <= 1'b0;
            pitch3_active   <= 1'b0;
            startup_pending <= 1'b1;
            home_pending    <= 1'b0;
            home_seq        <= 1'b0;
            update_pending  <= 1'b0;
            update_wait     <= 32'd0;
        end else begin
            send_req <= 1'b0;

            if (home_i)
                home_pending <= 1'b1;

            if (update_wait != 0) begin
                update_wait <= update_wait - 1'b1;
            end else begin
                update_pending <= 1'b1;
                update_wait <= UPDATE_TICKS;
            end

            case (state)
                S_IDLE: begin
                    if ((startup_pending || home_pending) && !pkt_busy) begin
                        startup_pending <= 1'b0;
                        home_pending    <= 1'b0;
                        home_seq        <= 1'b1;
                        pitch3_active   <= 1'b0;
                        pos3      <= POS3_INIT;
                        pos4      <= POS4_INIT;
                        pos6      <= POS6_INIT;
                        send_pos3 <= POS3_INIT;
                        send_pos4 <= POS4_INIT;
                        send_req  <= 1'b1;
                        servo_id  <= 8'd1;
                        frame_len <= LEN_MOVE_TIME_WAIT_WRITE;
                        cmd       <= CMD_MOVE_TIME_WAIT_WRITE;
                        param_count <= 3'd4;
                        p1 <= POS1_AIR[7:0];
                        p2 <= POS1_AIR[15:8];
                        p3 <= HOME_TIME_16[7:0];
                        p4 <= HOME_TIME_16[15:8];
                        state <= S_WAIT1;
                    end else if (update_pending && !pkt_busy && target_valid) begin
                        update_pending <= 1'b0;

                        if (pitch3_active && (pos3 == POS3_INIT) &&
                            (pitch_delta == 0))
                            pitch3_active <= 1'b0;

                        if ((pitch_delta != 0) || (yaw_delta != 0) ||
                            (pitch3_delta != 0)) begin
                            if (pitch3_active || pitch3_start) begin
                                // Servo 3 has priority. Hold servo 4 at the
                                // endpoint until servo 3 reaches 700.
                                pos3      <= next_pos3;
                                send_pos3 <= next_pos3;
                                send_pos4 <= pos4;
                                send_pitch3 <= (pitch3_delta != 0);
                                if (next_pos3 == POS3_INIT)
                                    pitch3_active <= 1'b0;
                                else
                                    pitch3_active <= 1'b1;
                            end else begin
                                pos3      <= pos3;
                                pos4      <= next_pos4;
                                send_pos3 <= pos3;
                                send_pos4 <= next_pos4;
                                send_pitch3 <= 1'b0;
                            end
                            pos6      <= next_pos6;
                            send_req  <= 1'b1;
                            servo_id  <= 8'd6;
                            frame_len <= LEN_MOVE_TIME_WAIT_WRITE;
                            cmd       <= CMD_MOVE_TIME_WAIT_WRITE;
                            param_count <= 3'd4;
                            p1 <= next_pos6[7:0];
                            p2 <= next_pos6[15:8];
                            p3 <= MOVE_TIME_16[7:0];
                            p4 <= MOVE_TIME_16[15:8];
                            state <= S_WAIT6;
                        end
                    end
                end

                S_WAIT1: begin
                    if (pkt_done) begin
                        send_req  <= 1'b1;
                        servo_id  <= 8'd2;
                        frame_len <= LEN_MOVE_TIME_WAIT_WRITE;
                        cmd       <= CMD_MOVE_TIME_WAIT_WRITE;
                        param_count <= 3'd4;
                        p1 <= POS2_AIR[7:0];
                        p2 <= POS2_AIR[15:8];
                        p3 <= HOME_TIME_16[7:0];
                        p4 <= HOME_TIME_16[15:8];
                        state <= S_WAIT2;
                    end
                end

                S_WAIT2: begin
                    if (pkt_done) begin
                        send_req  <= 1'b1;
                        servo_id  <= 8'd3;
                        frame_len <= LEN_MOVE_TIME_WAIT_WRITE;
                        cmd       <= CMD_MOVE_TIME_WAIT_WRITE;
                        param_count <= 3'd4;
                        p1 <= POS3_INIT[7:0];
                        p2 <= POS3_INIT[15:8];
                        p3 <= HOME_TIME_16[7:0];
                        p4 <= HOME_TIME_16[15:8];
                        state <= S_WAIT3;
                    end
                end

                S_WAIT3: begin
                    if (pkt_done) begin
                        send_req  <= 1'b1;
                        servo_id  <= 8'd5;
                        frame_len <= LEN_MOVE_TIME_WAIT_WRITE;
                        cmd       <= CMD_MOVE_TIME_WAIT_WRITE;
                        param_count <= 3'd4;
                        p1 <= POS5_AIR[7:0];
                        p2 <= POS5_AIR[15:8];
                        p3 <= HOME_TIME_16[7:0];
                        p4 <= HOME_TIME_16[15:8];
                        state <= S_WAIT5;
                    end
                end

                S_WAIT5: begin
                    if (pkt_done) begin
                        send_req  <= 1'b1;
                        servo_id  <= 8'd6;
                        frame_len <= LEN_MOVE_TIME_WAIT_WRITE;
                        cmd       <= CMD_MOVE_TIME_WAIT_WRITE;
                        param_count <= 3'd4;
                        p1 <= POS6_INIT[7:0];
                        p2 <= POS6_INIT[15:8];
                        p3 <= HOME_TIME_16[7:0];
                        p4 <= HOME_TIME_16[15:8];
                        state <= S_WAIT6;
                    end
                end

                S_WAIT6: begin
                    if (pkt_done) begin
                        if (home_seq) begin
                            // Servo 4 is the one axis the startup pose used to skip;
                            // include it so the initial pose is complete.
                            send_req  <= 1'b1;
                            servo_id  <= 8'd4;
                            frame_len <= LEN_MOVE_TIME_WAIT_WRITE;
                            cmd       <= CMD_MOVE_TIME_WAIT_WRITE;
                            param_count <= 3'd4;
                            p1 <= POS4_INIT[7:0];
                            p2 <= POS4_INIT[15:8];
                            p3 <= HOME_TIME_16[7:0];
                            p4 <= HOME_TIME_16[15:8];
                            state <= S_WAIT4;
                        end else if (send_pitch3) begin
                            send_req  <= 1'b1;
                            servo_id  <= 8'd3;
                            frame_len <= LEN_MOVE_TIME_WAIT_WRITE;
                            cmd       <= CMD_MOVE_TIME_WAIT_WRITE;
                            param_count <= 3'd4;
                            p1 <= send_pos3[7:0];
                            p2 <= send_pos3[15:8];
                            p3 <= MOVE_TIME_16[7:0];
                            p4 <= MOVE_TIME_16[15:8];
                            state <= S_WAIT3_TRACK;
                        end else begin
                            send_req  <= 1'b1;
                            servo_id  <= 8'd4;
                            frame_len <= LEN_MOVE_TIME_WAIT_WRITE;
                            cmd       <= CMD_MOVE_TIME_WAIT_WRITE;
                            param_count <= 3'd4;
                            p1 <= send_pos4[7:0];
                            p2 <= send_pos4[15:8];
                            p3 <= MOVE_TIME_16[7:0];
                            p4 <= MOVE_TIME_16[15:8];
                            state <= S_WAIT4;
                        end
                    end
                end

                S_WAIT3_TRACK: begin
                    if (pkt_done) begin
                        send_req  <= 1'b1;
                        servo_id  <= 8'd4;
                        frame_len <= LEN_MOVE_TIME_WAIT_WRITE;
                        cmd       <= CMD_MOVE_TIME_WAIT_WRITE;
                        param_count <= 3'd4;
                        p1 <= send_pos4[7:0];
                        p2 <= send_pos4[15:8];
                        p3 <= MOVE_TIME_16[7:0];
                        p4 <= MOVE_TIME_16[15:8];
                        state <= S_WAIT4;
                    end
                end

                S_WAIT4: begin
                    if (pkt_done) begin
                        send_req  <= 1'b1;
                        servo_id  <= BROADCAST_ID;
                        frame_len <= LEN_MOVE_START;
                        cmd       <= CMD_MOVE_START;
                        param_count <= 3'd0;
                        p1 <= 8'd0; p2 <= 8'd0; p3 <= 8'd0; p4 <= 8'd0;
                        state <= S_START;
                    end
                end

                S_START: begin
                    if (pkt_done) begin
                        home_seq <= 1'b0;
                        state    <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    compat_bus_servo_packet_tx #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD)
    ) u_packet (
        .sys_clk     (clk),
        .rst_n       (rst_n),
        .send_req    (send_req),
        .servo_id    (servo_id),
        .frame_len   (frame_len),
        .cmd         (cmd),
        .param_count (param_count),
        .param1      (p1),
        .param2      (p2),
        .param3      (p3),
        .param4      (p4),
        .txd         (arm_uart),
        .tx_oe       (tx_oe),
        .busy        (pkt_busy),
        .done        (pkt_done)
    );

    assign dbg_move_time = {p4, p3};
    assign dbg_pos3     = pos3;
    assign dbg_pos4     = pos4;
    assign dbg_pos6     = pos6;
    assign dbg_servo_id = servo_id;
    assign dbg_send     = send_req;
    assign dbg_busy     = (state != S_IDLE);

endmodule
