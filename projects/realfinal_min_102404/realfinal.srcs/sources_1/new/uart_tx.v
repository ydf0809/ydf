//----------------------------------------------------------------------------------------
// File name:           uart_tx
// Descriptions:        UART 发送模块（8 数据位 / 无校验 / 1 停止位）
//
// 用法：uart_tx_en 给一个时钟周期的高脉冲，同时把要发的字节放在 uart_tx_data 上，
//       模块在本拍把数据锁进移位寄存器，随后 busy 拉高，按 1 起始位 + 8 数据位
//       (低位先发) + 1 停止位 的顺序把整帧发完，再释放 busy。
//       busy 为高期间不要再给 en。
//
// 时序：bit_idx 0 = 空闲/起始位，1~8 = 数据位 0~7，9 = 停止位。
//       每个状态停留 BAUD_CNT_MAX 个时钟，状态切换时输出电平同步更换。
//       停止位整个位宽都发完才回空闲，线上不会出现多余的跳变。
//----------------------------------------------------------------------------------------

module uart_tx #(
    parameter CLK_FREQ = 50000000,   //系统时钟频率(Hz)
    parameter UART_BPS = 115200      //串口波特率
)(
    input               clk         , //系统时钟
    input               rst_n       , //同步后的复位，低有效

    input               uart_tx_en  , //发送使能，一个时钟周期的高脉冲
    input       [7:0]   uart_tx_data, //要发送的数据
    output reg          uart_txd    , //UART 发送引脚：接语音模块的 RX
    output reg          uart_tx_busy  //发送中标志
);

//localparam define
localparam BAUD_CNT_MAX = CLK_FREQ / UART_BPS;   //一个位需要的时钟数

//reg define
reg [15:0] baud_cnt;    //位内计数
reg [3:0]  bit_idx;     //0=起始位 1~8=数据位 9=停止位
reg [7:0]  tx_data_r;   //待发数据，每发一位右移一次

//*****************************************************
//**                    main code
//*****************************************************

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        uart_tx_busy <= 1'b0;
        uart_txd     <= 1'b1;           //空闲时线上保持高电平
        baud_cnt     <= 16'd0;
        bit_idx      <= 4'd0;
        tx_data_r    <= 8'd0;
    end
    //收到发送请求：锁存数据，拉出起始位
    else if(uart_tx_en && !uart_tx_busy) begin
        uart_tx_busy <= 1'b1;
        uart_txd     <= 1'b0;
        baud_cnt     <= 16'd0;
        bit_idx      <= 4'd0;
        tx_data_r    <= uart_tx_data;
    end
    //发送中：每个位周期换一次输出
    else if(uart_tx_busy) begin
        if(baud_cnt >= BAUD_CNT_MAX - 1'b1) begin
            baud_cnt <= 16'd0;
            if(bit_idx == 4'd9) begin          //停止位发完，回空闲
                uart_tx_busy <= 1'b0;
                uart_txd     <= 1'b1;
                bit_idx      <= 4'd0;
            end
            else begin
                bit_idx   <= bit_idx + 1'b1;
                tx_data_r <= {1'b0, tx_data_r[7:1]};
                //bit_idx 0 结束后发的是数据位 0，之后依次是 1~7，最后是停止位
                if(bit_idx >= 4'd8)
                    uart_txd <= 1'b1;          //停止位
                else
                    uart_txd <= tx_data_r[0];  //数据位：低位先发
            end
        end
        else
            baud_cnt <= baud_cnt + 1'b1;
    end
end

endmodule
