//----------------------------------------------------------------------------------------
// File name:           link_tx
// Descriptions:        板间串口链路 —— 帧发送（上层板 / 下层板通用）
//
// 帧格式固定 5 字节： AA 55 <命令号> 55 AA ，8 数据位 / 无校验 / 1 停止位。
// 收侧的 asr_frame_decode 就是按这个格式解析的，所以这条路和语音那条路同格式。
//
// 用法：req 给一个时钟周期的高脉冲，同时把命令号放在 cmd 上。
//       帧还没发完就再来请求不会丢：内部把请求锁存住，等这一帧发完补发。
//       连来多个请求时只留最后一个命令号（命令号是状态量，不是事件流）。
//
// 时序：S_SEND 里每次碰到 uart_tx 空闲就送出 shift[39:32]，同时左移 8 位。
//       uart_tx 在 en 那一拍才把数据锁进它自己的移位寄存器，所以本拍发出去的仍是移位前的字节。
//       判据只能是 !uart_tx_busy：若与上 !uart_tx_en，状态机会永远停在 S_SEND、无限重发。
//       （这两条是从 top_asr_voice 的回发状态机搬来的，那边踩过这两个坑。）
//----------------------------------------------------------------------------------------

module compat_link_tx #(
    parameter CLK_FREQ = 33333333,   //系统时钟频率(Hz)：两块板都是 33.333MHz
    parameter UART_BPS = 115200      //串口波特率
)(
    input  wire       clk     ,      //系统时钟
    input  wire       rst_n   ,      //复位，低有效

    input  wire       req     ,      //发送请求，一个时钟周期的高脉冲
    input  wire [7:0] cmd     ,      //要发的命令号（帧里的第 3 个字节）

    output wire       txd     ,      //串口发送脚：接对方板的 RX
    output wire       busy           //正在发一帧，或还有一帧在排队
);

//localparam define
localparam [1:0] S_IDLE = 2'd0,      //空闲
                 S_SEND = 2'd1;      //逐字节发送

//reg define
reg  [1:0]  state;
reg  [39:0] shift;      //{AA,55,cmd,55,AA}，最高字节先发
reg  [2:0]  idx;        //已发出的字节数
reg         pend;       //有请求排队
reg  [7:0]  pend_cmd;   //排队帧的命令号

//wire define
wire        tx_busy;    //uart_tx 正在发
wire        tx_en;      //uart_tx 发送使能，一个时钟周期的高脉冲
wire [7:0]  tx_data;    //要发的字节

//*****************************************************
//**                    main code
//*****************************************************

assign tx_en   = (state == S_SEND) && !tx_busy;
assign tx_data = shift[39:32];
assign busy    = (state != S_IDLE) || pend;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state    <= S_IDLE;
        shift    <= 40'd0;
        idx      <= 3'd0;
        pend     <= 1'b0;
        pend_cmd <= 8'd0;
    end
    else begin
        case(state)
            S_IDLE: begin
                if(pend) begin
                    shift <= {8'hAA, 8'h55, pend_cmd, 8'h55, 8'hAA};
                    idx   <= 3'd0;
                    state <= S_SEND;
                end
            end

            S_SEND: begin
                if(!tx_busy) begin
                    shift <= {shift[31:0], 8'h00};
                    if(idx == 3'd4)
                        state <= S_IDLE;
                    else
                        idx <= idx + 1'b1;
                end
            end

            default: state <= S_IDLE;
        endcase

        //请求锁存：正忙时来的新请求记下来，等这一帧发完补发
        if(req) begin
            pend     <= 1'b1;
            pend_cmd <= cmd;
        end
        else if((state == S_IDLE) && pend)   //帧正是在这一拍装进 shift 的
            pend <= 1'b0;
    end
end

compat_uart_tx #(
    .CLK_FREQ (CLK_FREQ),
    .UART_BPS (UART_BPS))
    u_uart_tx(
    .clk          (clk    ),
    .rst_n        (rst_n  ),
    .uart_tx_en   (tx_en  ),
    .uart_tx_data (tx_data),
    .uart_txd     (txd    ),
    .uart_tx_busy (tx_busy )
    );

endmodule
