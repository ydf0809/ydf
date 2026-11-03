//----------------------------------------------------------------------------------------
// File name:           uart_rx
// Descriptions:        UART 接收模块（8 数据位 / 无校验 / 1 停止位）
//
// 采样方式：每个数据位在"位中点"采一次。
//   * 检测到起始位下降沿后，baud_cnt 从 0 开始数
//   * 数到 BAUD_CNT_MAX/2 时正好是起始位的中间（相位对齐）
//   * 之后每个位周期采一次，采样点依次落在数据位 0~7 和停止位的中间
//   * bit_cnt：0=起始位，1~8=数据位，9=停止位；在停止位中点输出数据并结束
//
// 分频：BAUD_CNT_MAX = CLK_FREQ / UART_BPS
//   33.333MHz / 115200 = 289.3 -> 289，实际 115303 bps，误差 0.09%，可接受
//   50MHz     / 115200 = 434.0 -> 434，误差 0.01%
//
// 注意：CLK_FREQ 必须与板载晶振一致。填错不报错，但每个位都会偏，整帧成乱码。
//       若贝八角板 = 33.333MHz；正点原子领航者 = 50MHz。
//----------------------------------------------------------------------------------------

module compat_uart_rx #(
    parameter CLK_FREQ = 50000000,   //系统时钟频率(Hz)，必须与板载晶振一致
    parameter UART_BPS = 115200      //串口波特率，必须与语音模块配置一致
)(
    input               clk         , //系统时钟
    input               rst_n       , //同步后的复位，低有效

    input               uart_rxd    , //UART 接收引脚：接语音模块的 TX
    output reg          uart_rx_done, //单字节接收完成，一个时钟周期的高脉冲
    output reg  [7:0]   uart_rx_data, //接收到的数据
    output reg          frame_err     //成帧错误：停止位不是高电平
);

//localparam define
localparam BAUD_CNT_MAX = CLK_FREQ / UART_BPS;   //一位需要的时钟数
localparam HALF_CNT     = BAUD_CNT_MAX / 2;      //半位，用来对到位中点

//reg define
reg        rxd_d0;      //异步输入打拍
reg        rxd_d1;
reg        rxd_d2;
reg        rx_busy;     //正在收一个字节
reg        rx_done_d;   //rx_done 打一拍，用于清 rx_busy
reg [3:0]  bit_cnt;     //0=起始位 1~8=数据位 9=停止位
reg [15:0] baud_cnt;    //位内计数
reg [7:0]  rx_shift;    //接收移位寄存器

//wire define
wire start_en;          //起始位下降沿，且当前空闲
wire samp_en;           //到达位中点

//*****************************************************
//**                    main code
//*****************************************************

assign start_en = rxd_d2 & (~rxd_d1) & (~rx_busy);
assign samp_en  = (baud_cnt == HALF_CNT - 1'b1);

//异步输入同步化
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rxd_d0 <= 1'b1;
        rxd_d1 <= 1'b1;
        rxd_d2 <= 1'b1;
    end
    else begin
        rxd_d0 <= uart_rxd;
        rxd_d1 <= rxd_d0;
        rxd_d2 <= rxd_d1;
    end
end

//接收过程标志：起始位启动，停止位中点结束
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        rx_busy <= 1'b0;
    else if(start_en)
        rx_busy <= 1'b1;
    else if(rx_done_d)
        rx_busy <= 1'b0;
end

//位内计数
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        baud_cnt <= 16'd0;
    else if(rx_busy) begin
        if(baud_cnt >= BAUD_CNT_MAX - 1'b1)
            baud_cnt <= 16'd0;
        else
            baud_cnt <= baud_cnt + 1'b1;
    end
    else
        baud_cnt <= 16'd0;
end

//位计数：每个位周期 +1
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        bit_cnt <= 4'd0;
    else if(rx_busy) begin
        if(baud_cnt == BAUD_CNT_MAX - 1'b1)
            bit_cnt <= bit_cnt + 1'b1;
    end
    else
        bit_cnt <= 4'd0;
end

//位中点采样，低位先收
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        rx_shift <= 8'd0;
    else if(rx_busy && samp_en) begin
        if(bit_cnt >= 4'd1 && bit_cnt <= 4'd8)
            rx_shift <= {rxd_d2, rx_shift[7:1]};
    end
end

//接收完成 / 成帧错误
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        uart_rx_done <= 1'b0;
        uart_rx_data <= 8'd0;
        frame_err    <= 1'b0;
        rx_done_d    <= 1'b0;
    end
    else begin
        uart_rx_done <= 1'b0;
        frame_err    <= 1'b0;
        rx_done_d    <= 1'b0;

        //停止位中点：一次接收在这里收尾
        if(rx_busy && samp_en && (bit_cnt == 4'd9)) begin
            uart_rx_done <= 1'b1;
            uart_rx_data <= rx_shift;
            rx_done_d    <= 1'b1;
            if(~rxd_d2)                 //停止位应该是高，低了说明成帧错误
                frame_err <= 1'b1;
        end
    end
end

endmodule
