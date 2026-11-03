`timescale 1ns/1ps
module tb_lcd_box_color;
reg clk=0;always #15 clk=~clk;reg rst_n=0,locked=0,tracker_enabled=1;reg [9:0] roi_x=236;reg [8:0] roi_y=136;
wire [23:0] lcd_rgb;integer errors=0;
lcd_cam_text_scnn dut(.clk(clk),.rst_n(rst_n),.pixel_data(16'd0),.drone_count(6'd0),.not_drone_count(6'd0),.tracker_enabled(tracker_enabled),.roi_x(roi_x),.roi_y(roi_y),.locked(locked),.lcd_hs(),.lcd_vs(),.lcd_de(),.lcd_rgb(lcd_rgb),.fb_rd_addr());
task sample(input [10:0] h,input [10:0] v,input [23:0] expected,input [8*110-1:0] msg);begin
 force dut.h_cnt=h;force dut.v_cnt=v;repeat(6)@(negedge clk);
 if(lcd_rgb!==expected)begin errors=errors+1;$display("ERROR: %0s rgb=%06h expected=%06h",msg,lcd_rgb,expected);end
end endtask
initial begin repeat(3)@(negedge clk);rst_n=1;
sample(679,326,24'hFF0000,"unlocked ROI must be red");locked=1;sample(679,326,24'h00FF00,"locked ROI must be green");
roi_x=80;roi_y=60;locked=0;sample(679,326,24'h000000,"active off-centre ROI must not be drawn at centre");
sample(835,402,24'hFF0000,"active unlocked off-centre ROI must remain red");locked=1;sample(835,402,24'h00FF00,"active locked off-centre ROI must be green");
tracker_enabled=0;sample(835,402,24'h000000,"non-air mode retained the previous ROI position");
sample(679,326,24'hFF0000,"non-air mode must show a centred red ROI even with stale lock inputs");
tracker_enabled=1;locked=0;sample(835,402,24'hFF0000,"re-entering air must resume original ROI display");
release dut.h_cnt;release dut.v_cnt;
if(errors==0)$display("LCD_BOX_COLOR_TEST: PASS");else $display("LCD_BOX_COLOR_TEST: FAIL (%0d errors)",errors);$finish;end
endmodule
