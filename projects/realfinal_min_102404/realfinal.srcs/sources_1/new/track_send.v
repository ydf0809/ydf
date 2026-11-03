//----------------------------------------------------------------------------------------
// File name:           track_send
// Descriptions:        上层板：读 5 路循迹传感器，定期打包成「循迹状态帧」发给下层板
//
// 为什么要有这个模块：五路循迹的传感器线接在上层板（下层板 J4 被 LCD 占满了），
// 但轮子在下层板、循迹算法也在下层板，所以上层要把这 5 位状态定时送下去。
//
// 帧里一个字节的格式（和命令号共用同一条链路，靠 bit7 区分）：
//   bit7=1 -> 循迹状态帧：低 5 位 = 5 路状态，bit6:5 固定 0
//   bit7=0 -> 命令号（1~5，语音/YOLO 下发）
// 5 位顺序与下层 line_follow_ctrl 里那句一样：{track_l2, track_l1, track_m, track_r1, track_r2}
//
// 发送节奏：
//   * 平时每 SEND_PERIOD_US 微秒发一帧（默认 1ms，够循迹用；115200 下一帧 434us）
//   * mode_upd 来了优先发命令号，并且把定时器清零顺延 —— 保证命令不会被循迹帧挤掉
//     （link_tx 里"忙时锁存"只留最后一个请求，所以要在这里就把优先级排好）
//
// 传感器是异步输入，这里做两级同步；极性按"1 = 压到线"处理（下层算法就是这个约定）。
//   如果你的循迹模块是低电平有效（压线输出 0），把下面 track_pat 那行的 5 位取反即可。
//----------------------------------------------------------------------------------------

module track_send #(
    parameter integer CLK_FREQ        = 33_333_333,  //系统时钟频率(Hz)
    parameter integer SEND_PERIOD_US  = 1000         //平时多久发一帧(us)
)(
    input  wire       clk           ,   //系统时钟（33.333MHz）
    input  wire       rst_n         ,   //复位，低有效

    input  wire       track_l2      ,   //5 路循迹（异步输入）
    input  wire       track_l1      ,
    input  wire       track_m       ,
    input  wire       track_r1      ,
    input  wire       track_r2      ,

    input  wire       mode_upd      ,   //命令更新脉冲（语音/YOLO），优先发送
    input  wire [7:0] mode_cmd      ,   //命令号

    output reg  [7:0] local_cmd     ,   //交给 board_link 的字节
    output reg        local_send        //交给 board_link 的发送请求（一拍）
);

//localparam define
localparam integer SEND_TICKS = (CLK_FREQ / 1000000) * SEND_PERIOD_US;   //定时器终值

//reg define
reg [4:0]  pat_d0;      //同步用
reg [4:0]  pat_d1;      //同步后的 5 位
reg [15:0] send_cnt;    //发送定时器

//wire define
wire [4:0] track_pat;   //同步后的状态，顺序 {l2,l1,m,r1,r2}

//*****************************************************
//**                    main code
//*****************************************************

//传感器是异步输入：两级同步，防亚稳态
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        pat_d0 <= 5'd0;
        pat_d1 <= 5'd0;
    end
    else begin
        pat_d0 <= {track_l2, track_l1, track_m, track_r1, track_r2};
        pat_d1 <= pat_d0;
    end
end

assign track_pat = pat_d1;
//极性反过来就改成： assign track_pat = ~pat_d1;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        send_cnt  <= 16'd0;
        local_cmd <= 8'd0;
        local_send<= 1'b0;
    end
    else begin
        local_send <= 1'b0;

        if(mode_upd) begin                        //命令优先
            local_cmd  <= {3'b000, mode_cmd[4:0]};
            local_send <= 1'b1;
            send_cnt   <= 16'd0;                  //顺延一个周期，别紧挨着再发一帧
        end
        else if(send_cnt >= SEND_TICKS[15:0] - 16'd1) begin
            send_cnt   <= 16'd0;
            local_cmd  <= {1'b1, 2'b00, track_pat};   //bit7=1：循迹状态帧
            local_send <= 1'b1;
        end
        else begin
            send_cnt <= send_cnt + 1'b1;
        end
    end
end

endmodule
