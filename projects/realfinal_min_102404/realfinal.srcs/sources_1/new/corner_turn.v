`timescale 1ns / 1ps
//============================================================================
// corner_turn.v -- 直角弯状态机（抢在 PID 前面接管轮速）
//
// 触发：左侧三路同时压线（且右边两路是白的）
//   正常循迹 ----> 直行 FORWARD_MS ----> 原地旋转 ----> 冷却 ----> 交还 PID
//
// 旋转什么时候停：
//   STOP_ON_LINE=1（默认）：至少转 MIN_SPIN_MS，转弯侧最外探头先离开黑线、
//                           再重新检测到黑线后，交回 PID；TIMEOUT_MS 兜底。
//   STOP_ON_LINE=0        ：纯定时，转满 SPIN_MS 就停，就是你说的"定时 90 度"。
//
// busy=1 期间 xunbi_core 会把 PID 的 run_en 拉低，PID 输出清零、积分和微分历史
// 一起清掉；转完回来 PID 从干净状态重新开始，不会因为转的时候积分攒满而猛地一冲。
//
// 注意：pat 用的是和 line_pid_ctrl 完全相同的左右映射（STEER_REVERSE=1），
// 所以 pat[4] 是 PID 认定"物理最左"的那一路，pat[0] 是最右。
//============================================================================

module corner_turn #(
    parameter integer      CLK_FREQ_HZ  = 33_333_333,
    parameter integer      FORWARD_MS   = 1000,      // 进弯前直行多久
    parameter integer      SPIN_MS      = 700,      // STOP_ON_LINE=0 时的旋转时长
    parameter integer      MIN_SPIN_MS  = 250,      // 至少转多久（跳过拐角那块黑）
    parameter integer      TIMEOUT_MS   = 2000,     // 旋转兜底超时
    parameter integer      COOLDOWN_MS  = 500,      // 转完多久内不再触发同一个弯
    parameter integer      CONFIRM_MS   = 3,        // 三路压线要连续确认几毫秒
    parameter signed [7:0] FORWARD_SPEED= 8'sd16,
    parameter signed [7:0] SPIN_SPEED   = 8'sd20,
    parameter              STOP_ON_LINE = 1
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              run_en,       // 忙时由 xunbi_core 拉低 PID 的 run_en
    input  wire [4:0]        pat,          // 1 = 压黑线，pat[4]=最左 ... pat[0]=最右
    input  wire              line_valid,   // 消抖后的"看得到线"
    input  wire signed [7:0] pid_left,
    input  wire signed [7:0] pid_right,
    output reg  signed [7:0] out_left,
    output reg  signed [7:0] out_right,
    output reg               busy
);

    localparam integer CYCLES_PER_MS = CLK_FREQ_HZ / 1000;

    localparam S_RUN  = 2'd0;
    localparam S_FWD  = 2'd1;
    localparam S_SPIN = 2'd2;
    localparam S_COOL = 2'd3;

    reg [1:0]  state;
    reg [15:0] ms_cnt;
    reg [15:0] t_ms;
    reg [2:0]  det_cnt;
    reg        dir_left;
    reg        outer_seen_off; // 转弯侧最外探头已经离开过拐角黑线

    // 三路同时压线，另外两路必须是白的（避免十字/大块黑误触发）
    wire left3  = pat[4] & pat[3] & pat[2] & ~pat[1] & ~pat[0];
    wire right3 = pat[0] & pat[1] & pat[2] & ~pat[3] & ~pat[4];
    wire pattern_valid = (pat != 5'b00000) && (pat != 5'b11111);
    wire turn_outer = dir_left ? pat[4] : pat[0];
    wire turn_outer_off = dir_left ? ~pat[4] : ~pat[0];

    wire tick = (ms_cnt >= CYCLES_PER_MS - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_RUN;
            ms_cnt   <= 16'd0;
            t_ms     <= 16'd0;
            det_cnt  <= 3'd0;
            dir_left <= 1'b0;
            outer_seen_off <= 1'b0;
        end else if (!run_en) begin
            state    <= S_RUN;
            ms_cnt   <= 16'd0;
            t_ms     <= 16'd0;
            det_cnt  <= 3'd0;
            outer_seen_off <= 1'b0;
        end else begin
            ms_cnt <= tick ? 16'd0 : ms_cnt + 1'b1;

            if (tick) begin
                t_ms <= t_ms + 1'b1;

                case (state)
                    S_RUN: begin
                        if (left3 || right3) begin
                            if (det_cnt >= CONFIRM_MS - 1) begin
                                state    <= S_FWD;
                                t_ms     <= 16'd0;
                                det_cnt  <= 3'd0;
                                dir_left <= left3;
                                outer_seen_off <= 1'b0;
                            end else begin
                                det_cnt <= det_cnt + 1'b1;
                            end
                        end else begin
                            det_cnt <= 3'd0;
                        end
                    end

                    S_FWD: begin
                        if (t_ms >= FORWARD_MS - 1) begin
                            state    <= S_SPIN;
                            t_ms     <= 16'd0;
                            outer_seen_off <= 1'b0;
                        end
                    end

                    S_SPIN: begin
                        // 先确认转弯侧最外探头离开拐角黑线，
                        // 再等待它重新压线，避免刚进弯就立即交回 PID。
                        if (turn_outer_off) outer_seen_off <= 1'b1;

                        if (STOP_ON_LINE) begin
                            if (outer_seen_off && (t_ms >= MIN_SPIN_MS - 1) &&
                                turn_outer && line_valid && pattern_valid) begin
                                state    <= S_COOL;
                                t_ms     <= 16'd0;
                            end

                            if (t_ms >= TIMEOUT_MS - 1) begin
                                state    <= S_COOL;
                                t_ms     <= 16'd0;
                            end
                        end else begin
                            if (t_ms >= SPIN_MS - 1) begin
                                state <= S_COOL;
                                t_ms  <= 16'd0;
                            end
                        end
                    end

                    S_COOL: begin
                        if (t_ms >= COOLDOWN_MS - 1) begin
                            state <= S_RUN;
                            t_ms  <= 16'd0;
                        end
                    end

                    default: state <= S_RUN;
                endcase
            end
        end
    end

    always @(*) begin
        case (state)
            S_FWD: begin
                out_left  = FORWARD_SPEED;
                out_right = FORWARD_SPEED;
            end
            S_SPIN: begin
                if (dir_left) begin
                    out_left  = -SPIN_SPEED;
                    out_right =  SPIN_SPEED;
                end else begin
                    out_left  =  SPIN_SPEED;
                    out_right = -SPIN_SPEED;
                end
            end
            default: begin
                out_left  = pid_left;
                out_right = pid_right;
            end
        endcase
    end

    always @(*) begin
        busy = (state == S_FWD) || (state == S_SPIN);
    end

endmodule
