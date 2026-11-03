`timescale 1ns/1ps
module tb_rgb2hsv_pipeline;
reg clk=0,rst_n=0,valid=0;reg [15:0] rgb=0;
always #10 clk=~clk;
wire out_valid;wire [8:0] h;wire [7:0] s,v;
rgb2hsv dut(.clk(clk),.rst_n(rst_n),.rgb_valid(valid),.rgb565_in(rgb),.hsv_valid(out_valid),.hsv_h(h),.hsv_s(s),.hsv_v(v));
integer eh[0:65535],es[0:65535],ev[0:65535];
integer wr=0,rd=0,errors=0,r,g,b,mn,mx,d,hh,ss,i;
always @(posedge clk) begin
 if(!rst_n)begin wr=0;rd=0;end
 else if(valid)begin
  r={rgb[15:11],rgb[15:13]};g={rgb[10:5],rgb[10:9]};b={rgb[4:0],rgb[4:2]};
  mx=(r>=g && r>=b)?r:((g>=r && g>=b)?g:b);mn=(r<=g && r<=b)?r:((g<=r && g<=b)?g:b);d=mx-mn;
  ss=(mx==0)?0:(d*255)/mx;
  if(d==0)hh=0;
  else if(mx==r)hh=(g>=b)?((g-b)*60/d):(360-(b-g)*60/d);
  else if(mx==g)hh=(b>=r)?(120+(b-r)*60/d):(120-(r-b)*60/d);
  else hh=(r>=g)?(240+(r-g)*60/d):(240-(g-r)*60/d);
  eh[wr]=hh;es[wr]=ss;ev[wr]=mx;wr=wr+1;
 end
 #1;
 if(rst_n && out_valid)begin
  if(rd>=wr || h!==eh[rd] || s!==es[rd] || v!==ev[rd])begin
   errors=errors+1;if(errors<6)$display("FAIL rgb index %0d HSV=%0d/%0d/%0d expected=%0d/%0d/%0d",rd,h,s,v,eh[rd],es[rd],ev[rd]);
  end
  rd=rd+1;
 end
end
initial begin
 repeat(4)@(negedge clk);rst_n=1;valid=1;rgb=16'hf800;repeat(4)@(negedge clk);rst_n=0;valid=0;
 repeat(4)@(negedge clk);rst_n=1;
 for(i=0;i<65536;i=i+1)begin
  @(negedge clk);valid=1;rgb=i;
  if(i%7==0)begin @(negedge clk);valid=0;end
 end
 @(negedge clk);valid=0;repeat(24)@(negedge clk);
 if(rd!=65536)begin $display("FAIL sample count %0d",rd);errors=errors+1;end
 if(errors==0)$display("RGB2HSV_PIPELINE_PASS samples=%0d",rd);else $display("FAIL errors=%0d",errors);
 $finish;end
initial begin #2000000;$display("FAIL timeout");$finish;end
endmodule
