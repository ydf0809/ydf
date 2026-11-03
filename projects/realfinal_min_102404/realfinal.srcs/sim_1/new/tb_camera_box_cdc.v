`timescale 1ns/1ps
module tb_camera_box_cdc;
reg clk=0,cam=0,clk75=0,clk24=0,rst_n=0,mode=0;
always #15 clk=~clk;always #10 cam=~cam;always #7 clk75=~clk75;always #21 clk24=~clk24;
reg [10:0] sx=150,sy=200,sw=100,sh=100;
wire [10:0] x,y,w,h;wire sda;integer i,errors=0,observed=0;
shijue_arm_core dut(.clk(clk),.clk_75m(clk75),.clk_24m(clk24),.rst_n(rst_n),.vision_mode_sw(mode),
 .ov_pclk(cam),.ov_href(1'b0),.ov_vsync(1'b0),.ov_data(8'd0),.ov_sio_d(sda),
 .target_x(x),.target_y(y),.target_w(w),.target_h(h));
pullup(sda);
always @(posedge clk)begin #1;if(rst_n && x>=400)begin
 observed=observed+1;if(y!==x+1 || w!==x+2 || h!==x+3)begin errors=errors+1;$display("FAIL torn bbox %0d/%0d/%0d/%0d",x,y,w,h);end
end end
initial begin
 force dut.cam_target_x=sx;force dut.cam_target_y=sy;force dut.cam_target_w=sw;force dut.cam_target_h=sh;
 repeat(5)@(negedge clk);rst_n=1;#3;mode=1;repeat(4)@(negedge cam);
 if(dut.vision_cam!==1)begin errors=errors+1;$display("FAIL mode synchronizer");end
 for(i=400;i<432;i=i+1)begin @(negedge cam);sx=i;sy=i+1;sw=i+2;sh=i+3;repeat(2)@(negedge cam);end
 repeat(40)@(negedge clk);
 if(x!==431 || y!==432 || w!==433 || h!==434 || observed==0)begin errors=errors+1;$display("FAIL final bbox");end
 mode=0;repeat(4)@(negedge cam);if(dut.vision_cam!==0)begin errors=errors+1;$display("FAIL mode disable");end
 if(errors==0)$display("CAMERA_BOX_CDC_PASS");else $display("FAIL CDC errors=%0d",errors);$finish;end
initial begin #100000;$display("FAIL CDC timeout");$finish;end
endmodule
