//----------------------------------------------------------------------------------------
// File name:           link_rx
// Descriptions:        板间串口链路 —— 帧接收（上层板 / 下层板通用）
//
// 就是把 uart_rx + asr_frame_decode 串起来：收齐 AA 55 <命令号> 55 AA 才认一帧。
// 两种出错都会报 err：
//   * 字节级成帧错误（某个字节的停止位不对）——uart_rx 报
//   * 收齐 5 个字节但帧头/帧尾对不上     ——asr_frame_decode 报
// err 是脉冲，锁存成"出过一次错就拉高"由 board_link 做。
//
// peer_cmd 在 peer_valid 那一拍有效。peer_valid 是一拍脉冲，用的时候要当事件用，
// 想当电平用就自己锁存。
//----------------------------------------------------------------------------------------

module link_rx #(
    parameter CLK_FREQ = 33333333,   //系统时钟频率(Hz)，必须与板载晶振一致
    parameter UART_BPS = 115200      //串口波特率
)(
    input  wire       clk       ,    //系统时钟
    input  wire       rst_n     ,    //复位，低有效

    input  wire       rxd       ,    //接对方板的 TX

    output wire [7:0] peer_cmd  ,    //对方发来的命令号
    output wire       peer_valid,    //收到一整帧有效，一个时钟周期的高脉冲
    output wire       err            //坏帧或成帧错误，一个时钟周期的高脉冲
);

//wire define
wire [7:0] rx_data       ;   //UART 收到的字节
wire       rx_done       ;   //单字节接收完成
wire       rx_frame_err  ;   //字节级成帧错误
wire [7:0] dec_cmd       ;   //解析出的命令号
wire       dec_valid     ;   //一帧有效
wire       dec_frame_err ;   //一帧无效

//*****************************************************
//**                    main code
//*****************************************************

uart_rx #(
    .CLK_FREQ (CLK_FREQ),
    .UART_BPS (UART_BPS))
    u_uart_rx(
    .clk          (clk        ),
    .rst_n        (rst_n      ),
    .uart_rxd     (rxd        ),
    .uart_rx_done (rx_done    ),
    .uart_rx_data (rx_data    ),
    .frame_err    (rx_frame_err)
    );

asr_frame_decode u_asr_frame_decode(
    .clk          (clk        ),
    .rst_n        (rst_n      ),
    .uart_rx_data (rx_data    ),
    .uart_rx_done (rx_done    ),
    .cmd_id       (dec_cmd    ),
    .cmd_valid    (dec_valid  ),
    .frame_err    (dec_frame_err)
    );

assign peer_cmd   = dec_cmd;
assign peer_valid = dec_valid;
assign err        = dec_frame_err | rx_frame_err;

endmodule
