`timescale 1ns / 1ps
module tb_integrated_recheck_cdc;
    reg sys_clk = 0;
    reg cam_pclk = 0;
    reg rst_n = 0;
    reg injected_valid = 0;
    reg [11:0] injected_counts = 0;
    wire cam_sda;
    integer errors = 0;
    integer i;

    always #15 sys_clk = ~sys_clk;
    always #20 cam_pclk = ~cam_pclk;

    top dut (
        .sys_clk(sys_clk), .sys_rst_n(rst_n),
        .cam_pclk(cam_pclk), .cam_vsync(1'b0), .cam_href(1'b0),
        .cam_data(8'd0), .cam_sda(cam_sda),
        .asr_rxd(1'b1), .link_rx(1'b1),
        .track_l2(1'b0), .track_l1(1'b0), .track_m(1'b0),
        .track_r1(1'b0), .track_r2(1'b0)
    );
    defparam dut.u_periodic_recheck_timer.INTERVAL_CYCLES = 200;
    pullup(cam_sda);

    task check;
        input condition;
        input [8*100-1:0] message;
        begin
            if (!condition) begin
                $display("ERROR: %0s", message);
                errors = errors + 1;
            end
        end
    endtask

    task label;
        input [5:0] drone_spikes;
        begin
            @(negedge sys_clk);
            injected_counts = {drone_spikes, 6'd0};
            injected_valid = 1;
            @(negedge sys_clk);
            injected_valid = 0;
            repeat (6) @(negedge cam_pclk);
        end
    endtask

    task next_periodic;
        begin
            wait (dut.roi_tracking && dut.roi_verifying);
            @(negedge cam_pclk);
        end
    endtask

    initial begin
        force dut.mode = 3'd3;
        force dut.cfg_done = 1'b0;
        force dut.snn_label_valid = injected_valid;
        force dut.snn_all_counts = injected_counts;
        repeat (5) @(negedge sys_clk);
        rst_n = 1;
        repeat (8) @(negedge cam_pclk);

        for (i = 0; i < 5; i = i + 1) label(50);
        check(dut.roi_tracking, "CDC fixture did not acquire lock");
        check(dut.bbox_valid_now, "locked target was not exported as valid");
        // Exercise the actual capture/pending handshake as well as result CDC.
        force dut.snn_busy = 1'b0;
        force dut.cfg_done = 1'b1;
        repeat (3) @(negedge cam_pclk);
        check(!dut.net_capture_en, "normal locked tracking kept continuous SCNN capture");
        next_periodic;
        check(dut.net_capture_en, "periodic verification did not enable an RGB capture");
        force dut.vsync_pos = 1'b1;
        @(negedge cam_pclk);
        force dut.vsync_pos = 1'b0;
        @(negedge cam_pclk);
        check(dut.roi_result_pending && dut.roi_capture_active && !dut.net_capture_en,
              "scheduled crop was not held as one pending transaction");
        force dut.net_done = 1'b1;
        @(negedge cam_pclk);
        release dut.net_done;
        @(negedge cam_pclk);
        check(!dut.roi_capture_active && dut.roi_result_pending,
              "capture completion cleared the pending classifier result too early");
        label(50);
        check(dut.roi_tracking && !dut.roi_verifying && !dut.roi_result_pending &&
              !dut.net_capture_en, "completed periodic result failed to resume locked-only tracking");
        force dut.cfg_done = 1'b0;


        for (i = 0; i < 4; i = i + 1) begin
            next_periodic;
            label(i == 0 ? 0 : (i == 1 ? 1 : 10));
            check(dut.roi_tracking && !dut.roi_verifying,
                  "low classification dropped lock before five checks");
        end
        next_periodic;
        label(11);
        check(dut.roi_tracking && dut.u_roi_scheduler.low_recheck_count == 0,
              "count 11 did not clear consecutive-low count across CDC");
        check(dut.label_drone_cam && !dut.label_low_cam1,
              "raw count-11 result was misqualified across CDC");

        for (i = 0; i < 4; i = i + 1) begin
            next_periodic;
            label(i == 0 ? 0 : (i == 1 ? 1 : 10));
            check(dut.roi_tracking, "post-11 low streak ended too early");
        end
        next_periodic;
        label(i == 0 ? 0 : (i == 1 ? 1 : 10));
        check(!dut.roi_tracking && !dut.roi_verifying,
              "fifth consecutive raw low did not release lock");
        check(!dut.bbox_valid_now, "released target remained valid on the board link");

        if (errors == 0) $display("INTEGRATED_RECHECK_CDC_TEST: PASS");
        else $display("INTEGRATED_RECHECK_CDC_TEST: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("INTEGRATED_RECHECK_CDC_TEST: FAIL (timeout)");
        $finish;
    end
endmodule
