`timescale 1ns / 1ps
module tb_air_defence_mode;
    reg sys_clk=0, cam_pclk=0, rst_n=0, asr_rxd=1;
    reg injected_valid=0, injected_frame=0;
    reg [11:0] injected_counts=0;
    wire cam_sda;
    integer errors=0, i, saved_h;
    always #15 sys_clk=~sys_clk;
    always #20 cam_pclk=~cam_pclk;
    top dut (
        .sys_clk(sys_clk), .sys_rst_n(rst_n),
        .cam_pclk(cam_pclk), .cam_vsync(1'b0), .cam_href(1'b0),
        .cam_data(8'd0), .cam_sda(cam_sda),
        .asr_rxd(asr_rxd), .link_rx(1'b1),
        .track_l2(1'b0), .track_l1(1'b0), .track_m(1'b0),
        .track_r1(1'b0), .track_r2(1'b0)
    );
    pullup(cam_sda);
    task check;
        input condition;
        input [8*120-1:0] message;
        begin
            if (condition !== 1'b1) begin
                $display("ERROR: %0s",message); errors=errors+1;
            end
        end
    endtask
    task uart_byte;
        input [7:0] value;
        integer b;
        begin
            asr_rxd=0; #8680;
            for(b=0;b<8;b=b+1) begin asr_rxd=value[b]; #8680; end
            asr_rxd=1; #8680;
        end
    endtask
    task set_mode;
        input [7:0] value;
        begin
            uart_byte(8'hAA); uart_byte(8'h55); uart_byte(value);
            uart_byte(8'h55); uart_byte(8'hAA);
            repeat(12) @(negedge cam_pclk);
            check(dut.mode==value[2:0],"actual ASR UART mode command failed");
        end
    endtask
    task label;
        begin
            @(negedge sys_clk); injected_counts={6'd50,6'd0}; injected_valid=1;
            @(negedge sys_clk); injected_valid=0;
            repeat(6) @(negedge cam_pclk);
        end
    endtask
    task check_disabled;
        begin
            repeat(12) @(negedge cam_pclk);
            check(!dut.tracker_sys_rst_n && !dut.tracker_cam_rst_n,
                  "non-air mode did not hold both tracker domains in reset");
            check(!dut.net_capture_en && !dut.start_pulse && !dut.snn_busy,
                  "non-air mode is capturing or classifying");
            check(!dut.roi_tracking && !dut.roi_verifying && !dut.bbox_valid_now,
                  "non-air mode retained lock or outgoing valid bbox");
            check(!dut.motion_valid && !dut.track_found,
                  "non-air mode retained a search candidate");
            check(dut.u_periodic_recheck_timer.count==0 &&
                  dut.u_roi_scheduler.low_recheck_count==0,
                  "non-air mode retained recheck interval or low streak");
            check(!dut.roi_result_pending && !dut.roi_capture_active &&
                  !dut.result_valid && dut.result_drone_count==0,
                  "non-air mode retained a stale capture or classification");
            saved_h=dut.u_lcd.h_cnt;
            repeat(3) @(negedge sys_clk);
            check(dut.u_lcd.h_cnt != saved_h,"mode disable stopped LCD timing");
        end
    endtask
    initial begin
        force dut.cfg_done=1'b1;
        force dut.snn_label_valid=injected_valid;
        force dut.snn_all_counts=injected_counts;
        force dut.vsync_pos=injected_frame;
        repeat(5) @(negedge sys_clk); rst_n=1;
        check_disabled;
        // Stray/late positive results cannot lock the default mode.
        for(i=0;i<5;i=i+1) label;
        check_disabled;
        set_mode(3);
        check(dut.net_capture_en,
              "air defence did not enable search");
        for(i=0;i<5;i=i+1) label;
        check(dut.roi_tracking,"air defence did not acquire lock");
        repeat(12) @(negedge cam_pclk);
        check(dut.bbox_valid_now,"locked bbox was not exported");
        // Repeating command 03 must start a new tracker session, even if mode stays 03.
        set_mode(3);
        repeat(24) @(negedge cam_pclk);
        check(!dut.roi_tracking && !dut.bbox_valid_now &&
              dut.u_roi_scheduler.hist_count==0 && dut.u_roi_scheduler.low_recheck_count==0,
              "repeated air-defence command retained the old lock or history");
        check(dut.roi_x0==236 && dut.roi_y0==136 &&
              !dut.roi_result_pending && !dut.roi_capture_active && !dut.result_valid,
              "repeated air-defence command retained ROI or pending results");
        for(i=0;i<4;i=i+1) label;
        check(!dut.roi_tracking,"repeated command reused old acquisition evidence");
        label; check(dut.roi_tracking,"fresh lock failed after repeated command");
        set_mode(2); check_disabled;
        for(i=0;i<5;i=i+1) label;
        check_disabled;
        set_mode(1); check_disabled;
        set_mode(4); check_disabled;
        set_mode(5); check_disabled;
        set_mode(0); check_disabled;
        set_mode(3);
        check(!dut.roi_tracking && dut.u_roi_scheduler.hist_count==0,
              "re-entering air defence resurrected a stale lock");
        for(i=0;i<4;i=i+1) label;
        check(!dut.roi_tracking,"air defence reused previous acquisition history");
        label; check(dut.roi_tracking,"fresh acquisition failed after re-entry");
        // Mode exit during a pending capture must cancel its transaction.
        set_mode(4); check_disabled;
        set_mode(3);
        @(negedge cam_pclk); injected_frame=1;
        @(negedge cam_pclk); injected_frame=0;
        check(dut.roi_result_pending && dut.roi_capture_active,
              "pending capture fixture did not start");
        set_mode(3);
        repeat(24) @(negedge cam_pclk);
        check(dut.net_capture_en && !dut.roi_result_pending && !dut.roi_capture_active,
              "repeated command failed to cancel an in-flight capture");
        set_mode(5); check_disabled;
        set_mode(3);
        check(dut.net_capture_en && !dut.roi_result_pending,
              "cancelled capture blocked search after re-entry");
        // Complete a synthetic crop and enter the actual SCNN busy state.
        @(negedge cam_pclk); injected_frame=1;
        @(negedge cam_pclk); injected_frame=0;
        force dut.net_done=1'b1;
        @(negedge cam_pclk);
        release dut.net_done;
        repeat(20) @(negedge sys_clk);
        check(dut.snn_busy,"in-flight SCNN fixture did not start");
        set_mode(3);
        repeat(24) @(negedge cam_pclk);
        check(dut.net_capture_en && !dut.snn_busy && !dut.frame_new &&
              !dut.roi_result_pending && !dut.roi_capture_active &&
              !dut.roi_tracking && dut.u_roi_scheduler.hist_count==0,
              "repeated command failed to cancel active SCNN or replayed its old frame");
        set_mode(2); check_disabled;
        set_mode(3);
        repeat(12) @(negedge cam_pclk);
        check(dut.net_capture_en && !dut.snn_busy && !dut.frame_new &&
              dut.u_roi_scheduler.hist_count==0,
              "mode exit failed to cancel SCNN or replayed an old frame/result");
        if(errors==0) $display("AIR_DEFENCE_MODE_TEST: PASS");
        else $display("AIR_DEFENCE_MODE_TEST: FAIL (%0d errors)",errors);
        $finish;
    end
    initial begin #10000000; $display("AIR_DEFENCE_MODE_TEST: FAIL (timeout)"); $finish; end
endmodule
