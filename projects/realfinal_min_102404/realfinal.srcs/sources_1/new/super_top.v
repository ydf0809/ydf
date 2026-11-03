// Lower-board mode, motor, arm and camera integration. Mode 3 uses the upper-board bbox.
`timescale 1ns / 1ps

module super_top(
    input  wire sys_clk_pin,
    input  wire rst_n,

    output wire lcd_clk,
    output wire lcd_hs,
    output wire lcd_vs,
    output wire lcd_de,
    output wire lcd_bl,
    output wire lcd_rst,
    output wire [23:0] lcd_rgb,

    output wire ov_xclk,
    output wire ov_sio_c,
    inout  wire ov_sio_d,
    input  wire ov_pclk,
    input  wire ov_href,
    input  wire ov_vsync,
    input  wire [7:0] ov_data,

    output wire us_trig,
    input  wire us_echo,

    output wire motor_scl,
    inout  wire motor_sda,

    output wire arm_uart,
    output wire tcon,

    input  wire link_rx,
    output wire link_tx
);

    // the 2022.2 synthesis engine. Create one explicit global clock net.
    wire sys_clk;
    BUFG u_sys_clk_bufg (
        .I (sys_clk_pin),
        .O (sys_clk)
    );

    wire clk_75m;
    wire clk_24m;

    clk_wiz_0 u_clock(
        .clk_in1 (sys_clk),
        .clk_out1(clk_75m),
        .clk_out2(clk_24m)
    );

    wire vision_en;
    wire defense_en;
    wire xunbi_en ;
    wire arm_en   ;
    wire [7:0] link_peer_cmd;
    wire       link_cmd_valid;

    voice_mode_select u_voice_mode_select (
        .clk       (sys_clk),
        .rst_n     (rst_n),
        .cmd       (link_peer_cmd),
        .cmd_valid (link_cmd_valid),
        .xunbi_en  (xunbi_en),
        .vision_en (vision_en),
        .defense_en(defense_en),
        .arm_en    (arm_en)
    );

    wire arm_voice_rst_n;
    wire arm_stop_cmd;
    wire arm_home_cmd;

    assign arm_stop_cmd = link_cmd_valid && (link_peer_cmd == 8'd4);

    wire arm_home_raw;
    assign arm_home_raw = link_cmd_valid &&
                          ((link_peer_cmd == 8'd1) || (link_peer_cmd == 8'd2));
    reg [1:0] arm_home_dly;
    always @(posedge sys_clk or negedge rst_n) begin
        if(!rst_n) arm_home_dly <= 2'd0;
        else       arm_home_dly <= {arm_home_dly[0], arm_home_raw};
    end

    reg [26:0] pwr_home_cnt;
    always @(posedge sys_clk or negedge rst_n) begin
        if(!rst_n)                              pwr_home_cnt <= 27'd0;
        else if(pwr_home_cnt < 27'd100_000_000) pwr_home_cnt <= pwr_home_cnt + 1'b1;
    end
    wire pwr_home_req = (pwr_home_cnt == (27'd100_000_000 - 1'b1));

    assign arm_home_cmd = arm_home_dly[1] | (pwr_home_req && !defense_en);

    arm_voice_trigger #(
        .CLK_FREQ    (33_333_333),
        .ARM_CMD     (8'd5),
        .RST_HOLD_MS (1)
    ) u_arm_voice_trigger (
        .clk       (sys_clk),
        .rst_n     (rst_n),
        .cmd       (link_peer_cmd),
        .cmd_valid (link_cmd_valid),
        .arm_req   (),
        .arm_rst_n (arm_voice_rst_n)
    );

    wire arm_rst_n;
    assign arm_rst_n = rst_n & arm_voice_rst_n;

    wire pick_arm_uart;
    wire pick_tcon;
    wire track_arm_uart;
    wire track_tcon;

    arm_pick_place_once_top #(
        .CLK_HZ(33333333),
        .STARTUP_WAIT_MS(3000)
    ) u_arm_core (
        .sys_clk  (sys_clk),
        .rst_n    (arm_rst_n),
        .run_en   (arm_en),
        .stop_i   (arm_stop_cmd),
        .home_i   (arm_home_cmd),
        .arm_uart (pick_arm_uart),
        .tcon     (pick_tcon)
    );

    wire [10:0] vision_box_x;
    wire [10:0] vision_box_y;
    wire [10:0] vision_box_w;
    wire [10:0] vision_box_h;
    wire [7:0] vision_m1, vision_m2, vision_m3, vision_m4;
    wire vision_cmd_req;

    shijue_arm_core u_shijue_arm_core (
        .clk              (sys_clk),
        .clk_75m          (clk_75m),
        .clk_24m          (clk_24m),
        .rst_n            (rst_n),

        .vision_mode_sw   (vision_en),

        .lcd_clk(lcd_clk), .lcd_hs(lcd_hs), .lcd_vs(lcd_vs), .lcd_de(lcd_de),
        .lcd_bl(lcd_bl), .lcd_rst(lcd_rst), .lcd_rgb(lcd_rgb),
        .ov_xclk(ov_xclk), .ov_sio_c(ov_sio_c), .ov_sio_d(ov_sio_d),
        .ov_pclk(ov_pclk), .ov_href(ov_href), .ov_vsync(ov_vsync), .ov_data(ov_data),

        .target_x(vision_box_x), .target_y(vision_box_y),
        .target_w(vision_box_w), .target_h(vision_box_h),
        .out_m1(vision_m1), .out_m2(vision_m2),
        .out_m3(vision_m3), .out_m4(vision_m4),
        .cmd_update(vision_cmd_req)
    );

    wire [7:0] xunbi_m1, xunbi_m2, xunbi_m3, xunbi_m4;
    wire xunbi_cmd_req;

    xunbi_core u_xunbi_core (
        .sys_clk   (sys_clk),
        .rst_n     (rst_n),
        .run_en    (xunbi_en),
        .track_l2  (track_pat[4]), .track_l1(track_pat[3]), .track_m(track_pat[2]),
        .track_r1  (track_pat[1]), .track_r2(track_pat[0]),
        .us_trig   (us_trig), .us_echo(us_echo),

        .out_m1(xunbi_m1), .out_m2(xunbi_m2), .out_m3(xunbi_m3), .out_m4(xunbi_m4),
        .cmd_update(xunbi_cmd_req)
    );

    reg [7:0] iic_m1, iic_m2, iic_m3, iic_m4;
    reg iic_cmd_req;

    wire        spin_active;
    wire        spin_req;
    wire [7:0]  spin_m1, spin_m2, spin_m3, spin_m4;

    reg [19:0] stop_cnt;
    reg stop_pulse;
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            stop_cnt <= 20'd0;
            stop_pulse <= 1'b0;
        end else if (!vision_en && !xunbi_en) begin
            if (stop_cnt < 20'd333333) begin
                stop_cnt <= stop_cnt + 1;
                stop_pulse <= 1'b0;
            end else begin
                stop_cnt <= 0;
                stop_pulse <= 1'b1;
            end
        end else begin
            stop_cnt <= 0;
            stop_pulse <= 1'b0;
        end
    end

    always @(*) begin
        if (vision_en) begin
            iic_m1 = vision_m1; iic_m2 = vision_m2; iic_m3 = vision_m3; iic_m4 = vision_m4;
            iic_cmd_req = vision_cmd_req;
        end else if (xunbi_en) begin
            iic_m1 = xunbi_m1; iic_m2 = xunbi_m2; iic_m3 = xunbi_m3; iic_m4 = xunbi_m4;
            iic_cmd_req = xunbi_cmd_req;
        end else if (spin_active) begin

            iic_m1 = spin_m1; iic_m2 = spin_m2; iic_m3 = spin_m3; iic_m4 = spin_m4;
            iic_cmd_req = spin_req;
        end else begin
            iic_m1 = 8'sd0; iic_m2 = 8'sd0; iic_m3 = 8'sd0; iic_m4 = 8'sd0;
            iic_cmd_req = stop_pulse;
        end
    end

    iic_w_top u_motor_iic(
        .sys_clk        (sys_clk),
        .rst_n          (rst_n),
        .SDA            (motor_sda),
        .SCL            (motor_scl),
        .motor1_spd     (iic_m1),
        .motor2_spd     (iic_m2),
        .motor3_spd     (iic_m3),
        .motor4_spd     (iic_m4),
        .cmd_update_req (iic_cmd_req)
    );

    wire       link_peer_valid;
    wire       link_err_flag  ;
    wire [4:0] track_pat      ;
    wire       track_upd      ;
    wire       bbox_rx_busy   ;
    wire       bbox_valid     ;
    wire [9:0] bbox_x         ;
    wire [9:0] bbox_y         ;
    wire [9:0] bbox_w         ;
    wire [9:0] bbox_h         ;
    wire       bbox_label     ;
    wire       bbox_frame_tgl ;

    bbox_unpack #(
        .CLK_FREQ (33_333_333)
    ) u_bbox_unpack (
        .clk             (sys_clk),
        .rst_n           (rst_n),
        .peer_cmd        (link_peer_cmd),
        .peer_valid      (link_peer_valid),
        .bbox_valid      (bbox_valid),
        .bbox_x          (bbox_x),
        .bbox_y          (bbox_y),
        .bbox_w          (bbox_w),
        .bbox_h          (bbox_h),
        .bbox_label      (bbox_label),
        .bbox_frame_tgl  (bbox_frame_tgl),
        .bbox_rx_busy    (bbox_rx_busy)
    );

    link_demux u_link_demux (
        .clk        (sys_clk),
        .rst_n      (rst_n),
        .peer_cmd   (link_peer_cmd),
        .peer_valid (link_peer_valid),
        .bbox_busy  (bbox_rx_busy),
        .track_pat  (track_pat),
        .track_upd  (track_upd),
        .cmd_valid  (link_cmd_valid)
    );

    board_link #(
        .CLK_FREQ (33_333_333),
        .UART_BPS (115200),
        .ECHO_EN  (1'b0)
    ) u_board_link (
        .clk        (sys_clk),
        .rst_n      (rst_n),
        .link_rx    (link_rx),
        .link_tx    (link_tx),
        .local_cmd  (8'd0),
        .local_send (1'b0),
        .peer_cmd   (link_peer_cmd),
        .peer_valid (link_peer_valid),
        .link_err   (link_err_flag)
    );

    wire [10:0] bbox_raw_cx = {1'b0, bbox_x} + {2'b0, bbox_w[9:1]};
    wire [10:0] bbox_raw_cy = {1'b0, bbox_y} + {2'b0, bbox_h[9:1]};
    wire [10:0] bbox_cx = 11'd599 - bbox_raw_cx;
    wire [10:0] bbox_cy = 11'd399 - bbox_raw_cy;

    wire defense_home_req = link_cmd_valid && (link_peer_cmd == 8'd3);
    wire [15:0] track_yaw_pos;

    arm_red_track #(
        .CLK_HZ(33_333_333),
        .BAUD(115_200),
        .CENTER_PITCH(200),
        .CENTER_YAW(300),
        .PITCH_MIN(200),
        .PITCH_MAX(400),
        .YAW_MIN(210),
        .YAW_MAX(750),
        .PITCH3_MIN(600),
        .PITCH3_MAX(800),
        .PITCH_CASCADE_LOW(200),
        .PITCH_CASCADE_HIGH(400),
        .POS4_INIT(300),
        .POS6_INIT(500),
        .POS1_AIR(220),
        .POS2_AIR(500),
        .POS3_INIT(700),
        .POS5_AIR(400),
        .DEADBAND(16),
        .KP_SHIFT(3),

        .STEP_MAX(14),
        .MOVE_TIME_MS(100),
        .HOME_TIME_MS(1000),
        .UPDATE_PERIOD_MS(100),
        .PITCH_SIGN(1),
        .PITCH3_SIGN(-1),
        .YAW_SIGN(1)
    ) u_arm_red_track (
        .clk        (sys_clk),
        .rst_n      (rst_n & defense_en),
        .target_pitch(bbox_cy),
        .target_yaw  (bbox_cx),
        .target_valid(bbox_valid),
        .home_i     (defense_home_req),
        .arm_uart   (track_arm_uart),
        .tx_oe      (track_tcon),
        .dbg_move_time(),
        .dbg_pos3   (),
        .dbg_pos4   (),
        .dbg_pos6   (track_yaw_pos),
        .dbg_servo_id(),
        .dbg_send   (),
        .dbg_busy   ()
    );

    defense_spin #(
        .CLK_HZ      (33_333_333),
        .IMG_W       (600),
        .CENTER_X    (300),
        .BOX_HALF_W  (64),
        .EDGE_PX     (30),
        .YAW_MIN     (210),
        .YAW_MAX     (750),
        .CONFIRM_MS  (300),
        .MIN_SPIN_MS (1000),
        .MAX_SPIN_MS (2000),
        .SPIN_SPEED  (8'sd18),
        .RIGHT_SIGN  (1)
    ) u_defense_spin (
        .clk         (sys_clk),
        .rst_n       (rst_n & defense_en),
        .defense_en  (defense_en),
        .target_valid(bbox_valid),
        .target_cx   (bbox_cx),
        .yaw_pos     (track_yaw_pos),
        .spin_active (spin_active),
        .m1          (spin_m1),
        .m2          (spin_m2),
        .m3          (spin_m3),
        .m4          (spin_m4),
        .cmd_update  (spin_req)
    );

    assign arm_uart = defense_en ? track_arm_uart : pick_arm_uart;
    assign tcon     = defense_en ? track_tcon     : pick_tcon;

endmodule
