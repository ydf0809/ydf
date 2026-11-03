`timescale 1ns/1ps
module tb_ov7670_capture;
reg clk=0,vsync=0,href=0;reg [7:0] din=0;always #10 clk=~clk;
wire we,valid,page;wire [17:0] addr;wire [15:0] pixel,track;
integer line,p,seen=0,errors=0;
ov7670_capture dut(.pclk(clk),.vsync(vsync),.href(href),.din(din),.we(we),.waddr(addr),.dout(pixel),.lcd_rd_page(1'b0),.cam_latest_page(page),.track_valid(valid),.track_data(track),.track_vsync());
always @(posedge clk)begin #1;if(valid)begin
 if(track!==(16'h8000+seen) || pixel!==track || !we || addr!==(18'd120000+seen))begin errors=errors+1;$display("FAIL capture sample=%0d addr=%0d pixel=%h track=%h",seen,addr,pixel,track);end
 seen=seen+1;
end end
initial begin
 repeat(4)@(negedge clk);vsync=1;repeat(4)@(negedge clk);vsync=0;repeat(4)@(negedge clk);
 for(line=0;line<41;line=line+1)begin
  for(p=0;p<(line==40?178:640);p=p+1)begin
   @(negedge clk);href=1;din=(line==40 && p>=170)?8'h80:8'h12;
   @(negedge clk);din=(line==40 && p>=170)?(p-170):8'h34;
  end
  @(negedge clk);href=0;din=0;repeat(6)@(negedge clk);
  if(valid || we)begin errors=errors+1;$display("FAIL capture valid extended into blanking");end
 end
 if(seen!=8)begin errors=errors+1;$display("FAIL capture count %0d",seen);end
 if(errors==0)$display("OV7670_CAPTURE_PASS pixels=%0d",seen);else $display("FAIL capture errors=%0d",errors);$finish;end
initial begin #2000000;$display("FAIL capture timeout");$finish;end
endmodule
