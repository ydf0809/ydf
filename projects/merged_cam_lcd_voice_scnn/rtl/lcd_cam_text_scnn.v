`timescale 1ns / 1ps

// 800x480 LCD 驱动 + 300x200 预览 2x2 放大 + 文字/单框叠加。
//
// 版面（visible 坐标 = 观众看到的正方向，屏 180 度安装）：
//   左上  y 2..25   x 2..161    "DRONE LOCK"（仅锁定无人机时）
//   右上  y 2..25   x 654..797  "DRONE: nn"
//   右上  y 26..49  x 590..797  "NOT DRONE: nn"
//   画面  x 100..699 y 52..451  源 300x200 -> 2x2 最近邻放大
//   框    与 SCNN 128x128 ROI 同心同尺寸；搜索绿、锁定红
//
// 两路数据（帧缓存 BRAM、字模 ROM）都是同步读、1 拍延迟，所以地址必须
// 组合算出，标志位和像素数据一起打一拍对齐。
module lcd_cam_text_scnn (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] pixel_data,      // 300x200 预览，比 fb_rd_addr 慢 1 拍
    input  wire [5:0]  drone_count,     // DRONE 统计（clk 域）
    input  wire [5:0]  not_drone_count, // NOT DRONE 统计（clk 域）
    input  wire [9:0]  roi_x,           // SCNN ROI 左上角（摄像头窗口坐标，cam_pclk 域）
    input  wire [8:0]  roi_y,
    input  wire        locked,          // 1 = 已锁定无人机（cam_pclk 域）
    input  wire        tracker_enabled, // mode 03 only; camera preview stays live
    output reg         lcd_hs,
    output reg         lcd_vs,
    output reg         lcd_de,
    output wire [23:0] lcd_rgb,
    output wire [15:0] fb_rd_addr       // 组合地址 -> 帧缓存
);

    // ---------------- 场时序（与两版一字不差） ----------------
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

    localparam H_ACT = H_SYNC + H_BACK;      // 216
    localparam V_ACT = V_SYNC + V_BACK;      // 35

    // ---------------- 版面 ----------------
    localparam IMG_X = 100, IMG_Y = 52, IMG_W = 600, IMG_H = 400;  // 画面窗口

    localparam CELL_W = 16, CELL_H = 24;
    localparam ROW1_Y = 2;                    // 第一行文字（y 2..25）
    localparam ROW2_Y = 26;                   // 第二行文字（y 26..49）
    localparam LOCK_X = 2;                    // "DRONE LOCK"：左上，10 字符
    localparam LOCK_W = 10 * CELL_W;          // 160
    localparam DRONE_X = 654;                 // "DRONE: nn"：右上，9 字符，右对齐 798
    localparam DRONE_W = 9 * CELL_W;          // 144
    localparam NOT_X   = 590;                 // "NOT DRONE: nn"：右上第二行，13 字符
    localparam NOT_W   = 13 * CELL_W;         // 208

    localparam FG_COLOR = 24'hFFFFFF;
    localparam BG_COLOR = 24'h000000;
    localparam RED_COLOR   = 24'hFF0000;      // 未锁定：红框
    localparam GREEN_COLOR = 24'h00FF00;      // 锁定：绿框
    localparam BOX_THICK = 2;
    localparam ROI_SIDE  = 128;

    // 字模码 = ASCII - 0x20
    localparam [6:0] C_D = 7'h24, C_R = 7'h32, C_O = 7'h2F, C_N = 7'h2E,
                     C_E = 7'h25, C_SP = 7'h00, C_L = 7'h2C, C_C = 7'h23,
                     C_K = 7'h2B, C_T = 7'h34, C_COLON = 7'h1A;

    reg [10:0] h_cnt;
    reg [10:0] v_cnt;

    // ---------------- 跨时钟：ROI 坐标 + 锁定标志（cam_pclk -> clk） ----------------
    (* ASYNC_REG = "TRUE" *) reg [9:0] roi_x_meta;
    (* ASYNC_REG = "TRUE" *) reg [8:0] roi_y_meta;
    (* ASYNC_REG = "TRUE" *) reg       lock_meta;
    reg [9:0] roi_x_use;
    reg [8:0] roi_y_use;
    reg       locked_use;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            roi_x_meta <= 10'd236; roi_y_meta <= 9'd136; lock_meta <= 1'b0;
            roi_x_use  <= 10'd236; roi_y_use  <= 9'd136; locked_use <= 1'b0;
        end else begin
            roi_x_meta <= roi_x;   roi_y_meta <= roi_y;   lock_meta <= locked;
            roi_x_use  <= roi_x_meta; roi_y_use <= roi_y_meta; locked_use <= lock_meta;
        end
    end

    // ---------------- 场计数 ----------------
    wire de_req = (h_cnt >= H_ACT) && (h_cnt < H_ACT + H_DISP) &&
                  (v_cnt >= V_ACT) && (v_cnt < V_ACT + V_DISP);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            h_cnt <= 11'd0;
            v_cnt <= 11'd0;
        end else if(h_cnt == H_TOTAL - 1'b1) begin
            h_cnt <= 11'd0;
            if(v_cnt == V_TOTAL - 1'b1) v_cnt <= 11'd0;
            else                        v_cnt <= v_cnt + 1'b1;
        end else begin
            h_cnt <= h_cnt + 1'b1;
        end
    end

    wire [10:0] screen_x = h_cnt - H_ACT;
    wire [10:0] screen_y = v_cnt - V_ACT;
    wire [10:0] visible_x = H_DISP - 1'b1 - screen_x;
    wire [10:0] visible_y = V_DISP - 1'b1 - screen_y;

    // ---------------- 画面窗口 + 2x2 放大取址 ----------------
    wire in_img_vis = de_req &&
                      (visible_x >= IMG_X) && (visible_x < IMG_X + IMG_W) &&
                      (visible_y >= IMG_Y) && (visible_y < IMG_Y + IMG_H);

    wire [9:0] img_vx = visible_x - IMG_X;     // 0..599（与摄像头窗口坐标同空间）
    wire [9:0] img_vy = visible_y - IMG_Y;     // 0..399

    // 源像素 1 个铺 2x2：右移一位即可
    assign fb_rd_addr = {8'd0, img_vy[8:1]} * 16'd300 + {6'd0, img_vx[9:1]};

    // ---------------- 三个文字区 ----------------
    wire in_lock  = tracker_enabled && locked_use && de_req &&
                    (visible_y >= ROW1_Y) && (visible_y < ROW1_Y + CELL_H) &&
                    (visible_x >= LOCK_X) && (visible_x < LOCK_X + LOCK_W);
    wire in_drone = tracker_enabled && de_req &&
                    (visible_y >= ROW1_Y) && (visible_y < ROW1_Y + CELL_H) &&
                    (visible_x >= DRONE_X) && (visible_x < DRONE_X + DRONE_W);
    wire in_not   = tracker_enabled && de_req &&
                    (visible_y >= ROW2_Y) && (visible_y < ROW2_Y + CELL_H) &&
                    (visible_x >= NOT_X) && (visible_x < NOT_X + NOT_W);
    wire in_text  = in_lock || in_drone || in_not;

    wire [10:0] tx = in_lock  ? (visible_x - LOCK_X)  :
                     in_drone ? (visible_x - DRONE_X) : (visible_x - NOT_X);
    wire [10:0] gy = (in_not ? (visible_y - ROW2_Y) : (visible_y - ROW1_Y));

    function [3:0] dec_tens;
        input [5:0] value;
        begin
            dec_tens = (value >= 6'd50) ? 4'd5 :
                       (value >= 6'd40) ? 4'd4 :
                       (value >= 6'd30) ? 4'd3 :
                       (value >= 6'd20) ? 4'd2 :
                       (value >= 6'd10) ? 4'd1 : 4'd0;
        end
    endfunction

    function [3:0] dec_ones;
        input [5:0] value;
        reg [3:0] tens;
        reg [5:0] tens_value;
        begin
            tens = dec_tens(value);
            tens_value = {2'b00, tens} * 6'd10;
            dec_ones = value[3:0] - tens_value[3:0];
        end
    endfunction

    wire [5:0] cnt_sel = in_not ? not_drone_count : drone_count;
    // 个位始终显示；十位只在 >=10 时显示（<10 时该位留空）
    wire [6:0] tens_code = (cnt_sel >= 6'd10) ? (7'h10 + {3'b000, dec_tens(cnt_sel)}) : C_SP;
    wire [6:0] ones_code = 7'h10 + {3'b000, dec_ones(cnt_sel)};

    reg [6:0] char_code;
    always @(*) begin
        char_code = C_SP;
        if (in_lock) begin
            case (tx[7:4])
                4'd0: char_code = C_D;
                4'd1: char_code = C_R;
                4'd2: char_code = C_O;
                4'd3: char_code = C_N;
                4'd4: char_code = C_E;
                4'd5: char_code = C_SP;
                4'd6: char_code = C_L;
                4'd7: char_code = C_O;
                4'd8: char_code = C_C;
                4'd9: char_code = C_K;
                default: char_code = C_SP;
            endcase
        end else if (in_drone) begin
            case (tx[7:4])
                4'd0: char_code = C_D;
                4'd1: char_code = C_R;
                4'd2: char_code = C_O;
                4'd3: char_code = C_N;
                4'd4: char_code = C_E;
                4'd5: char_code = C_COLON;
                4'd6: char_code = C_SP;
                4'd7: char_code = tens_code;
                4'd8: char_code = ones_code;
                default: char_code = C_SP;
            endcase
        end else if (in_not) begin
            case (tx[7:4])
                4'd0:  char_code = C_N;
                4'd1:  char_code = C_O;
                4'd2:  char_code = C_T;
                4'd3:  char_code = C_SP;
                4'd4:  char_code = C_D;
                4'd5:  char_code = C_R;
                4'd6:  char_code = C_O;
                4'd7:  char_code = C_N;
                4'd8:  char_code = C_E;
                4'd9:  char_code = C_COLON;
                4'd10: char_code = C_SP;
                4'd11: char_code = tens_code;
                4'd12: char_code = ones_code;
                default: char_code = C_SP;
            endcase
        end
    end

    wire [15:0] glyph;
    font_rom u_font (
        .addr ({char_code, gy[4:0]}),
        .clk  (clk),
        .dout (glyph)
    );

    // ---------------- 单框：128x128，搜索/验证红 / 锁定绿 ----------------
    // Inactive drone mode still displays the same ROI, parked at camera centre.
    wire [9:0] display_roi_x=tracker_enabled ? roi_x_use : 10'd236;
    wire [8:0] display_roi_y=tracker_enabled ? roi_y_use : 9'd136;
    wire [9:0] roi_rel_x = img_vx - display_roi_x;
    wire [9:0] roi_rel_y = img_vy - {1'b0, display_roi_y};
    wire roi_inside = in_img_vis &&
                      (img_vx >= display_roi_x) && (img_vx < display_roi_x + ROI_SIDE) &&
                      (img_vy >= {1'b0, display_roi_y}) && (img_vy < {1'b0, display_roi_y} + ROI_SIDE);
    wire roi_border = roi_inside &&
                      ((roi_rel_x < BOX_THICK) || (roi_rel_x > ROI_SIDE - 1 - BOX_THICK) ||
                       (roi_rel_y < BOX_THICK) || (roi_rel_y > ROI_SIDE - 1 - BOX_THICK));

    // ---------------- 一拍延迟：对齐 BRAM(1 拍) 和 字模 ROM(1 拍) ----------------
    reg        in_text_r;
    reg        in_img_r;
    reg        roi_border_r;
    reg        locked_r;
    reg [3:0]  cx_r;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            lcd_hs       <= 1'b0;
            lcd_vs       <= 1'b0;
            lcd_de       <= 1'b0;
            in_text_r    <= 1'b0;
            in_img_r     <= 1'b0;
            roi_border_r <= 1'b0;
            locked_r     <= 1'b0;
            cx_r         <= 4'd0;
        end else begin
            lcd_hs       <= ~(h_cnt < H_SYNC);
            lcd_vs       <= ~(v_cnt < V_SYNC);
            lcd_de       <= de_req;
            in_text_r    <= in_text;
            in_img_r     <= in_img_vis;
            roi_border_r <= roi_border;
            locked_r     <= tracker_enabled && locked_use;
            cx_r         <= tx[3:0];
        end
    end

    wire [23:0] cam_rgb = {pixel_data[15:11], pixel_data[15:13],
                           pixel_data[10:5],  pixel_data[10:9],
                           pixel_data[4:0],   pixel_data[4:2]};
    wire ink = glyph[4'd15 - cx_r];
    wire [23:0] box_color = locked_r ? GREEN_COLOR : RED_COLOR;

    assign lcd_rgb = (in_text_r && tracker_enabled) ? (ink ? FG_COLOR : BG_COLOR) :
                     roi_border_r ? box_color :
                     in_img_r     ? cam_rgb : BG_COLOR;

endmodule
