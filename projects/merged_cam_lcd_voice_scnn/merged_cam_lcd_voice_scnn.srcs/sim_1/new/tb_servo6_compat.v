`timescale 1ns/1ps
module tb_servo6_compat;
reg clk=0;always #15 clk=~clk;reg rst_n=0,valid=0,home=0;reg [9:0] raw_x=236;
wire [10:0] yaw=11'd599-({1'b0,raw_x}+11'd64);wire [15:0] pos6;wire [7:0] id;wire send,busy;integer errors=0,starts=0;
compat_arm_red_track #(
        .CLK_HZ(33_333_333),
        .BAUD(8_333_333),
        .CENTER_PITCH(200),
        .CENTER_YAW(300),
        .PITCH_MIN(200),
        .PITCH_MAX(400),
        .YAW_MIN(210),
        .YAW_MAX(750),
        .PITCH3_MIN(600),
        .PITCH3_MAX(800),
        .PITCH_CASCADE_LOW(200),
        .PITCH_CASCADE_HIGH(400),
        .POS4_INIT(300),
        .POS6_INIT(500),
        .POS1_AIR(220),
        .POS2_AIR(500),
        .POS3_INIT(700),
        .POS5_AIR(400),
        .DEADBAND(16),
        .KP_SHIFT(3),

        .STEP_MAX(14),
        .MOVE_TIME_MS(100),
        .HOME_TIME_MS(1000),
        .UPDATE_PERIOD_MS(0),
        .PITCH_SIGN(1),
        .PITCH3_SIGN(-1),
        .YAW_SIGN(1)
) dut(.clk(clk),.rst_n(rst_n),.target_pitch(11'd199),.target_yaw(yaw),.target_valid(valid),.home_i(home),.arm_uart(),.tx_oe(),.dbg_move_time(),.dbg_pos3(),.dbg_pos4(),.dbg_pos6(pos6),.dbg_servo_id(id),.dbg_send(send),.dbg_busy(busy));
always @(posedge clk)if(rst_n)begin
 if(send && id==254)starts<=starts+1;
 if(pos6<210 || pos6>750)begin errors=errors+1;$display("ERROR: servo 6 exceeded 210..750: %0d",pos6);end
end
task check(input condition,input [8*100-1:0] msg);begin if(condition!==1'b1)begin errors=errors+1;$display("ERROR: %0s",msg);end end endtask
initial begin repeat(6)@(negedge clk);rst_n=1;wait(starts>=1 && !busy);check(pos6==500,"lower startup yaw is not 500");
raw_x=0;valid=1;wait(pos6==750);check(yaw==535,"upper-to-lower mirrored yaw units are wrong");repeat(100)@(negedge clk);check(pos6==750,"upper yaw clamp was not stable");
raw_x=472;wait(pos6==210);check(yaw==63,"right-edge bbox orientation is wrong");repeat(100)@(negedge clk);check(pos6==210,"lower yaw clamp was not stable");
valid=0;@(negedge clk);home=1;@(negedge clk);home=0;wait(starts>=2 && !busy);repeat(100)@(negedge clk);check(pos6==500,"home request failed to restore yaw 500");
if(errors==0)$display("SERVO6_COMPAT_TEST: PASS");else $display("SERVO6_COMPAT_TEST: FAIL (%0d errors)",errors);$finish;end
initial begin #10000000;$display("SERVO6_COMPAT_TEST: FAIL (timeout)");$finish;end
endmodule
