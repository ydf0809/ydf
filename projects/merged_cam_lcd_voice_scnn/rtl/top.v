// Upper-board camera, SCNN, voice and inter-board control integration.
`timescale 1ns / 1ps

module top(

    input  wire        sys_clk,
    input  wire        sys_rst_n,
    output wire        led,

    input  wire        cam_pclk,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_data,
    output wire        cam_rst_n,
    output wire        cam_pwdn,
    output wire        cam_scl,
    inout  wire        cam_sda,

    output wire        lcd_clk,
    output wire        lcd_hs,
    output wire        lcd_vs,
    output wire        lcd_de,
    output wire        lcd_bl,
    output wire        lcd_rst,
    output wire [23:0] lcd_rgb,

    input  wire        asr_rxd,
    output wire        asr_txd,
    output wire [2:0]  mode,
    output wire        mode_upd,
    output wire        frame_err_flag,

    output wire        link_tx,
    input  wire        link_rx,

    input  wire        track_l2,
    input  wire        track_l1,
    input  wire        track_m,
    input  wire        track_r1,
    input  wire        track_r2
);

    localparam CMOS_H_PIXEL  = 13'd640;
    localparam CMOS_V_PIXEL  = 13'd480;
    localparam TOTAL_H_PIXEL = 13'd1856;
    localparam TOTAL_V_PIXEL = 13'd984;

    wire        clk_33m;
    wire        sys_init_done;

    wire        dri_clk;
    wire        i2c_exec;
    wire        i2c_rh_wl;
    wire        i2c_done;
    wire        i2c_ack;
    wire        cfg_done;
    wire [23:0] i2c_data;
    wire [7:0]  i2c_data_r;

    wire        cmos_frame_vsync;
    wire        cmos_frame_href;
    wire        cmos_frame_valid;
    wire [15:0] cmos_frame_data;

    wire        bbox_valid_now;
    wire [9:0]  bbox_x, bbox_y, bbox_w, bbox_h;
    wire        bbox_frame_tgl;

    wire [15:0] bram_dout;
    wire [15:0] preview_addr;
    wire [15:0] preview_rd_addr;

    wire [7:0]  link_peer_cmd;
    wire        link_peer_valid;
    wire        link_err_flag;
    wire        asr_frame_err_flag;

    BUFG u_bufg_sys (.I(sys_clk), .O(clk_33m));

    assign sys_init_done = sys_rst_n;
    assign lcd_clk = clk_33m;

    assign cam_rst_n = 1'b1;
    assign cam_pwdn  = 1'b0;

    i2c_dri #(
        .SLAVE_ADDR (7'h3C),
        .CLK_FREQ   (33_333_333),
        .I2C_FREQ   (250_000)
    ) u_i2c_dri (
        .clk         (clk_33m),
        .rst_n       (sys_init_done),
        .i2c_exec    (i2c_exec),
        .bit_ctrl    (1'b1),
        .i2c_rh_wl   (i2c_rh_wl),
        .i2c_addr    (i2c_data[23:8]),
        .i2c_data_w  (i2c_data[7:0]),
        .i2c_data_r  (i2c_data_r),
        .i2c_done    (i2c_done),
        .i2c_ack     (i2c_ack),
        .scl         (cam_scl),
        .sda         (cam_sda),
        .dri_clk     (dri_clk)
    );

    i2c_ov5640_rgb565_cfg u_i2c_cfg (
        .clk            (dri_clk),
        .rst_n          (sys_init_done),
        .i2c_data_r     (i2c_data_r),
        .i2c_done       (i2c_done),
        .cmos_h_pixel   (CMOS_H_PIXEL),
        .cmos_v_pixel   (CMOS_V_PIXEL),
        .total_h_pixel  (TOTAL_H_PIXEL),
        .total_v_pixel  (TOTAL_V_PIXEL),
        .i2c_exec       (i2c_exec),
        .i2c_data       (i2c_data),
        .i2c_rh_wl      (i2c_rh_wl),
        .init_done      (cfg_done)
    );

    ov5640_capture #(
        .PIX_W   (640),
        .PIX_H   (480),
        .CAP_X0  (20),
        .CAP_Y0  (40),
        .CAP_W   (600),
        .CAP_H   (400)
    ) u_ov5640_capture (
        .sys_rst_n         (sys_init_done),
        .cfg_done          (cfg_done),
        .cam_pclk          (cam_pclk),
        .cam_vsync         (cam_vsync),
        .cam_href          (cam_href),
        .cam_data          (cam_data),
        .cmos_frame_vsync  (cmos_frame_vsync),
        .cmos_frame_href   (cmos_frame_href),
        .cmos_frame_valid  (cmos_frame_valid),
        .cmos_frame_data   (cmos_frame_data)
    );

    reg vsync_d0, vsync_d1;
    reg href_d0,  href_d1;
    reg [9:0] img_x, img_y;

    always @(posedge cam_pclk or negedge sys_init_done) begin
        if(!sys_init_done) begin
            vsync_d0 <= 1'b0; vsync_d1 <= 1'b0;
            href_d0  <= 1'b0; href_d1  <= 1'b0;
        end else begin
            vsync_d0 <= cmos_frame_vsync; vsync_d1 <= vsync_d0;
            href_d0  <= cmos_frame_href;  href_d1  <= href_d0;
        end
    end
    wire vsync_pos = vsync_d0 & ~vsync_d1;
    wire href_neg  = ~href_d0 & href_d1;

    always @(posedge cam_pclk or negedge sys_init_done) begin
        if(!sys_init_done) begin
            img_x <= 10'd0;
            img_y <= 10'd0;
        end else if(vsync_pos) begin
            img_x <= 10'd0;
            img_y <= 10'd0;
        end else if(cmos_frame_href) begin
            if(cmos_frame_valid)
                img_x <= img_x + 1'b1;
        end else if(href_neg) begin
            img_x <= 10'd0;
            if(img_y != 10'd479)
                img_y <= img_y + 1'b1;
        end
    end

    wire        preview_we    = cmos_frame_valid && ~img_x[0] && ~img_y[0];
    wire [7:0]  preview_y     = (img_y - 10'd40) >> 1;
    wire [8:0]  preview_x     = img_x[9:1];
    wire [8:0]  crop_y        = img_y - 10'd40;
    wire [15:0] preview_waddr = preview_y * 16'd300 + {7'b0, preview_x};

    frame_buffer #(
        .DEPTH  (60000),
        .ADDR_W (16),
        .DATA_W (16)
    ) u_preview_buffer (
        .clk_wr  (cam_pclk),
        .wr_en   (preview_we),
        .wr_addr (preview_waddr),
        .wr_data (cmos_frame_data),
        .clk_rd  (clk_33m),
        .rd_addr (preview_rd_addr),
        .rd_data (bram_dout)
    );

    wire drone_mode_sys = (mode == 3'd3);
    wire drone_restart_command = mode_upd && (mode==3'd3);
    reg [3:0] tracker_restart_count;
    reg tracker_restart_toggle;
    always @(posedge clk_33m or negedge sys_init_done) begin
        if(!sys_init_done)begin tracker_restart_count<=0;tracker_restart_toggle<=0;end
        else if(drone_restart_command)begin
            tracker_restart_count<=15;tracker_restart_toggle<=~tracker_restart_toggle;
        end else if(tracker_restart_count!=0)tracker_restart_count<=tracker_restart_count-1'b1;
    end
    wire tracker_reset_request_n = sys_init_done && drone_mode_sys &&
                                   !drone_restart_command && (tracker_restart_count==0);
    (* ASYNC_REG="TRUE" *) reg restart_cam0,restart_cam1;
    reg restart_cam2;
    always @(posedge cam_pclk or negedge sys_init_done) begin
        if(!sys_init_done)begin restart_cam0<=0;restart_cam1<=0;restart_cam2<=0;end
        else begin restart_cam0<=tracker_restart_toggle;restart_cam1<=restart_cam0;restart_cam2<=restart_cam1;end
    end
    wire restart_snapshot_cam=restart_cam1^restart_cam2;
    (* ASYNC_REG="TRUE" *) reg [1:0] tracker_sys_release;
    (* ASYNC_REG="TRUE" *) reg [1:0] tracker_cam_release;
    always @(posedge clk_33m or negedge tracker_reset_request_n) begin
        if (!tracker_reset_request_n) tracker_sys_release <= 2'b00;
        else tracker_sys_release <= {tracker_sys_release[0], 1'b1};
    end
    always @(posedge cam_pclk or negedge tracker_reset_request_n) begin
        if (!tracker_reset_request_n) tracker_cam_release <= 2'b00;
        else tracker_cam_release <= {tracker_cam_release[0], 1'b1};
    end
    wire tracker_sys_rst_n = tracker_sys_release[1];
    wire tracker_cam_rst_n = tracker_cam_release[1];
    localparam [5:0] RECHECK_SPIKE_THRESHOLD = 6'd15;
    wire        motion_valid;
    wire        track_found;
    wire [8:0]  motion_x0;
    wire [8:0]  motion_x1;
    wire [7:0]  motion_y0;
    wire [7:0]  motion_y1;
    wire [13:0] motion_count;
    wire [6:0]  motion_dbg_best;
    wire [15:0] motion_dbg_total;
    wire [9:0]  roi_x0;
    wire [8:0]  roi_y0;
    wire        roi_tracking;
    wire        roi_verifying;

    motion_detector u_motion (
        .clk          (cam_pclk),
        .rst_n        (tracker_cam_rst_n),
        .frame_sync   (vsync_pos),
        .pix_we       (preview_we),
        .pix_x        (preview_x),
        .pix_y        (preview_y),
        .pix_rgb565   (cmos_frame_data),
        .track_enable (roi_tracking),
        .track_x0     (roi_x0),
        .track_y0     (roi_y0),
        .box_valid    (motion_valid),
        .track_found  (track_found),
        .box_x0       (motion_x0),
        .box_x1       (motion_x1),
        .box_y0       (motion_y0),
        .box_y1       (motion_y1),
        .motion_count (motion_count),
        .dbg_best     (motion_dbg_best),
        .dbg_total    (motion_dbg_total)
    );

    wire        snn_busy;
    wire        snn_done;
    wire        snn_label_valid;
    wire [0:0]  snn_label;
    wire [5:0]  snn_count;
    wire [11:0] snn_all_counts;
    wire snn_drone_margin=({1'b0,snn_all_counts[11:6]} >=
                           {1'b0,snn_all_counts[5:0]}+7'd8);

    reg        label_toggle_33;
    reg        label_drone_33;
    reg        label_low_33;
    reg        label_t0, label_t1, label_t2;
    reg        label_drone_cam0, label_drone_cam1;
    (* ASYNC_REG="TRUE" *) reg label_low_cam0, label_low_cam1;
    always @(posedge clk_33m or negedge tracker_sys_rst_n) begin
        if (!tracker_sys_rst_n) begin
            label_toggle_33 <= 1'b0;
            label_drone_33  <= 1'b0;
            label_low_33   <= 1'b0;
        end else if (snn_label_valid) begin
            label_toggle_33 <= ~label_toggle_33;

            label_drone_33  <= snn_drone_margin;
            label_low_33   <= (snn_all_counts[11:6] <= RECHECK_SPIKE_THRESHOLD);
        end
    end

    always @(posedge cam_pclk or negedge tracker_cam_rst_n) begin
        if (!tracker_cam_rst_n) begin
            label_t0         <= 1'b0;
            label_t1         <= 1'b0;
            label_t2         <= 1'b0;
            label_drone_cam0 <= 1'b0;
            label_drone_cam1 <= 1'b0;
            label_low_cam0  <= 1'b0;
            label_low_cam1  <= 1'b0;
        end else begin
            label_t0         <= label_toggle_33;
            label_t1         <= label_t0;
            label_t2         <= label_t1;
            label_drone_cam0 <= label_drone_33;
            label_drone_cam1 <= label_drone_cam0;
            label_low_cam0  <= label_low_33;
            label_low_cam1  <= label_low_cam0;
        end
    end
    wire label_pulse_cam = label_t1 ^ label_t2;
    wire label_drone_cam = label_drone_cam1;
    wire periodic_recheck_toggle;
    wire tracking_for_recheck;
    (* ASYNC_REG="TRUE" *) reg recheck_cam0, recheck_cam1, recheck_cam2;
    reg roi_tracking_cam;
    (* ASYNC_REG="TRUE" *) reg roi_tracking_sys0, roi_tracking_sys1;
    always @(posedge cam_pclk or negedge tracker_cam_rst_n) begin
        if (!tracker_cam_rst_n) roi_tracking_cam <= 1'b0;
        else roi_tracking_cam <= roi_tracking;
    end
    always @(posedge clk_33m or negedge tracker_sys_rst_n) begin
        if (!tracker_sys_rst_n) begin
            roi_tracking_sys0 <= 1'b0;
            roi_tracking_sys1 <= 1'b0;
        end else begin
            roi_tracking_sys0 <= roi_tracking_cam;
            roi_tracking_sys1 <= roi_tracking_sys0;
        end
    end
    assign tracking_for_recheck = tracker_sys_rst_n && roi_tracking_sys1;
    periodic_recheck_timer #(.INTERVAL_CYCLES(33333333)) u_periodic_recheck_timer (
        .clk(clk_33m), .rst_n(tracker_sys_rst_n),
        .tracking(tracking_for_recheck), .request_toggle(periodic_recheck_toggle)
    );
    always @(posedge cam_pclk or negedge tracker_cam_rst_n) begin
        if (!tracker_cam_rst_n) begin
            recheck_cam0 <= 1'b0;
            recheck_cam1 <= 1'b0;
            recheck_cam2 <= 1'b0;
        end else begin
            recheck_cam0 <= periodic_recheck_toggle;
            recheck_cam1 <= recheck_cam0;
            recheck_cam2 <= recheck_cam1;
        end
    end
    wire periodic_recheck_tick = recheck_cam1 ^ recheck_cam2;

    wire net_capture_en;
    reg        roi_result_pending;
    reg        roi_capture_active;
    reg snn_busy_cam0, snn_busy_cam1;
    roi_scheduler u_roi_scheduler (
        .clk          (cam_pclk),
        .rst_n        (tracker_cam_rst_n),
        .frame_sync   (vsync_pos),

        .roi_hold     (roi_result_pending || roi_capture_active || snn_busy_cam1),
        .label_valid  (label_pulse_cam),
        .is_drone     (label_drone_cam),
        .drone_count_low(label_low_cam1),
        .recheck_tick (periodic_recheck_tick),
        .motion_valid (roi_tracking ? track_found : motion_valid),
        .motion_x0    (motion_x0),
        .motion_x1    (motion_x1),
        .motion_y0    (motion_y0),
        .motion_y1    (motion_y1),
        .roi_x0       (roi_x0),
        .roi_y0       (roi_y0),
        .tracking     (roi_tracking),
        .verifying    (roi_verifying)
    );

    always @(posedge cam_pclk or negedge tracker_cam_rst_n) begin
        if (!tracker_cam_rst_n) begin
            snn_busy_cam0 <= 1'b0;
            snn_busy_cam1 <= 1'b0;
        end else begin
            snn_busy_cam0 <= snn_busy;
            snn_busy_cam1 <= snn_busy_cam0;
        end
    end

    assign net_capture_en = tracker_cam_rst_n && cfg_done && !snn_busy_cam1 && !roi_result_pending &&
                            (!roi_tracking || roi_verifying);

    wire        net_we;
    wire [11:0] net_addr;
    wire [23:0] net_rgb;
    wire        net_done;
    reg frame_toggle;
    reg write_bank;
    reg ready_bank;

    always @(posedge cam_pclk or negedge tracker_cam_rst_n) begin
        if (!tracker_cam_rst_n) begin
            roi_result_pending <= 1'b0;
            roi_capture_active <= 1'b0;
        end else begin
            if(label_pulse_cam) roi_result_pending<=1'b0;
            else if(vsync_pos && net_capture_en) roi_result_pending<=1'b1;
            if(net_done) roi_capture_active<=1'b0;
            else if(vsync_pos && net_capture_en) roi_capture_active<=1'b1;
        end
    end

    roi_resampler u_roi_resampler (
        .clk          (cam_pclk),
        .rst_n        (tracker_cam_rst_n),
        .frame_sync   (vsync_pos),
        .enable       (net_capture_en || roi_capture_active),
        .roi_x        (roi_x0),
        .roi_y        (roi_y0),
        .pixel_valid  (cmos_frame_valid),
        .pixel_x      (img_x),
        .pixel_y      (crop_y),
        .pixel_rgb565 (cmos_frame_data),
        .out_we       (net_we),
        .out_addr     (net_addr),
        .out_data     (net_rgb),
        .frame_done   (net_done)
    );

    always @(posedge cam_pclk or negedge tracker_cam_rst_n) begin
        if (!tracker_cam_rst_n) begin
            frame_toggle <= 1'b0;
            write_bank   <= 1'b0;
            ready_bank   <= 1'b0;
        end else if (net_done) begin
            frame_toggle <= ~frame_toggle;
            ready_bank   <= write_bank;
            write_bank   <= ~write_bank;
        end
    end
    wire [12:0] net_wr_addr = {write_bank, net_addr};

    wire        start_pulse;
    wire        read_bank;
    wire        frame_new;
    reg         ready_b0, ready_b1, ready_b2;

    reg frame_t0, frame_t1, frame_t2;
    always @(posedge clk_33m or negedge tracker_sys_rst_n) begin
        if (!tracker_sys_rst_n) begin
            frame_t0 <= 1'b0;
            frame_t1 <= 1'b0;
            frame_t2 <= 1'b0;
            ready_b0 <= 1'b0;
            ready_b1 <= 1'b0;
            ready_b2 <= 1'b0;
        end else begin
            frame_t0 <= frame_toggle;
            frame_t1 <= frame_t0;
            frame_t2 <= frame_t1;
            ready_b0 <= ready_bank;
            ready_b1 <= ready_b0;
            ready_b2 <= ready_b1;
        end
    end
    assign frame_new = frame_t1 ^ frame_t2;
    assign start_pulse = tracker_sys_rst_n && frame_new && !snn_busy;
    assign read_bank = ready_b2;

    reg        result_is_drone;
    reg [5:0]  result_drone_count;
    reg [5:0]  result_not_drone_count;
    reg        result_valid;
    always @(posedge clk_33m or negedge tracker_sys_rst_n) begin
        if (!tracker_sys_rst_n) begin
            result_is_drone <= 1'b0;
            result_drone_count     <= 6'd0;
            result_not_drone_count <= 6'd0;
            result_valid    <= 1'b0;
        end else begin
            if (snn_label_valid) begin
                result_is_drone <= snn_drone_margin;
                result_drone_count     <= snn_all_counts[11:6];
                result_not_drone_count <= snn_all_counts[5:0];
                result_valid    <= 1'b1;
            end
        end
    end

    snn_cnn_top #(
        .P_IN_H(64),
        .P_IN_W(64),
        .P_CIN(3),
        .P_C1(8),
        .P_C2(16),
        .P_NUM_OUT(2),
        .P_T_MAX(50)
    ) u_snn (
        .clk(clk_33m),
        .i_frame_clk(cam_pclk),
        .rst_n(tracker_sys_rst_n),
        .i_start_image(start_pulse),
        .o_busy(snn_busy),
        .o_done_image(snn_done),
        .o_label(snn_label),
        .o_max_count(snn_count),
        .o_all_spike_counts(snn_all_counts),
        .o_label_valid(snn_label_valid),
        .i_frame_bank(read_bank),
        .i_frame_we(net_we),
        .i_frame_addr(net_wr_addr),
        .i_frame_data(net_rgb)
    );

    reg [9:0] bbox_x_cam, bbox_y_cam;
    reg bbox_valid_cam, bbox_tgl_r, bbox_lock_d;
    assign bbox_x = bbox_x_cam;
    assign bbox_y = bbox_y_cam;
    assign bbox_w = 10'd128;
    assign bbox_h = 10'd128;
    assign bbox_valid_now = bbox_valid_cam && tracker_sys_rst_n;
    assign bbox_frame_tgl = bbox_tgl_r;
    always @(posedge cam_pclk or negedge sys_init_done) begin
        if(!sys_init_done) begin
            bbox_x_cam<=10'd236; bbox_y_cam<=10'd136;
            bbox_valid_cam<=0; bbox_tgl_r<=0; bbox_lock_d<=0;
        end else if(!tracker_cam_rst_n || restart_snapshot_cam) begin
            bbox_x_cam<=10'd236;bbox_y_cam<=10'd136;
            bbox_valid_cam<=0;bbox_lock_d<=0;
            if(bbox_valid_cam || restart_snapshot_cam)bbox_tgl_r<=~bbox_tgl_r;
        end else begin
            bbox_lock_d<=roi_tracking;
            if((vsync_pos && roi_tracking) || (roi_tracking!=bbox_lock_d)) begin
                bbox_x_cam<=roi_x0;
                bbox_y_cam<={1'b0,roi_y0};
                bbox_valid_cam<=roi_tracking;
                bbox_tgl_r<=~bbox_tgl_r;
            end
        end
    end

    lcd_cam_text_scnn u_lcd (
        .clk             (clk_33m),
        .rst_n           (sys_init_done),
        .pixel_data      (bram_dout),
        .drone_count     (result_drone_count),
        .not_drone_count (result_not_drone_count),
        .roi_x           (roi_x0),
        .roi_y           (roi_y0),
        .locked          (roi_tracking),
        .tracker_enabled (drone_mode_sys && tracker_sys_rst_n),
        .lcd_hs          (lcd_hs),
        .lcd_vs          (lcd_vs),
        .lcd_de          (lcd_de),
        .lcd_rgb         (lcd_rgb),
        .fb_rd_addr      (preview_rd_addr)
    );

    top_asr_voice #(
        .CLK_FREQ (33_333_333),
        .UART_BPS (115200),
        .ECHO_EN  (1'b1)
    ) u_top_asr_voice (
        .sys_clk        (clk_33m),
        .btn_n          (sys_rst_n),
        .asr_rxd        (asr_rxd),
        .asr_txd        (asr_txd),
        .mode           (mode),
        .mode_upd       (mode_upd),
        .frame_err_flag (asr_frame_err_flag)
    );

    wire [7:0] link_local_cmd;
    wire       link_local_send;
    wire       link_local_busy;
    wire       bbox_send_busy;

    upper_link_send #(
        .CLK_FREQ        (33_333_333),
        .TRACK_PERIOD_US (1000)
    ) u_upper_link_send (
        .clk        (clk_33m),
        .rst_n      (sys_init_done),
        .track_l2   (track_l2),
        .track_l1   (track_l1),
        .track_m    (track_m),
        .track_r1   (track_r1),
        .track_r2   (track_r2),
        .mode_upd   (mode_upd),
        .mode_cmd   ({5'b0, mode}),
        .bbox_x     (bbox_x),
        .bbox_y     (bbox_y),
        .bbox_w     (bbox_w),
        .bbox_h     (bbox_h),
        .bbox_valid (bbox_valid_now),
        .bbox_tgl   (bbox_frame_tgl),
        .link_busy  (link_local_busy),
        .local_cmd  (link_local_cmd),
        .local_send (link_local_send),
        .bbox_busy  (bbox_send_busy)
    );

    board_link #(
        .CLK_FREQ (33_333_333),
        .UART_BPS (115200),
        .ECHO_EN  (1'b0)
    ) u_board_link (
        .clk        (clk_33m),
        .rst_n      (sys_init_done),
        .link_rx    (link_rx),
        .link_tx    (link_tx),
        .local_cmd  (link_local_cmd),
        .local_send (link_local_send),
        .peer_cmd   (link_peer_cmd),
        .peer_valid (link_peer_valid),
        .local_busy (link_local_busy),
        .link_err   (link_err_flag)
    );

    assign frame_err_flag = asr_frame_err_flag | link_err_flag;

    assign lcd_bl  = 1'b1;
    assign lcd_rst = 1'b1;

    reg [24:0] blink_cnt;
    reg        blink;
    always @(posedge clk_33m or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            blink_cnt <= 25'd0;
            blink     <= 1'b0;
        end else if(cfg_done) begin
            if(blink_cnt == 25'd16_666_666 - 1'b1) begin
                blink_cnt <= 25'd0;
                blink     <= ~blink;
            end else begin
                blink_cnt <= blink_cnt + 1'b1;
            end
        end else begin
            blink_cnt <= 25'd0;
            blink     <= 1'b0;
        end
    end

    wire drone_flag = result_valid && result_is_drone;
    assign led = drone_flag ? 1'b1 : blink;

endmodule
