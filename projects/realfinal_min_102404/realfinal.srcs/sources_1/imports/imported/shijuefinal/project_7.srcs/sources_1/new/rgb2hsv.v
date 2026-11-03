`timescale 1ns / 1ps
// Two restoring dividers preserve HSV values with one input accepted per cycle.
// Output valid follows the input through 18 registered stages.
module rgb2hsv(
    input wire clk, input wire rst_n,
    input wire rgb_valid, input wire [15:0] rgb565_in,
    output reg hsv_valid, output reg [8:0] hsv_h,
    output reg [7:0] hsv_s, output reg [7:0] hsv_v
);
    wire [7:0] r = {rgb565_in[15:11],rgb565_in[15:13]};
    wire [7:0] g = {rgb565_in[10:5],rgb565_in[10:9]};
    wire [7:0] b = {rgb565_in[4:0],rgb565_in[4:2]};
    wire [7:0] maximum = (r>=g && r>=b)?r:((g>=r && g>=b)?g:b);
    wire [7:0] minimum = (r<=g && r<=b)?r:((g<=r && g<=b)?g:b);
    wire [7:0] delta = maximum-minimum;
    reg [15:0] hn[0:16],sn[0:16],hq[0:16],sq[0:16];
    reg [8:0] hr[0:16],sr[0:16],base[0:16];
    reg [7:0] hd[0:16],sd[0:16],value[0:16];
    reg subtract[0:16],valid[0:16];
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(i=0;i<=16;i=i+1) begin
                hn[i]<=0;sn[i]<=0;hq[i]<=0;sq[i]<=0;
                hr[i]<=0;sr[i]<=0;base[i]<=0;
                hd[i]<=1;sd[i]<=1;value[i]<=0;subtract[i]<=0;valid[i]<=0;
            end
            hsv_valid<=0;hsv_h<=0;hsv_s<=0;hsv_v<=0;
        end else begin
            valid[0]<=rgb_valid;value[0]<=maximum;
            hd[0]<=(delta==0)?8'd1:delta;
            sd[0]<=(maximum==0)?8'd1:maximum;
            sn[0]<=delta*16'd255;hq[0]<=0;sq[0]<=0;hr[0]<=0;sr[0]<=0;
            if(delta==0) begin hn[0]<=0;base[0]<=0;subtract[0]<=0;end
            else if(maximum==r) begin
                hn[0]<=((g>=b)?(g-b):(b-g))*16'd60;
                base[0]<=(g>=b)?9'd0:9'd360;subtract[0]<=(g<b);
            end else if(maximum==g) begin
                hn[0]<=((b>=r)?(b-r):(r-b))*16'd60;
                base[0]<=9'd120;subtract[0]<=(b<r);
            end else begin
                hn[0]<=((r>=g)?(r-g):(g-r))*16'd60;
                base[0]<=9'd240;subtract[0]<=(r<g);
            end
            for(i=0;i<16;i=i+1) begin
                hn[i+1]<={hn[i][14:0],1'b0};sn[i+1]<={sn[i][14:0],1'b0};
                hd[i+1]<=hd[i];sd[i+1]<=sd[i];
                if({hr[i][7:0],hn[i][15]}>={1'b0,hd[i]}) begin
                    hr[i+1]<={hr[i][7:0],hn[i][15]}-{1'b0,hd[i]};
                    hq[i+1]<={hq[i][14:0],1'b1};
                end else begin hr[i+1]<={hr[i][7:0],hn[i][15]};hq[i+1]<={hq[i][14:0],1'b0};end
                if({sr[i][7:0],sn[i][15]}>={1'b0,sd[i]}) begin
                    sr[i+1]<={sr[i][7:0],sn[i][15]}-{1'b0,sd[i]};
                    sq[i+1]<={sq[i][14:0],1'b1};
                end else begin sr[i+1]<={sr[i][7:0],sn[i][15]};sq[i+1]<={sq[i][14:0],1'b0};end
                base[i+1]<=base[i];subtract[i+1]<=subtract[i];
                value[i+1]<=value[i];valid[i+1]<=valid[i];
            end
            hsv_valid<=valid[16];hsv_v<=value[16];hsv_s<=sq[16][7:0];
            hsv_h<=subtract[16]?(base[16]-hq[16][8:0]):(base[16]+hq[16][8:0]);
        end
    end
endmodule
