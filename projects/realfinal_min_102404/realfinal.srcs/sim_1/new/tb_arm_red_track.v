`timescale 1ns / 1ps

module tb_arm_red_track;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [10:0] target_pitch = 11'd200;
    reg [10:0] target_yaw = 11'd300;
    reg        target_valid = 1'b1;
    reg        home = 1'b0;

    wire arm_uart;
    wire tx_oe;
    wire [15:0] move_time;
    wire [15:0] pos3;
    wire [15:0] pos4;
    wire [15:0] pos6;
    wire [7:0] servo_id;
    wire send;
    wire busy;

    integer servo6_count = 0;
    integer servo4_count = 0;
    integer servo5_count = 0;
    integer servo1_count = 0;
    integer servo2_count = 0;
    integer servo3_count = 0;
    integer start_count  = 0;

    reg [15:0] last_move_time = 16'd0;
    reg [15:0] track_move_time = 16'd0;
    integer s1_b, s2_b, s3_b, s4_b, s5_b, s6_b, st_b;

    always #15 clk = ~clk;

    arm_red_track #(
        .CLK_HZ(33_333_333),
        .BAUD(8_333_333),
        .UPDATE_PERIOD_MS(0),
        .CENTER_PITCH(200),
        .CENTER_YAW(300),
        .PITCH3_MIN(600),
        .PITCH3_MAX(800),
        .PITCH_CASCADE_LOW(200),
        .PITCH_CASCADE_HIGH(400),
        .PITCH_SIGN(1),
        .PITCH3_SIGN(-1),
        .YAW_SIGN(1)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .target_pitch(target_pitch),
        .target_yaw(target_yaw),
        .target_valid(target_valid),
        .home_i(home),
        .arm_uart(arm_uart),
        .tx_oe(tx_oe),
        .dbg_move_time(move_time),
        .dbg_pos3(pos3),
        .dbg_pos4(pos4),
        .dbg_pos6(pos6),
        .dbg_servo_id(servo_id),
        .dbg_send(send),
        .dbg_busy(busy)
    );

    always @(posedge clk) begin
        if (send && (servo_id == 8'd6)) servo6_count <= servo6_count + 1;
        if (send && (servo_id == 8'd4)) servo4_count <= servo4_count + 1;
        if (send && (servo_id == 8'd5)) servo5_count <= servo5_count + 1;
        if (send && (servo_id == 8'd1)) servo1_count <= servo1_count + 1;
        if (send && (servo_id == 8'd2)) servo2_count <= servo2_count + 1;
        if (send && (servo_id == 8'd3)) servo3_count <= servo3_count + 1;
        if (send && (servo_id == 8'd254)) start_count <= start_count + 1;
        if (send && (servo_id != 8'd254)) last_move_time <= move_time;
    end

    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1'b1;

        wait (!busy && servo5_count == 1 &&
              servo6_count == 1 && servo4_count == 1 &&
              start_count == 1);
        if (pos3 !== 16'd700 || pos4 !== 16'd300 || pos6 !== 16'd500)
            $fatal(1, "startup pose is wrong: pos3=%0d pos4=%0d pos6=%0d",
                   pos3, pos4, pos6);
        if ((servo1_count != 1) || (servo2_count != 1) ||
            (servo3_count != 1) || (servo5_count != 1))
            $fatal(1, "fixed air-defence pose was not sent exactly once");

        // Target is below and to the right in the camera image.
        target_pitch = 11'd220;
        target_yaw = 11'd340;
        wait (servo6_count >= 2);
        target_pitch = 11'd200;
        target_yaw = 11'd300;
        wait (!busy && servo4_count >= 2 && start_count >= 2);
        $display("TRACE initial move: pos3=%0d pos4=%0d pos6=%0d",
                 pos3, pos4, pos6);

        if (pos4 !== 16'd302)
            $fatal(1, "servo 4 sign regression, expected 302: %0d", pos4);
        if (pos6 !== 16'd505)
            $fatal(1, "servo 6 sign regression, expected 505: %0d", pos6);
        if (servo5_count != 1)
            $fatal(1, "servo 5 must receive exactly one upright pose");

        repeat (1000) @(posedge clk);
        if ((servo6_count != 2) || (servo4_count != 2))
            $fatal(1, "centered target must not send another movement");
        if (servo5_count != 1)
            $fatal(1, "servo 5 must remain unchanged after startup");

        // Drive the target far above centre until servo 4 reaches its low
        // threshold. Servo 3 must then start moving as the secondary pitch axis.
        target_pitch = 11'd0;
        wait (pos4 == 16'd200);
        $display("TRACE servo4 low: pos3=%0d pos4=%0d servo3_count=%0d",
                 pos3, pos4, servo3_count);
        wait (servo3_count >= 2);
        $display("TRACE servo3 extend: pos3=%0d pos4=%0d servo3_count=%0d",
                 pos3, pos4, servo3_count);
        if (pos3 <= 16'd700)
            $fatal(1, "servo 3 did not extend after servo 4 reached threshold");

        // Return the target to centre. Servo 3 must return home first while
        // servo 4 remains at 300.
        target_pitch = 11'd200;
        wait (pos3 == 16'd700);
        $display("TRACE servo3 home: pos3=%0d pos4=%0d", pos3, pos4);
        if (pos4 != 16'd200)
            $fatal(1, "servo 4 moved before servo 3 returned home: %0d", pos4);

        // Only after servo 3 is home may servo 4 resume tracking.
        target_pitch = 11'd220;
        wait (pos4 > 16'd200);
        $display("TRACE servo4 resume: pos3=%0d pos4=%0d", pos3, pos4);

        // Symmetric high-end cascade: servo 4 reaches 400, then servo 3 moves
        // below 700 and must return home before servo 4 leaves 400.
        target_pitch = 11'd400;
        wait (pos4 == 16'd400);
        wait (pos3 < 16'd700);
        if (pos4 != 16'd400)
            $fatal(1, "servo 4 left its high stop during servo 3 assist");

        target_pitch = 11'd200;
        wait (pos3 == 16'd700);
        if (pos4 != 16'd400)
            $fatal(1, "servo 4 moved before high-side servo 3 returned home");

        target_pitch = 11'd180;
        wait (pos4 < 16'd400);

        // 需求 1/2：跟踪中再说一次"防空" -> 6 个舵机重发初始姿态，时间 1000ms
        if (last_move_time !== 16'd100)
            $fatal(1, "tracking packets must keep MOVE_TIME_MS=100: %0d", last_move_time);

        target_valid = 1'b0;
        wait (!busy);               // 等上一轮跟踪的收尾包全部发完再记基线
        repeat (4) @(posedge clk);
        s1_b = servo1_count; s2_b = servo2_count; s3_b = servo3_count;
        s4_b = servo4_count; s5_b = servo5_count; s6_b = servo6_count;
        st_b = start_count;

        home = 1'b1;
        @(posedge clk);
        home = 1'b0;

        wait (!busy &&
              servo1_count == s1_b + 1 && servo2_count == s2_b + 1 &&
              servo3_count == s3_b + 1 && servo4_count == s4_b + 1 &&
              servo5_count == s5_b + 1 && servo6_count == s6_b + 1 &&
              start_count  == st_b  + 1);
        if (pos3 !== 16'd700 || pos4 !== 16'd300 || pos6 !== 16'd500)
            $fatal(1, "home pulse did not restore the initial pose: pos3=%0d pos4=%0d pos6=%0d",
                   pos3, pos4, pos6);
        if (last_move_time !== 16'd1000)
            $fatal(1, "home packets must use HOME_TIME_MS=1000: %0d", last_move_time);
        $display("TRACE home pose resent: pos3=%0d pos4=%0d pos6=%0d move_time=%0d",
                 pos3, pos4, pos6, last_move_time);

        // 回位结束后跟踪照常恢复，并且仍用 100ms
        s6_b = servo6_count;
        target_valid = 1'b1;
        target_yaw = 11'd340;
        wait (servo6_count >= s6_b + 2);
        if (last_move_time !== 16'd100)
            $fatal(1, "tracking after home must use MOVE_TIME_MS=100: %0d", last_move_time);
        $display("TRACE tracking resumed, move_time=%0d", last_move_time);

        $display("ARM_RED_TRACK_PASS pos3=%0d pos4=%0d pos6=%0d servo5_packets=%0d",
                 pos3, pos4, pos6, servo5_count);
        $finish;
    end

    initial begin
        repeat (500000) @(posedge clk);
        $fatal(1, "timeout waiting for arm tracking packets");
    end
endmodule
