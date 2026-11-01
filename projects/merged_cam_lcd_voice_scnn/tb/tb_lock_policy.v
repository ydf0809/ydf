`timescale 1ns/1ps
module tb_lock_policy;
reg clk=0; always #500000 clk=~clk;
reg rst_n=0,frame_sync=0,roi_hold=0,run_en=1,label_valid=0,is_drone=0;
reg drone_count_low=0,recheck_tick=0,motion_valid=0,motion_update=0;
wire [9:0] roi_x0; wire [8:0] roi_y0; wire tracking,verifying;
integer errors=0,i; reg [9:0] last_x; reg [8:0] last_y;
roi_scheduler dut(.clk(clk),.rst_n(rst_n),.frame_sync(frame_sync),.roi_hold(roi_hold),.run_en(run_en),.label_valid(label_valid),.is_drone(is_drone),.drone_count_low(drone_count_low),.recheck_tick(recheck_tick),.motion_valid(motion_valid),.motion_update(motion_update),.motion_x0(9'd140),.motion_x1(9'd159),.motion_y0(8'd90),.motion_y1(8'd109),.roi_x0(roi_x0),.roi_y0(roi_y0),.tracking(tracking),.verifying(verifying));
task check(input condition,input [8*110-1:0] message); begin if(condition!==1'b1)begin $display("ERROR: %0s",message);errors=errors+1;end end endtask
task reset; begin rst_n=0;frame_sync=0;roi_hold=0;run_en=1;label_valid=0;motion_valid=0;motion_update=0;recheck_tick=0;repeat(3)@(negedge clk);rst_n=1;end endtask
task label(input d); begin @(negedge clk);is_drone=d;label_valid=1;@(negedge clk);label_valid=0;end endtask
task frame; begin @(negedge clk);frame_sync=1;@(negedge clk);frame_sync=0;end endtask
task acquire; begin label(1);label(0);label(1);label(0);check(!tracking,"initial acquisition locked before five results");label(1);check(tracking && !verifying,"main 3-of-5 acquisition changed");end endtask
initial begin
reset;for(i=0;i<24;i=i+1)begin label(0);frame;check(roi_x0==dut.scan_x(i%6) && roi_y0==dut.scan_y(i/6),"main 24-window search order changed");end
reset;acquire;roi_hold=1;repeat(1100)@(negedge clk);check(tracking,"old one-second/no-result timeout still active");
repeat(60)frame;check(tracking && !verifying && dut.lost_not_count==0,"busy frames incorrectly counted as lost observations");
roi_hold=0;repeat(44)frame;check(tracking && !verifying,"loss check started before 45 idle frames");
@(negedge clk);recheck_tick=1;frame_sync=1;@(negedge clk);recheck_tick=0;frame_sync=0;
check(tracking && verifying && dut.mode==dut.LOST_CHECK,"45-frame loss check lost priority to periodic request");
motion_valid=1;frame;check(tracking && !verifying,"returning local target failed to cancel loss check");
motion_valid=0;repeat(45)frame;last_x=roi_x0;last_y=roi_y0;drone_count_low=0;repeat(5)label(0);
check(!tracking && !verifying && roi_x0==last_x && roi_y0==last_y,"negative 3-of-5 loss check did not release at last ROI");
acquire;run_en=0;repeat(3)@(negedge clk);check(!tracking && !verifying && dut.low_recheck_count==0 && roi_x0==236 && roi_y0==136,"mode exit retained lock/history or changed idle ROI");
run_en=1;repeat(3)@(negedge clk);label(1);check(!tracking,"mode reentry reused stale acquisition history");
if(errors==0)$display("LOCK_POLICY_TEST: PASS");else $display("LOCK_POLICY_TEST: FAIL (%0d errors)",errors);$finish;
end
initial begin #(64'd3_000_000_000);$display("LOCK_POLICY_TEST: FAIL (timeout)");$finish;end
endmodule
