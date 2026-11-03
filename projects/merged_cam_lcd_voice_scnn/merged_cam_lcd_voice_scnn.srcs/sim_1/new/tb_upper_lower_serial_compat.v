`timescale 1ns/1ps
module tb_upper_lower_serial_compat;
reg clk=0,cam_clk=0,rst_n=0,asr=1,label_valid=0,frame=0;reg [11:0] counts=0;reg [9:0] roi_x=0;
always #15 clk=~clk;always #20 cam_clk=~cam_clk;
wire upper_tx,lower_tx,cam_sda;wire [7:0] peer_cmd;wire peer_valid,link_error,bbox_valid,bbox_tgl,bbox_busy,cmd_valid;
wire [9:0] bbox_x,bbox_y,bbox_w,bbox_h;wire [4:0] track_pat;wire vision_en,defense_en;
wire [10:0] yaw=11'd599-({1'b0,bbox_x}+{2'b0,bbox_w[9:1]});
wire [10:0] pitch=11'd399-({1'b0,bbox_y}+{2'b0,bbox_h[9:1]});
integer errors=0,air_commands=0,commands=0,i;
top upper(.sys_clk(clk),.sys_rst_n(rst_n),.cam_pclk(cam_clk),.cam_vsync(1'b0),.cam_href(1'b0),.cam_data(8'd0),.cam_sda(cam_sda),.asr_rxd(asr),.link_rx(lower_tx),.link_tx(upper_tx),.track_l2(1'b0),.track_l1(1'b1),.track_m(1'b0),.track_r1(1'b1),.track_r2(1'b0));
pullup(cam_sda);
compat_board_link #(.CLK_FREQ(33333333),.UART_BPS(115200),.ECHO_EN(1'b0)) link(.clk(clk),.rst_n(rst_n),.link_rx(upper_tx),.link_tx(lower_tx),.local_cmd(8'd0),.local_send(1'b0),.peer_cmd(peer_cmd),.peer_valid(peer_valid),.link_err(link_error));
compat_bbox_unpack #(.CLK_FREQ(33333333)) unpack(.clk(clk),.rst_n(rst_n),.peer_cmd(peer_cmd),.peer_valid(peer_valid),.bbox_valid(bbox_valid),.bbox_x(bbox_x),.bbox_y(bbox_y),.bbox_w(bbox_w),.bbox_h(bbox_h),.bbox_label(),.bbox_frame_tgl(bbox_tgl),.bbox_rx_busy(bbox_busy));
compat_link_demux #(.CLK_FREQ(33333333)) demux(.clk(clk),.rst_n(rst_n),.peer_cmd(peer_cmd),.peer_valid(peer_valid),.bbox_busy(bbox_busy),.track_pat(track_pat),.track_upd(),.cmd_valid(cmd_valid));
compat_voice_mode_select modes(.clk(clk),.rst_n(rst_n),.cmd(peer_cmd),.cmd_valid(cmd_valid),.xunbi_en(),.vision_en(vision_en),.defense_en(defense_en),.arm_en());
always @(posedge clk)if(rst_n && cmd_valid)begin commands<=commands+1;if(peer_cmd==3)air_commands<=air_commands+1;end
task check(input condition,input [8*120-1:0] msg);begin if(condition!==1'b1)begin errors=errors+1;$display("ERROR: %0s",msg);end end endtask
task uart_byte(input [7:0] value);integer b;begin asr=0;#8680;for(b=0;b<8;b=b+1)begin asr=value[b];#8680;end asr=1;#8680;end endtask
task command(input [7:0] value);begin uart_byte(8'hAA);uart_byte(8'h55);uart_byte(value);uart_byte(8'h55);uart_byte(8'hAA);repeat(24)@(negedge cam_clk);end endtask
task label;begin @(negedge clk);counts={6'd50,6'd0};label_valid=1;@(negedge clk);label_valid=0;repeat(6)@(negedge cam_clk);end endtask
task camera_frame;begin @(negedge cam_clk);frame=1;@(negedge cam_clk);frame=0;end endtask
initial begin
force upper.cfg_done=1'b0;force upper.snn_label_valid=label_valid;force upper.snn_all_counts=counts;force upper.vsync_pos=frame;force upper.roi_x0=roi_x;force upper.roi_y0=9'd136;
repeat(6)@(negedge clk);rst_n=1;command(3);for(i=0;i<5;i=i+1)label;
check(upper.roi_tracking,"upper failed its original five-result acquisition");wait(bbox_valid);
check(defense_en && bbox_x==0 && bbox_y==136 && bbox_w==128 && bbox_h==128,"actual UART bbox packet failed lower decode");
check(yaw==535 && pitch==199,"camera-to-lower mirrored coordinates are incompatible");wait(track_pat==5'b10101);
roi_x=472;camera_frame;wait(bbox_x==472 && bbox_valid);check(yaw==63,"right-edge bbox has wrong orientation or scale");
release upper.roi_x0;release upper.roi_y0;command(3);wait(air_commands==2);wait(!bbox_valid);
check(!upper.roi_tracking && upper.u_roi_scheduler.hist_count==0,"repeat command reused old upper lock/history");
for(i=0;i<4;i=i+1)label;check(!upper.roi_tracking,"old classifications restored lock before five fresh results");
label;wait(bbox_valid);check(upper.roi_tracking && bbox_x==236 && bbox_y==136,"fresh centre acquisition did not reach lower board");
check(air_commands==2 && commands==2,"bbox payload bytes were misread as mode commands");
command(4);wait(!defense_en);wait(!bbox_valid);check(!upper.roi_tracking && upper.u_lcd.display_roi_x==236 && upper.u_lcd.display_roi_y==136,"mode exit retained a valid target or non-centred upper display");
command(2);wait(vision_en);check(!defense_en && !upper.roi_tracking && !link_error && commands==4,"follow-mode routing or UART framing changed");
if(errors==0)$display("UPPER_LOWER_SERIAL_COMPAT_TEST: PASS");else $display("UPPER_LOWER_SERIAL_COMPAT_TEST: FAIL (%0d errors)",errors);$finish;end
initial begin #100000000;$display("UPPER_LOWER_SERIAL_COMPAT_TEST: FAIL (timeout)");$finish;end
endmodule
