`timescale 1ns / 1ps
//============================================================================
// line_pid_ctrl.v -- 五路循迹 -> 位置式 PID -> 左右轮差速
//
// 误差怎么算：
//   五个探头权重 -2 -1 0 +1 +2，对压线探头求加权重心并归一化。
//   误差使用 Q8 定点：1.0 个探头间距 = 256。
//
// 控制律：
//   turn      = Kp*err + Ki*积分 + Kd*误差变化，再限幅到 ±TURN_MAX
//   base_eff  = SPEED_BASE - |turn|/2^CURVE_SHIFT
//   left/right = base_eff ± turn
//
// 丢线搜索：连续 LOST_CONFIRM 拍 line_valid=0 后进入搜索；全亮/全灭
//   由外部 line_valid 判断。固定先左 T、再右 2T、再左 T 回中，完整扫描为 4T。
//   时间向上取整到控制周期；默认周期 20ms、T=150ms，按拍量化后完整扫描为640ms。
//   左右轮始终输出相反的 ±SEARCH_SPEED，不受丢线前转向影响。
//   控制周期发现有效线立即恢复 PID，并重新建立积分/微分历史；超时则停车。
//
// 三个增益都是 2 的幂（移位实现，不占乘法器）：
//   Kp = 1/2^KP_SHIFT，Ki = 1/2^KI_SHIFT，Kd = 1/2^KD_SHIFT
//   KI_SHIFT / KD_SHIFT 写 0 表示关闭该项。默认只开 P。
//============================================================================

module line_pid_ctrl #(
    parameter integer      CLK_FREQ_HZ   = 33_333_333,
    parameter integer      PERIOD_MS     = 20,
    parameter              STEER_REVERSE = 1'b1,
    parameter signed [7:0] SPEED_BASE    = 8'sd16,
    parameter signed [7:0] SPEED_MAX     = 8'sd20,
    parameter signed [7:0] TURN_MAX      = 8'sd16,
    parameter integer      CURVE_SHIFT   = 1,
    parameter integer      KP_SHIFT      = 5,
    parameter integer      ERR_DEADBAND  = 96,
    parameter integer      KI_SHIFT      = 0,
    parameter integer      KD_SHIFT      = 0,
    parameter integer      LOST_CONFIRM  = 2,
    parameter integer      SEARCH_EN     = 1,
    parameter integer      SEARCH_MS     = 640,
    parameter integer      SEARCH_SWING_MS = 150,
    parameter signed [7:0] SEARCH_SPEED  = 8'sd14
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              run_en,
    input  wire [4:0]        track_pat,
    input  wire              line_valid,
    output reg  signed [7:0] left_speed,
    output reg  signed [7:0] right_speed,
    output wire              active,
    output wire              search_active
);

    localparam integer PERIOD_CYCLES = (CLK_FREQ_HZ / 1000) * PERIOD_MS;
    localparam signed [16:0] I_MAX   = 17'sd30000;
    localparam integer SEARCH_TICKS  = ((SEARCH_MS + PERIOD_MS - 1) / PERIOD_MS < 1)
                                     ? 1 : ((SEARCH_MS + PERIOD_MS - 1) / PERIOD_MS);
    localparam integer SWING_TICKS   = ((SEARCH_SWING_MS + PERIOD_MS - 1) / PERIOD_MS < 1)
                                     ? 1 : ((SEARCH_SWING_MS + PERIOD_MS - 1) / PERIOD_MS);

    wire [4:0] pat = STEER_REVERSE
                   ? {track_pat[0], track_pat[1], track_pat[2], track_pat[3], track_pat[4]}
                   : track_pat;
    wire s_l2 = pat[4];
    wire s_l1 = pat[3];
    wire s_m  = pat[2];
    wire s_r1 = pat[1];
    wire s_r2 = pat[0];
    wire [2:0] cnt = s_l2 + s_l1 + s_m + s_r1 + s_r2;
    // 全白/全黑都是无效循迹状态。不要只依赖外部 line_valid，
    // 否则在消抖窗口内会继续沿用上一个直行/转弯速度。
    wire pattern_valid = (track_pat != 5'b00000) && (track_pat != 5'b11111);
    wire line_now_valid = line_valid && pattern_valid;

    reg signed [4:0] wsum;
    always @(*) begin
        wsum = 5'sd0;
        if (s_l2) wsum = wsum - 5'sd2;
        if (s_l1) wsum = wsum - 5'sd1;
        if (s_r1) wsum = wsum + 5'sd1;
        if (s_r2) wsum = wsum + 5'sd2;
    end

    reg [8:0] inv_cnt;
    always @(*) begin
        case (cnt)
            3'd1:    inv_cnt = 9'd256;
            3'd2:    inv_cnt = 9'd128;
            3'd3:    inv_cnt = 9'd85;
            3'd4:    inv_cnt = 9'd64;
            3'd5:    inv_cnt = 9'd51;
            default: inv_cnt = 9'd0;
        endcase
    end

    wire signed [12:0] err = wsum * $signed({1'b0, inv_cnt});
    wire signed [12:0] err_db = (err >  ERR_DEADBAND) ? (err - ERR_DEADBAND) :
                                (err < -ERR_DEADBAND) ? (err + ERR_DEADBAND) : 13'sd0;

    reg signed [12:0] err_prev;
    reg signed [16:0] integ;
    reg searching;
    reg give_up;

    wire signed [16:0] i_q    = (KI_SHIFT == 0) ? 17'sd0 : (integ >>> KI_SHIFT);
    wire signed [12:0] p_term = err_db >>> KP_SHIFT;
    wire signed [12:0] i_term = i_q[12:0];
    wire signed [12:0] d_term = (KD_SHIFT == 0 || searching || give_up)
                               ? 13'sd0 : ((err_db - err_prev) >>> KD_SHIFT);
    wire signed [13:0] turn_sum = p_term + i_term + d_term;

    reg signed [7:0] turn;
    always @(*) begin
        if (turn_sum > TURN_MAX)
            turn = TURN_MAX;
        else if (turn_sum < -TURN_MAX)
            turn = -TURN_MAX;
        else
            turn = turn_sum[7:0];
    end

    wire signed [7:0] turn_abs   = (turn < 0) ? -turn : turn;
    wire signed [7:0] curve_drop = (CURVE_SHIFT == 0) ? 8'sd0 : (turn_abs >>> CURVE_SHIFT);
    reg signed [8:0] base_eff;
    always @(*) begin
        if (curve_drop >= SPEED_BASE)
            base_eff = 9'sd0;
        else
            base_eff = SPEED_BASE - curve_drop;
    end

    reg signed [8:0] left_raw;
    reg signed [8:0] right_raw;
    always @(*) begin
        left_raw  = base_eff + turn;
        right_raw = base_eff - turn;
    end

    function signed [7:0] clamp_motor;
        input signed [8:0] v;
        begin
            if (v > SPEED_MAX)
                clamp_motor = SPEED_MAX;
            else if (v < -SPEED_MAX)
                clamp_motor = -SPEED_MAX;
            else
                clamp_motor = v[7:0];
        end
    endfunction

    reg [31:0] period_cnt;
    reg [3:0]  lost_cnt;
    reg [31:0] search_cnt;
    wire [31:0] search_next = search_cnt + 1'b1;
    wire [31:0] scan_next = search_next % (4 * SWING_TICKS);
    wire search_right = (scan_next >= SWING_TICKS) && (scan_next < 3 * SWING_TICKS);

    assign active = run_en & ~give_up;
    assign search_active = run_en & searching;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            period_cnt  <= 32'd0;
            lost_cnt    <= 4'd0;
            err_prev    <= 13'sd0;
            integ       <= 17'sd0;
            left_speed  <= 8'sd0;
            right_speed <= 8'sd0;
            searching   <= 1'b0;
            give_up     <= 1'b0;
            search_cnt  <= 32'd0;
        end else if (!run_en) begin
            period_cnt  <= 32'd0;
            lost_cnt    <= 4'd0;
            err_prev    <= 13'sd0;
            integ       <= 17'sd0;
            left_speed  <= 8'sd0;
            right_speed <= 8'sd0;
            searching   <= 1'b0;
            give_up     <= 1'b0;
            search_cnt  <= 32'd0;
        end else if (period_cnt < PERIOD_CYCLES - 1) begin
            period_cnt <= period_cnt + 1'b1;
            // Stop stale PID motion immediately; keep the original search cadence.
            if (!line_now_valid && !searching) begin
                left_speed  <= 8'sd0;
                right_speed <= 8'sd0;
            end
        end else begin
            period_cnt <= 32'd0;

            if (line_now_valid) begin
                lost_cnt   <= 4'd0;
                searching  <= 1'b0;
                give_up    <= 1'b0;
                search_cnt <= 32'd0;
                err_prev   <= err_db;

                if (KI_SHIFT != 0) begin
                    if (integ + err_db > I_MAX)
                        integ <= I_MAX[16:0];
                    else if (integ + err_db < -I_MAX)
                        integ <= -I_MAX[16:0];
                    else
                        integ <= integ + err_db;
                end

                left_speed  <= clamp_motor(left_raw);
                right_speed <= clamp_motor(right_raw);

            end else if (searching) begin
                if (search_cnt >= SEARCH_TICKS - 1) begin
                    searching   <= 1'b0;
                    give_up     <= 1'b1;
                    left_speed  <= 8'sd0;
                    right_speed <= 8'sd0;
                end else begin
                    search_cnt  <= search_next;
                    left_speed  <= search_right ?  SEARCH_SPEED : -SEARCH_SPEED;
                    right_speed <= search_right ? -SEARCH_SPEED :  SEARCH_SPEED;
                end

            end else if (give_up) begin
                left_speed  <= 8'sd0;
                right_speed <= 8'sd0;

            end else begin
                if (lost_cnt >= LOST_CONFIRM - 1) begin
                    err_prev <= 13'sd0;
                    integ    <= 17'sd0;
                    if (SEARCH_EN != 0) begin
                        searching   <= 1'b1;
                        search_cnt  <= 32'd0;
                        left_speed  <= -SEARCH_SPEED;
                        right_speed <=  SEARCH_SPEED;
                    end else begin
                        left_speed  <= 8'sd0;
                        right_speed <= 8'sd0;
                    end
                end else begin
                    lost_cnt <= lost_cnt + 1'b1;
                    // 无效状态先停车一个控制周期，再进入搜索，
                    // 防止五灯全亮/全灭时残留上一拍速度继续前进。
                    left_speed  <= 8'sd0;
                    right_speed <= 8'sd0;
                end
            end
        end
    end

endmodule
