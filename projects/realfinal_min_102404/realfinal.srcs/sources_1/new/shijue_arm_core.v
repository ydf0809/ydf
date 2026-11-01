`timescale 1ns / 1ps

// Lower-board OV7670 red-target frontend.
// This variant exposes the color tracker output for the arm gimbal and keeps
// the original chassis_control path for follow mode.
module shijue_arm_core(
    input  wire        clk,
    input  wire        clk_75m,
    input  wire        clk_24m,
    input  wire        rst_n,
    input  wire        vision_mode_sw,

    output wire        lcd_clk,
    output wire        lcd_hs,
    output wire        lcd_vs,
    output wire        lcd_de,
    output wire        lcd_bl,
    output wire        lcd_rst,
    output wire [23:0] lcd_rgb,

    output wire        ov_xclk,
    output wire        ov_sio_c,
    inout  wire        ov_sio_d,
    input  wire        ov_pclk,
    input  wire        ov_href,
    input  wire        ov_vsync,
    input  wire [7:0]  ov_data,

    output wire [10:0] target_x,
    output wire [10:0] target_y,
    output wire [10:0] target_w,
    output wire [10:0] target_h,

    output wire [7:0]  out_m1,
    output wire [7:0]  out_m2,
    output wire [7:0]  out_m3,
    output wire [7:0]  out_m4,
    output wire        cmd_update
);

    ODDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) u_ov_xclk (
        .Q(ov_xclk),
        .C(clk_24m),
        .CE(1'b1),
        .D1(1'b1),
        .D2(1'b0),
        .R(1'b0),
        .S(1'b0)
    );

    wire ov_init_done;
    ov7670_init u_ov7670_init(
        .clk(clk_75m),
        .rst_n(rst_n),
        .sio_c(ov_sio_c),
        .sio_d(ov_sio_d),
        .init_done(ov_init_done)
    );

    wire        ram_we;
    wire [17:0] ram_waddr;
    wire [15:0] ram_wdata;
    wire [17:0] ram_raddr;
    wire [15:0] ram_rdata;
    wire        lcd_rd_page_flag;
    wire        cam_latest_page_flag;

    wire [15:0] track_data;
    wire        track_valid;
    wire        track_vsync;

    ov7670_capture u_capture(
        .pclk(ov_pclk),
        .vsync(ov_vsync),
        .href(ov_href),
        .din(ov_data),
        .we(ram_we),
        .waddr(ram_waddr),
        .dout(ram_wdata),
        .lcd_rd_page(lcd_rd_page_flag),
        .cam_latest_page(cam_latest_page_flag),
        .track_valid(track_valid),
        .track_data(track_data),
        .track_vsync(track_vsync)
    );

    color_track u_tracker(
        .clk(ov_pclk),
        .rst_n(rst_n),
        .cmos_vsync(track_vsync),
        .cmos_valid(track_valid),
        .cmos_data(track_data),
        .lock_sw(vision_mode_sw),
        .target_x(target_x),
        .target_y(target_y),
        .target_w(target_w),
        .target_h(target_h)
    );

    frame_buffer_bram u_bram(
        .clka(ov_pclk),
        .wea(ram_we),
        .addra(ram_waddr),
        .dina(ram_wdata),
        .clkb(clk),
        .addrb(ram_raddr),
        .doutb(ram_rdata)
    );

    rgb_lcd_driver u_lcd_driver(
        .clk(clk),
        .rst_n(rst_n),
        .cam_latest_page(cam_latest_page_flag),
        .lcd_rd_page(lcd_rd_page_flag),
        .box_x(target_x),
        .box_y(target_y),
        .box_w(target_w),
        .box_h(target_h),
        .ram_addr(ram_raddr),
        .ram_data(ram_rdata),
        .lcd_clk(lcd_clk),
        .lcd_hs(lcd_hs),
        .lcd_vs(lcd_vs),
        .lcd_de(lcd_de),
        .lcd_bl(lcd_bl),
        .lcd_rst(lcd_rst),
        .lcd_rgb(lcd_rgb)
    );

    chassis_control u_chassis(
        .clk(clk),
        .rst_n(rst_n),
        .sw(vision_mode_sw),
        .box_x(target_x),
        .box_y(target_y),
        .box_w(target_w),
        .box_h(target_h),
        .out_m1(out_m1),
        .out_m2(out_m2),
        .out_m3(out_m3),
        .out_m4(out_m4),
        .cmd_update(cmd_update)
    );

endmodule
