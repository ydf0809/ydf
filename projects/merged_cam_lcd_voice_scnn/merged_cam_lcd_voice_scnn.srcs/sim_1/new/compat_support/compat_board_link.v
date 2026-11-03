//----------------------------------------------------------------------------------------
// File name:           board_link
// Descriptions:        板间串口链路顶层（上层板 / 下层板各例化一份，同一份源码）
//
// 两块板各占 2 个脚，交叉接（TX 接对方 RX），必须共地：
//
//      上层板 project_109_cam_lcd_voice        下层板 new(realfinal)
//      ----------------------------            ---------------------
//      link_tx (F19)  ------------------------> link_rx (D19)
//      link_rx (F20)  <------------------------ link_tx (C20)
//      GND            ------------------------- GND
//
// 用法：
//   local_cmd / local_send —— 本板要发给对方的命令：命令号 + 一拍脉冲
//   peer_cmd / peer_valid  —— 对方发来的命令：命令号 + 一拍脉冲（peer_valid 那拍有效）
//   link_err               —— 收到过坏帧就拉高并保持，复位才清（排障用）
//
// ECHO_EN：
//   1 = 收到对方的帧后原样回发当回执（下层板用 1：上层板发命令，下层板回执）
//   0 = 只收不发（上层板用 0）
//   ★ 两块板只能有一边开 ECHO_EN。两边都开会互相回发、无限循环。
//     （语音那条路也一样：README 第 6 节记过这个坑。）
//----------------------------------------------------------------------------------------

module compat_board_link #(
    parameter CLK_FREQ = 33333333,   //系统时钟频率(Hz)
    parameter UART_BPS = 115200,     //串口波特率
    parameter ECHO_EN  = 1'b0        //1=收到帧后原样回发（当回执用）
)(
    input  wire       clk       ,    //系统时钟
    input  wire       rst_n     ,    //复位，低有效

    input  wire       link_rx   ,    //接对方板的 link_tx
    output wire       link_tx   ,    //接对方板的 link_rx

    input  wire [7:0] local_cmd ,    //本板要发出的命令号
    input  wire       local_send,    //命令更新脉冲（一个时钟周期）

    output wire [7:0] peer_cmd  ,    //对方发来的命令号
    output wire       peer_valid,    //收到对方一整帧有效（一个时钟周期）
    output       reg  link_err       //坏帧指示：出过一次错就拉高保持，复位清
);

//wire define
wire [7:0] rx_cmd   ;   //刚收到的命令号
wire       rx_valid ;   //刚收到的帧有效
wire       rx_err   ;   //刚收到的帧有错
wire       tx_req   ;   //发送请求
wire [7:0] tx_cmd   ;   //要发的命令号

//*****************************************************
//**                    main code
//*****************************************************

//本板自己的命令优先；没有命令要发、又开了 ECHO_EN，就把刚收到的帧原样发回去。
//★ 只回"命令帧"（bit7=0）：bit7=1 是循迹状态帧，1ms 一帧，回执没有意义，
//  而且回执会把回程链路灌满、上层的接收侧也被无谓地占住。
assign tx_req = local_send | (ECHO_EN & rx_valid & ~rx_cmd[7]);
assign tx_cmd = local_send ? local_cmd : rx_cmd;

compat_link_rx #(
    .CLK_FREQ (CLK_FREQ),
    .UART_BPS (UART_BPS))
    u_link_rx(
    .clk        (clk      ),
    .rst_n      (rst_n    ),
    .rxd        (link_rx  ),
    .peer_cmd   (rx_cmd   ),
    .peer_valid (rx_valid ),
    .err        (rx_err   )
    );

compat_link_tx #(
    .CLK_FREQ (CLK_FREQ),
    .UART_BPS (UART_BPS))
    u_link_tx(
    .clk    (clk    ),
    .rst_n  (rst_n  ),
    .req    (tx_req ),
    .cmd    (tx_cmd ),
    .txd    (link_tx),
    .busy   (       )
    );

//坏帧指示：一拍脉冲锁成保持电平。要重新观察就按复位。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        link_err <= 1'b0;
    else if(rx_err)
        link_err <= 1'b1;
end

assign peer_cmd   = rx_cmd;
assign peer_valid = rx_valid;

endmodule
