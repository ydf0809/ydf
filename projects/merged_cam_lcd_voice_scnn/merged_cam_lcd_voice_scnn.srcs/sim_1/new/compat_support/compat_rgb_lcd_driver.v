`timescale 1ns / 1ps
//============================================================================
// rgb_lcd_driver.v
//  ATK-4384 (4.3�?800x480 RGB888) 驱动，DE 模式，像素时�?= sys_clk 33.333MHz
//  画面�?00x400 摄像头图�?1:1 居中显示�?x=250~549, y=40~439
//  叠加：色块跟踪框（红色），框参数在每帧开始时锁存，避免画面内抖动
//  时序参数取自 robeipingzhengchang/project_97（该工程在本板上已跑通）�?//    H: SYNC=128 BACK=88 DISP=800 FRONT=40 TOTAL=1056
//    V: SYNC=2   BACK=33 DISP=480 FRONT=10 TOTAL=525
//    33.333MHz / (1056*525) = 60.1Hz
//============================================================================
module compat_rgb_lcd_driver(
    input  wire        clk,               // 33.333MHz 像素时钟（直接同源系统时钟）
    input  wire        rst_n,

    input  wire        cam_latest_page,   // 采集模块刚写完的页（pclk 域）
    output reg         lcd_rd_page,       // 当前正在读的页，每帧开始时更新

    input  wire [10:0] box_x,
    input  wire [10:0] box_y,
    input  wire [10:0] box_w,
    input  wire [10:0] box_h,

    output wire [17:0] ram_addr,          // BRAM 读地址
    input  wire [15:0] ram_data,          // BRAM RGB565 数据（地址打一拍后有效�?
    output wire        lcd_clk,
    output reg         lcd_hs,
    output reg         lcd_vs,
    output reg         lcd_de,
    output wire [23:0] lcd_rgb,
    output wire        lcd_bl,
    output wire        lcd_rst
);

    // ---- 800x480 时序 ----
    localparam H_SYNC  = 11'd128;
    localparam H_BACK  = 11'd88;
    localparam H_DISP  = 11'd800;
    localparam H_FRONT = 11'd40;
    localparam H_TOTAL = 11'd1056;

    localparam V_SYNC  = 11'd2;
    localparam V_BACK  = 11'd33;
    localparam V_DISP  = 11'd480;
    localparam V_FRONT = 11'd10;
    localparam V_TOTAL = 11'd525;

    // ---- 图像在屏上的位置与大小（1:1 居中�?----
    localparam IMG_W  = 11'd300;
    localparam IMG_H  = 11'd400;
    localparam DSP_W  = 11'd640;
    localparam DSP_H  = 11'd480;
    localparam IMG_X0 = 11'd80;
    localparam IMG_Y0 = 11'd0;

    localparam PAGE_SIZE = 18'd120000;    // 每页 300*400 像素

    reg [10:0] h_cnt;
    reg [10:0] v_cnt;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            h_cnt <= 11'd0;
        else if(h_cnt == H_TOTAL - 1'b1)
            h_cnt <= 11'd0;
        else
            h_cnt <= h_cnt + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            v_cnt <= 11'd0;
        else if(h_cnt == H_TOTAL - 1'b1) begin
            if(v_cnt == V_TOTAL - 1'b1)
                v_cnt <= 11'd0;
            else
                v_cnt <= v_cnt + 1'b1;
        end
    end

    wire h_act = (h_cnt >= H_SYNC + H_BACK) && (h_cnt < H_SYNC + H_BACK + H_DISP);
    wire v_act = (v_cnt >= V_SYNC + V_BACK) && (v_cnt < V_SYNC + V_BACK + V_DISP);
    wire de_req = h_act && v_act;

    wire [10:0] px = h_cnt - (H_SYNC + H_BACK);   // 显示区坐�?0~799
    wire [10:0] py = v_cnt - (V_SYNC + V_BACK);   // 显示区坐�?0~479

    // 90 deg CW, enlarged 8/5 using nearest-neighbour reads of the same page.
    wire [10:0] dx = px - IMG_X0;
    wire [10:0] dy = py - IMG_Y0;
    wire [13:0] dx_scaled = {3'b000, dx} * 14'd5;
    wire [13:0] dy_scaled = {3'b000, dy} * 14'd5;
    wire [10:0] sx = dy_scaled[13:3];
    wire [10:0] sy = (IMG_H - 11'd1) - dx_scaled[13:3];
    wire in_img = de_req &&
                  (px >= IMG_X0) && (px < IMG_X0 + DSP_W) &&
                  (py >= IMG_Y0) && (py < IMG_Y0 + DSP_H);

    // ---- 跨时钟：跟踪框参数与采集页标志各打两�?----
    reg [10:0] box_x_r1, box_x_r2, box_y_r1, box_y_r2;
    reg [10:0] box_w_r1, box_w_r2, box_h_r1, box_h_r2;

    always @(posedge clk) begin
        box_x_r1 <= box_x; box_x_r2 <= box_x_r1;
        box_y_r1 <= box_y; box_y_r2 <= box_y_r1;
        box_w_r1 <= box_w; box_w_r2 <= box_w_r1;
        box_h_r1 <= box_h; box_h_r2 <= box_h_r1;
    end

    reg ack_synced_1, ack_synced_2;
    always @(posedge clk) begin
        ack_synced_1 <= cam_latest_page;
        ack_synced_2 <= ack_synced_1;
    end

    reg [10:0] locked_box_x, locked_box_y, locked_box_w, locked_box_h;

    wire frame_end = (h_cnt == H_TOTAL - 1'b1) && (v_cnt == V_TOTAL - 1'b1);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            lcd_rd_page  <= 1'b0;
            locked_box_x <= 11'd0;
            locked_box_y <= 11'd0;
            locked_box_w <= 11'd0;
            locked_box_h <= 11'd0;
        end else if(frame_end) begin
            lcd_rd_page  <= ack_synced_2;
            locked_box_x <= box_x_r2;
            locked_box_y <= box_y_r2;
            locked_box_w <= box_w_r2;
            locked_box_h <= box_h_r2;
        end
    end

    // ---- 跟踪框：2 像素粗的矩形边（屏坐标） ----
    wire [10:0] bx     = locked_box_x;
    wire [10:0] by     = locked_box_y;
    wire [10:0] half_w = locked_box_w >> 1;
    wire [10:0] half_h = locked_box_h >> 1;
    wire [10:0] bleft  = (bx > half_w) ? (bx - half_w) : 11'd0;
    wire [10:0] bright = bx + half_w;
    wire [10:0] btop   = (by > half_h) ? (by - half_h) : 11'd0;
    wire [10:0] bbot   = by + half_h;

    wire box_h_line = in_img && (sx >= bleft) && (sx <= bright) &&
                      ((sy == btop) || (sy == btop + 1'b1) || (sy == bbot) || (sy == bbot - 1'b1));
    wire box_v_line = in_img && (sy >= btop) && (sy <= bbot) &&
                      ((sx == bleft) || (sx == bleft + 1'b1) || (sx == bright) || (sx == bright - 1'b1));
    wire in_box = box_h_line || box_v_line;

    // ---- BRAM 读地址：组合给出，数据下一拍回�?----
    wire [17:0] img_off  = sy * 18'd300 + sx;
    wire [17:0] img_base = lcd_rd_page ? PAGE_SIZE : 18'd0;
    assign ram_addr = in_img ? (img_base + img_off) : 18'd0;

    // ---- 输出打一拍，�?BRAM 数据对齐 ----
    reg in_img_d0, in_box_d0;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            lcd_hs    <= 1'b1;
            lcd_vs    <= 1'b1;
            lcd_de    <= 1'b0;
            in_img_d0 <= 1'b0;
            in_box_d0 <= 1'b0;
        end else begin
            lcd_hs    <= ~(h_cnt < H_SYNC);
            lcd_vs    <= ~(v_cnt < V_SYNC);
            lcd_de    <= de_req;
            in_img_d0 <= in_img;
            in_box_d0 <= in_box;
        end
    end

    wire [23:0] img_rgb = {ram_data[15:11], ram_data[15:13],
                           ram_data[10:5],  ram_data[10:9],
                           ram_data[4:0],   ram_data[4:2]};

    assign lcd_rgb = in_img_d0 ? (in_box_d0 ? 24'hFF0000 : img_rgb) : 24'h000000;
    // 像素时钟直接同源系统时钟；背光与复位常开（与参考工程一致）
    assign lcd_clk = clk;
    assign lcd_bl  = 1'b1;
    assign lcd_rst = 1'b1;

endmodule
