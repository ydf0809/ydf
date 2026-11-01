//----------------------------------------------------------------------------------------
// File name:           defense_spin
// Descriptions:        防空模式底盘辅助：云台行程用尽时，麦克纳姆轮原地转向
//
// 触发条件（两路都满足，连续保持 CONFIRM_MS）：
//   右：舵机6 到 YAW_MAX 且 跟踪框右边缘距画面右边界 < EDGE_PX
//       （框中心 >= IMG_W-1-BOX_HALF_W-EDGE_PX = 505）
//   左：舵机6 到 YAW_MIN 且 跟踪框左边缘距画面左边界 < EDGE_PX
//       （框中心 <= BOX_HALF_W+EDGE_PX = 94）
//
// 为什么要用框边缘而不是框中心：上层下发的固定框是 128×128，且 ROI 被夹在画面内
// （roi_scheduler 里 x0∈[0,472]），框中心的可见坐标只能是 63~535，永远到不了 30 px。
// 框边缘才对应"无人机即将/已经出画"。
//
// 转向时长：至少 MIN_SPIN_MS，最长 MAX_SPIN_MS，两者之间满足下面任一就提前停：
//   - 锁定且框中心回到 300±CENTER_TOL_PX（无人机回到画面中央）
//   - 锁定但本方向的条件已经不成立（无人机换到另一边）——此时优先让舵机去追
// 转完直接恢复跟踪，不额外回位；若条件仍然成立，确认 300 ms 后会再转一次。
//
// 方向：RIGHT_SIGN>0 时"右边界 -> m1=+S,m2=-S,m3=+S,m4=-S"（沿用 xunbi_core 的
// 电机极性约定：左侧正转、右侧反转）。实车方向不对就把 RIGHT_SIGN 改成 -1。
//----------------------------------------------------------------------------------------

module defense_spin #(
    parameter integer CLK_HZ        = 33_333_333,
    parameter integer IMG_W         = 600,
    parameter integer CENTER_X      = 300,
    parameter integer BOX_HALF_W    = 64,      // 上层 ROI 框 128×128
    parameter integer EDGE_PX       = 30,      // 框边缘距边界阈值
    parameter integer YAW_MIN       = 100,
    parameter integer YAW_MAX       = 850,
    parameter integer CONFIRM_MS    = 300,
    parameter integer MIN_SPIN_MS   = 1000,
    parameter integer MAX_SPIN_MS   = 2000,
    parameter integer CENTER_TOL_PX = 60,
    parameter integer REFRESH_MS    = 100,
    parameter signed  [7:0] SPIN_SPEED = 8'sd18,
    parameter integer RIGHT_SIGN    = 1       // 1 或 -1，实车方向反了就翻这个
)(
    input  wire        clk,
    input  wire        rst_n,         // 建议接 rst_n & defense_en
    input  wire        defense_en,
    input  wire        target_valid,  // 上层锁定且在有效期内的框
    input  wire [10:0] target_cx,     // 框中心（可见/LCD 坐标）
    input  wire [15:0] yaw_pos,       // 舵机6 当前位置

    output reg         spin_active,
    output reg  signed [7:0] m1,
    output reg  signed [7:0] m2,
    output reg  signed [7:0] m3,
    output reg  signed [7:0] m4,
    output reg         cmd_update
);

localparam [10:0] CX_RIGHT_MIN = IMG_W - 1 - BOX_HALF_W - EDGE_PX;   // 505
localparam [10:0] CX_LEFT_MAX  = BOX_HALF_W + EDGE_PX;               //  94
localparam [10:0] CX_CENTER_LO = CENTER_X - CENTER_TOL_PX;           // 240
localparam [10:0] CX_CENTER_HI = CENTER_X + CENTER_TOL_PX;           // 360

localparam integer MS_TICKS      = CLK_HZ / 1000;
localparam integer CONFIRM_TICKS = MS_TICKS * CONFIRM_MS;
localparam integer MIN_TICKS     = MS_TICKS * MIN_SPIN_MS;
localparam integer MAX_TICKS     = MS_TICKS * MAX_SPIN_MS;
localparam integer REFRESH_TICKS = MS_TICKS * REFRESH_MS;

localparam S_IDLE = 1'b0;
localparam S_SPIN = 1'b1;

wire at_right = target_valid && (yaw_pos >= YAW_MAX) && (target_cx >= CX_RIGHT_MIN);
wire at_left  = target_valid && (yaw_pos <= YAW_MIN) && (target_cx <= CX_LEFT_MAX);
wire want     = defense_en && (at_right || at_left);

wire centered = target_valid && (target_cx > CX_CENTER_LO) && (target_cx < CX_CENTER_HI);

reg        state;
reg        dir_right;      // 本次原地转向的方向：1 = 右（朝画面右侧）
reg [31:0] confirm_cnt;
reg [31:0] spin_cnt;
reg [31:0] refresh_cnt;

wire dir_cond_now = dir_right ? at_right : at_left;
wire dir_lost     = target_valid && !dir_cond_now;
wire early_stop   = (spin_cnt >= MIN_TICKS - 1) && (centered || dir_lost);
wire time_out     = (spin_cnt >= MAX_TICKS - 1);

// RIGHT_SIGN>0: 右 -> m1/m3 正转、m2/m4 反转
wire turn_right_now = (RIGHT_SIGN > 0) ? at_right : ~at_right;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= S_IDLE;
        dir_right   <= 1'b0;
        confirm_cnt <= 32'd0;
        spin_cnt    <= 32'd0;
        refresh_cnt <= 32'd0;
        spin_active <= 1'b0;
        cmd_update  <= 1'b0;
        m1 <= 8'sd0; m2 <= 8'sd0; m3 <= 8'sd0; m4 <= 8'sd0;
    end else begin
        cmd_update <= 1'b0;

        case (state)
            S_IDLE: begin
                if (want) begin
                    if (confirm_cnt >= CONFIRM_TICKS - 1) begin
                        dir_right   <= at_right;
                        spin_cnt    <= 32'd0;
                        refresh_cnt <= 32'd0;
                        confirm_cnt <= 32'd0;
                        spin_active <= 1'b1;
                        cmd_update  <= 1'b1;
                        m1 <=  turn_right_now ?  SPIN_SPEED : -SPIN_SPEED;
                        m2 <=  turn_right_now ? -SPIN_SPEED :  SPIN_SPEED;
                        m3 <=  turn_right_now ?  SPIN_SPEED : -SPIN_SPEED;
                        m4 <=  turn_right_now ? -SPIN_SPEED :  SPIN_SPEED;
                        state <= S_SPIN;
                    end else begin
                        confirm_cnt <= confirm_cnt + 1'b1;
                    end
                end else begin
                    confirm_cnt <= 32'd0;
                end
            end

            S_SPIN: begin
                spin_cnt <= spin_cnt + 1'b1;

                if (refresh_cnt >= REFRESH_TICKS - 1) begin
                    refresh_cnt <= 32'd0;
                    cmd_update  <= 1'b1;      // 周期性重发，防止电机板丢一次就停
                end else begin
                    refresh_cnt <= refresh_cnt + 1'b1;
                end

                if (!defense_en || time_out || early_stop) begin
                    spin_active <= 1'b0;
                    spin_cnt    <= 32'd0;
                    confirm_cnt <= 32'd0;
                    m1 <= 8'sd0; m2 <= 8'sd0; m3 <= 8'sd0; m4 <= 8'sd0;
                    state <= S_IDLE;
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
