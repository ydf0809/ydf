`timescale 1ns/1ps
module tb_lower_display_compat;
reg clk=0;always #15 clk=~clk;reg rst_n=0,cmd_valid=0,vsync=0;reg [7:0] cmd=0;reg [15:0] pixels=16'hF800;
wire vision_en,defense_en;wire [10:0] x,y,w,h;wire [23:0] rgb;integer errors=0,i;
compat_voice_mode_select modes(.clk(clk),.rst_n(rst_n),.cmd(cmd),.cmd_valid(cmd_valid),.xunbi_en(),.vision_en(vision_en),.defense_en(defense_en),.arm_en());
compat_color_track tracker(.clk(clk),.rst_n(rst_n),.cmos_vsync(vsync),.cmos_valid(1'b1),.cmos_data(pixels),.lock_sw(vision_en),.target_x(x),.target_y(y),.target_w(w),.target_h(h));
compat_rgb_lcd_driver lcd(.clk(clk),.rst_n(rst_n),.cam_latest_page(1'b0),.lcd_rd_page(),.box_x(x),.box_y(y),.box_w(w),.box_h(h),.ram_addr(),.ram_data(16'd0),.lcd_clk(),.lcd_hs(),.lcd_vs(),.lcd_de(),.lcd_rgb(rgb),.lcd_bl(),.lcd_rst());
task check(input condition,input [8*100-1:0] msg);begin if(condition!==1'b1)begin errors=errors+1;$display("ERROR: %0s",msg);end end endtask
task command(input [7:0] value);begin @(negedge clk);cmd=value;cmd_valid=1;@(negedge clk);cmd_valid=0;repeat(4)@(negedge clk);end endtask
initial begin repeat(5)@(negedge clk);rst_n=1;command(3);check(defense_en && !vision_en,"defence mode enabled the lower red-target follower");
for(i=0;i<400;i=i+1)begin @(negedge clk);pixels=(i%2)?16'hF800:16'h001F;vsync=(i%100==0);check(x==150 && y==200 && w==100 && h==100,"lower red box moved in defence mode");end
force lcd.h_cnt=11'd1055;force lcd.v_cnt=11'd524;repeat(4)@(negedge clk);
force lcd.h_cnt=11'd615;force lcd.v_cnt=11'd195;repeat(4)@(negedge clk);
check(rgb==24'hFF0000,"fixed lower box did not render as a red border");
release lcd.h_cnt;release lcd.v_cnt;command(2);check(vision_en && !defense_en,"lower follow mode 02 was disabled by the adaptation");
command(4);repeat(10)@(negedge clk);check(!vision_en && x==150 && y==200,"lower non-follow idle box did not return to centre");
if(errors==0)$display("LOWER_DISPLAY_COMPAT_TEST: PASS");else $display("LOWER_DISPLAY_COMPAT_TEST: FAIL (%0d errors)",errors);$finish;end
initial begin #1000000;$display("LOWER_DISPLAY_COMPAT_TEST: FAIL (timeout)");$finish;end
endmodule
