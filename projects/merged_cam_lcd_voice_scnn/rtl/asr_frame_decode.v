//----------------------------------------------------------------------------------------
// File name:           asr_frame_decode
// Descriptions:        LU-ASR02 指令帧解析
//
// 帧格式（配置平台里"发送"动作填的 5 个字节）：
//     AA 55 <命令号> 55 AA
//
// 命令号约定（与平台里五条词条一一对应）：
//     01 = 循迹        02 = 跟随        03 = 防空        04 = 原地驻扎/停止   05 = 装卸货
//
// 输出：
//   cmd_id    : 解析出的命令号，在 cmd_valid 那一拍有效
//   cmd_valid : 收齐一帧且帧尾校验通过，一个时钟周期的高脉冲
//   frame_err : 收齐 5 个字节但帧尾不对，一个时钟周期的高脉冲
//               （用来区分"模块没说话"和"波特率不对/接线不对导致收到乱码"）
//
// 重同步：帧头丢字节也能靠 AA 重新对齐。解析中若又出现 AA，就当作新帧头重新开始，
//         所以 AA 55 01 AA 55 01 55 AA 这种粘包也能正确解出 01。
//
// 校验范围说明：帧头 AA 55 由状态机逐字节比对，帧尾 0x55 也由状态机比对，
//               最后一个 0xAA 在 S_TAIL2 里比。整帧 5 个字节全部校验。
//----------------------------------------------------------------------------------------

module asr_frame_decode(
    input               clk         , //系统时钟
    input               rst_n       , //同步后的复位，低有效

    input       [7:0]   uart_rx_data, //UART 收到的字节
    input               uart_rx_done, //单字节接收完成脉冲

    output reg  [7:0]   cmd_id      , //命令号
    output reg          cmd_valid   , //一帧有效
    output reg          frame_err     //一帧无效
);

//parameter define
parameter HEAD1 = 8'hAA;    //帧头第 1 字节
parameter HEAD2 = 8'h55;    //帧头第 2 字节
parameter TAIL1 = 8'h55;    //帧尾第 1 字节
parameter TAIL2 = 8'hAA;    //帧尾第 2 字节

//localparam define
localparam S_HEAD1 = 3'd0,  //等帧头第 1 字节
           S_HEAD2 = 3'd1,  //等帧头第 2 字节
           S_CMD   = 3'd2,  //收命令号
           S_TAIL1 = 3'd3,  //等帧尾第 1 字节
           S_TAIL2 = 3'd4;  //等帧尾第 2 字节

//reg define
reg [2:0] state   ;
reg [7:0] cmd_id_t;

//*****************************************************
//**                    main code
//*****************************************************

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state     <= S_HEAD1;
        cmd_id_t  <= 8'd0;
        cmd_id    <= 8'd0;
        cmd_valid <= 1'b0;
        frame_err <= 1'b0;
    end
    else begin
        cmd_valid <= 1'b0;              //默认拉低，只在解析成功那一拍给脉冲
        frame_err <= 1'b0;

        if(uart_rx_done) begin
            case(state)
                //等 0xAA
                S_HEAD1: state <= (uart_rx_data == HEAD1) ? S_HEAD2 : S_HEAD1;

                //等 0x55；若来的又是 0xAA 就停在本状态，避免漏掉紧跟着的正确帧头
                S_HEAD2: state <= (uart_rx_data == HEAD2) ? S_CMD   :
                                  (uart_rx_data == HEAD1) ? S_HEAD2 : S_HEAD1;

                //命令号
                S_CMD  : begin
                    cmd_id_t <= uart_rx_data;
                    state    <= S_TAIL1;
                end

                //等帧尾 0x55，同样保留对 0xAA 的重同步
                S_TAIL1: state <= (uart_rx_data == TAIL1) ? S_TAIL2 :
                                  (uart_rx_data == HEAD1) ? S_HEAD2 : S_HEAD1;

                //校验帧尾 0xAA
                S_TAIL2: begin
                    state <= S_HEAD1;
                    if(uart_rx_data == TAIL2) begin
                        cmd_id    <= cmd_id_t;
                        cmd_valid <= 1'b1;
                    end
                    else
                        frame_err <= 1'b1;
                end

                default: state <= S_HEAD1;
            endcase
        end
    end
end

endmodule
