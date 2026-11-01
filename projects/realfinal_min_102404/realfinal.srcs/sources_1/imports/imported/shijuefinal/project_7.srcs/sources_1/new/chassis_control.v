`timescale 1ns / 1ps

module chassis_control(
    input  wire        clk,        
    input  wire        rst_n,      
    
    input  wire        sw,         
    
    input  wire [10:0] box_x,      
    input  wire [10:0] box_y,      
    input  wire [10:0] box_w,      
    input  wire [10:0] box_h,      
    
    output wire [7:0]  out_m1, 
    output wire [7:0]  out_m2, 
    output wire [7:0]  out_m3, 
    output wire [7:0]  out_m4,
    output reg         cmd_update  
);

    reg sw_d0, sw_d1;
    always @(posedge clk) begin sw_d0 <= sw; sw_d1 <= sw_d0; end
    wire sw_rise = sw_d0 & ~sw_d1; 

    // 【修改点】：以最长的边作为判断距离的标准
    wire [10:0] cur_size = (box_w > box_h) ? box_w : box_h;
    
    // ★ 基准尺寸不能在你喊"跟随"的那一拍锁：那一刻 color_track 还没锁色，
    //   框还是默认的 100x100，锁进去会让车先按 100px 去追（往后退）。
    //   所以喊完先等 REF_DELAY（约 300ms：锁色 2~3 帧 + 出第一帧框），
    //   等框变成真实尺寸再锁，等待期间四轮保持 0。
    parameter integer REF_DELAY = 10_000_000;   // 300ms @33.333MHz

    reg  [10:0] ref_size;
    reg  [23:0] ref_wait;
    reg         ref_armed;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ref_size  <= 11'd100;
            ref_wait  <= 24'd0;
            ref_armed <= 1'b0;
        end else if (sw_rise) begin
            ref_wait  <= 24'd0;
            ref_armed <= 1'b1;
        end else if (!sw) begin
            ref_wait  <= 24'd0;
            ref_armed <= 1'b0;
        end else if (ref_armed) begin
            if (ref_wait >= REF_DELAY - 1) begin
                ref_size  <= cur_size;
                ref_armed <= 1'b0;
            end else begin
                ref_wait <= ref_wait + 1'b1;
            end
        end
    end

    // 框变大(cur_size > ref_size) -> 负值送进系统 -> 后退避让
    wire signed [11:0] err_forward = sw ? ($signed({1'b0,ref_size}) - $signed({1'b0,cur_size})) : 12'd0; 
    wire signed [11:0] err_turn    = sw ? ($signed({1'b0,box_y}) - 12'd200) : 12'd0;
    // relative dead band: +-12.5% of the reference size (distance independent)
    wire [11:0] fwd_hi = ref_size + (ref_size >> 3);
    wire [11:0] fwd_lo = ref_size - (ref_size >> 3);
    wire fwd_hold = (cur_size <= fwd_hi) && (cur_size >= fwd_lo); 
    
    // ---- 滤波 + PI（报告里"带滑动平均滤波的 PID"的简化版）----
    // 控制周期 50ms（timer 1_666_666 @33.333MHz）。误差每拍走 1/4 做一阶低通，
    // 等效约 200ms 的时间常数，用来压掉框的抖动；
    // 积分项默认关闭（KI_SHIFT=0）。要开就把它改成 6~10，数越小积分越强，
    // 用来磨掉"目标停住后还差一点距离"的稳态误差；积分有 ±IF_MAX 限幅防饱和。
    parameter integer        KI_SHIFT = 0;
    localparam signed [15:0] IF_MAX  = 16'sd20000;

    reg signed [11:0] ef_f, et_f;
    reg signed [15:0] if_f, if_t;
    wire signed [11:0] ef_step = (err_forward - ef_f) >>> 2;
    wire signed [11:0] et_step = (err_turn    - et_f) >>> 2;
    wire signed [11:0] ef_n    = ef_f + ef_step;      // 本拍滤波后的误差
    wire signed [11:0] et_n    = et_f + et_step;
    wire signed [15:0] ifn_f   = if_f + ef_n;
    wire signed [15:0] ifn_t   = if_t + et_n;
    wire signed [11:0] i_term_f = (KI_SHIFT == 0) ? 12'sd0 : (if_f >>> KI_SHIFT);
    wire signed [11:0] i_term_t = (KI_SHIFT == 0) ? 12'sd0 : (if_t >>> KI_SHIFT);
    wire signed [11:0] speed_forward = (ef_n >>> 1) + i_term_f;
    wire signed [11:0] speed_turn    = (et_n >>> 2) + i_term_t;

    reg signed [11:0] cal_m1, cal_m2, cal_m3, cal_m4;
    reg [23:0] timer; 

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            timer <= 0;
            cmd_update <= 0;
            cal_m1 <= 0; cal_m2 <= 0; cal_m3 <= 0; cal_m4 <= 0;
            ef_f <= 12'sd0; et_f <= 12'sd0;
            if_f <= 16'sd0; if_t <= 16'sd0;
        end else begin
            if(timer < 24'd1_666_666) begin
                timer <= timer + 1'b1;
                cmd_update <= 1'b0;
            end else begin
                timer <= 0;
                cmd_update <= 1'b1; 
                // 50ms 一拍：误差低通 + 积分（KI_SHIFT=0 时积分保持 0）
                ef_f <= ef_n;
                et_f <= et_n;
                if (KI_SHIFT != 0) begin
                    if (ifn_f > IF_MAX)       if_f <= IF_MAX;
                    else if (ifn_f < -IF_MAX) if_f <= -IF_MAX;
                    else                      if_f <= ifn_f;
                    if (ifn_t > IF_MAX)       if_t <= IF_MAX;
                    else if (ifn_t < -IF_MAX) if_t <= -IF_MAX;
                    else                      if_t <= ifn_t;
                end
                
                if (!sw || ref_armed || (fwd_hold && ($signed(err_turn)>-35 && $signed(err_turn)<35))) begin
                     cal_m1 <= 0; cal_m2 <= 0; cal_m3 <= 0; cal_m4 <= 0;
                end else begin
                     cal_m1 <=  speed_forward + speed_turn;
                     cal_m2 <= -speed_forward - speed_turn;
                     cal_m3 <= -speed_forward + speed_turn;
                     cal_m4 <=  speed_forward - speed_turn;
                end
            end
        end
    end

    function [7:0] clamp_and_cast;
        input signed [11:0] val;
        begin
            if(val > 12)       clamp_and_cast = 8'd12;
            else if(val < -12) clamp_and_cast = -8'd12;
            else               clamp_and_cast = val[7:0];
        end
    endfunction

    assign out_m1 = clamp_and_cast(cal_m1);
    assign out_m2 = clamp_and_cast(cal_m2);
    assign out_m3 = clamp_and_cast(cal_m3);
    assign out_m4 = clamp_and_cast(cal_m4);

endmodule
