`timescale 1ns / 1ps

module shijue_core(
    input  wire clk,            // �??sys_clk (33.333MHz)
    input  wire clk_75m,
    input  wire clk_24m,
    input  wire rst_n,      
    input  wire vision_mode_sw, 

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
    
    output wire [7:0] out_m1,
    output wire [7:0] out_m2,
    output wire [7:0] out_m3,
    output wire [7:0] out_m4,
    output wire cmd_update
);

    ODDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"), .INIT(1'b0), .SRTYPE("SYNC") 
    ) ODDR_xclk (
        .Q(ov_xclk), .C(clk_24m), .CE(1'b1), .D1(1'b1), .D2(1'b0), .R(1'b0), .S(1'b0)
    );

    wire ov_init_done;
    ov7670_init u_ov7670_init(
        .clk(clk_75m), .rst_n(rst_n),
        .sio_c(ov_sio_c), .sio_d(ov_sio_d), .init_done(ov_init_done)
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
    wire [10:0] box_x;
    wire [10:0] box_y;
    // ===== 新增的宽和高线条 =====
    wire [10:0] box_w;
    wire [10:0] box_h;

    ov7670_capture u_capture(
        .pclk(ov_pclk), .vsync(ov_vsync), .href(ov_href), .din(ov_data),
        .we(ram_we), .waddr(ram_waddr), .dout(ram_wdata),
        .lcd_rd_page(lcd_rd_page_flag), .cam_latest_page(cam_latest_page_flag),
        .track_valid(track_valid), .track_data(track_data), .track_vsync(track_vsync)
    );

    color_track u_tracker(
        .clk(ov_pclk), .rst_n(rst_n),
        .cmos_vsync(track_vsync), .cmos_valid(track_valid), .cmos_data(track_data),    
        .lock_sw(vision_mode_sw), 
        .target_x(box_x), .target_y(box_y),
        .target_w(box_w), .target_h(box_h) // ===== 连入新宽度高�??=====
    );

    frame_buffer_bram u_bram(
        .clka(ov_pclk), .wea(ram_we), .addra(ram_waddr), .dina(ram_wdata),
        .clkb(clk), .addrb(ram_raddr), .doutb(ram_rdata)
    );

    rgb_lcd_driver u_lcd_driver(
        .clk(clk), .rst_n(rst_n),
        .cam_latest_page(cam_latest_page_flag), .lcd_rd_page(lcd_rd_page_flag), 
        .box_x(box_x), .box_y(box_y),
        .box_w(box_w), .box_h(box_h),      // ===== 显示屏连入新宽度高度绘制动态框 =====
        .ram_addr(ram_raddr), .ram_data(ram_rdata),
        .lcd_clk(lcd_clk), .lcd_hs(lcd_hs), .lcd_vs(lcd_vs), .lcd_de(lcd_de),
        .lcd_bl(lcd_bl), .lcd_rst(lcd_rst), .lcd_rgb(lcd_rgb)
    );

    // 红色目标框直接用于底盘跟随，不再经过数字识别门控�?

    wire [7:0] chassis_m1, chassis_m2, chassis_m3, chassis_m4;
    wire       chassis_upd;


    chassis_control u_chassis(
        .clk        (clk),
        .rst_n      (rst_n),
        .sw         (vision_mode_sw),  // 补上缺失的开关信号，激活速度输出
        .box_x      (box_x),
        .box_y      (box_y),
        .box_w      (box_w),           // 接入新宽
        .box_h      (box_h),           // 接入新高
        .out_m1     (chassis_m1),
        .out_m2     (chassis_m2),
        .out_m3     (chassis_m3),
        .out_m4     (chassis_m4),
        .cmd_update (chassis_upd)
    );

    assign out_m1 = chassis_m1;
    assign out_m2 = chassis_m2;
    assign out_m3 = chassis_m3;
    assign out_m4 = chassis_m4;
    assign cmd_update = chassis_upd;

endmodule
