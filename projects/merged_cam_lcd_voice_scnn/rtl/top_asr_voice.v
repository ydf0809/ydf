//----------------------------------------------------------------------------------------
// File name:           top_asr_voice
// Descriptions:        LU-ASR02 语音识别模块 <-> 若贝 RZ7020 (XC7Z020CLG400-1) PL 串口接收
//
// 数据流：
//   说出"循迹"  ->  LU-ASR02 的 UART1_TX(B7) 发出  AA 55 01 55 AA
//   本模块      ->  收齐一帧 -> mode <= 3'd1，mode_upd 给一个时钟周期的高脉冲
//   本模块      ->  延时 GAP_MS 毫秒后把同一帧原样回发（ECHO_EN=1 时）
//   LU-ASR02    ->  若平台上给该命令配了一条"串口输入词条"，模块会语音播报收到
//
// 五条词条与参数号：
//   01 循迹 | 02 跟随 | 03 防空 | 04 原地驻扎/停止 | 05 装卸货
//
// ★ 顶层引脚一共只要 7 个（板子接口不够时按这个来）：
//     sys_clk        input    板载晶振
//     btn_n          input    板载按键（低有效，做复位）
//     asr_rxd        input    <- LU-ASR02 的 B7 (UART1_TX)
//     asr_txd        output   -> LU-ASR02 的 B6 (UART1_RX)   ECHO_EN=0 时可不接
//     mode[2:0]      output   当前模式号 1~5（3 个脚）
//     mode_upd       output   模式更新脉冲（1 个脚）
//     frame_err_flag output   乱码帧指示（1 个脚，接 LED 或多用表看电平即可）
//   XDC 里必须给这 7 个脚每一个都写出 PACKAGE_PIN，少一个就生成不了比特流。
//
//   想省脚的话，mode_upd 可以不接（你自己的逻辑直接看 mode 电平变化也行），
//   那就只剩 6 个脚。要彻底不用复位按键，见 rtl/rst_sync.v 的说明。
//   frame_err_flag 只占 1 个脚，排障时很有用，见下面"乱码帧指示"一节。
//
// 顶层参数（改波特率/时钟只动这里，RTL 不用改）：
//   CLK_FREQ : 输入时钟频率，必须与板载晶振一致。若贝 7020 八角板参考工程里
//              sys_clk 是 33.333MHz，正点原子领航者是 50MHz，别照抄。
//   UART_BPS : 串口波特率，必须与语音模块平台里"串口/发送"动作的波特率一致。
//   ECHO_EN  : 1 = 收到帧后原样回发（默认开）；0 = 只收不发，asr_txd 恒为高。
//
// 接线（3 根线，注意 TX 对 RX）：
//   LU-ASR02 B7 (UART1_TX) --> 开发板 asr_rxd
//   LU-ASR02 B6 (UART1_RX) <-- 开发板 asr_txd
//   LU-ASR02 GND           --- 开发板 GND   （必须共地，否则收不到或收到乱码）
//   LU-ASR02 供电按模块说明（5V 输入），不要用 FPGA 的 IO 给它供电。
//----------------------------------------------------------------------------------------

module top_asr_voice #(
    parameter CLK_FREQ        = 33333333,  //输入时钟频率(Hz)：若贝 RZ7020 八角板 = 33.333MHz
    parameter UART_BPS        = 115200  ,  //串口波特率
    parameter ECHO_EN         = 1'b1    ,  //1=收到帧后原样回发
    parameter GAP_MS          = 10      ,  //回发前等待的毫秒数
    parameter BTN_ACTIVE_LOW  = 1'b1       //板载按键按下是否为低电平
)(
    input               sys_clk       ,  //板载晶振
    input               btn_n         ,  //板载按键，按下为低（做 sys_rst_n）

    input               asr_rxd       ,  //<- LU-ASR02 的 B7 (UART1_TX)
    output              asr_txd       ,  //-> LU-ASR02 的 B6 (UART1_RX)

    output reg  [2:0]   mode          ,  //当前模式号 1~5，给循迹/跟随等逻辑用（3 个脚）
    output reg          mode_upd      ,  //模式更新脉冲（一个时钟周期，1 个脚）
    output reg          frame_err_flag   //乱码帧指示：出过一次错就拉高，保持到按复位（1 个脚）
);

//localparam define
localparam GAP_CNT_MAX = CLK_FREQ / 1000 * GAP_MS;   //回发前的等待时钟数

//wire define
wire [7:0] uart_rx_data  ;   //UART 收到的字节
wire       uart_rx_done  ;   //单字节接收完成
wire       rx_frame_err  ;   //字节级成帧错误（停止位不对）
wire [7:0] cmd_id        ;   //解析出的命令号
wire       cmd_valid     ;   //一帧有效
wire       frame_err     ;   //一帧无效
wire       rst_n         ;   //同步后的复位，低有效
wire       uart_tx_busy  ;   //发送中
wire       uart_tx_en    ;   //发送使能，一个时钟周期的高脉冲
wire [7:0] uart_tx_data  ;   //要发送的字节
wire       cmd_upd       ;   //命令更新（给回发用，和 mode_upd 区分开：mode_upd 是给外部逻辑的）

//reg define
reg  [39:0] echo_shift  ;    //回发用的 5 字节移位寄存器
reg  [2:0]  echo_idx    ;    //已发出的字节数
reg  [1:0]  tx_state    ;    //回发状态机
reg  [31:0] gap_cnt     ;    //回发延时计数
reg         cmd_pend    ;    //回发请求挂起

//localparam define
localparam S_IDLE = 2'd0,    //空闲
           S_GAP  = 2'd1,    //等待 GAP_MS 毫秒
           S_SEND = 2'd2;    //逐字节发送

//*****************************************************
//**                    main code
//*****************************************************

//-----------------------复位同步-----------------------------
rst_sync #(
    .BTN_ACTIVE_LOW (BTN_ACTIVE_LOW))
    u_rst_sync(
    .sys_clk        (sys_clk  ),
    .btn_n          (btn_n    ),
    .rst_n          (rst_n    )
    );

//-----------------------UART 接收---------------------------
uart_rx #(
    .CLK_FREQ       (CLK_FREQ ),
    .UART_BPS       (UART_BPS ))
    u_uart_rx(
    .clk            (sys_clk      ),
    .rst_n          (rst_n        ),
    .uart_rxd       (asr_rxd      ),
    .uart_rx_done   (uart_rx_done ),
    .uart_rx_data   (uart_rx_data ),
    .frame_err      (rx_frame_err )
    );

//-----------------------指令帧解析---------------------------
asr_frame_decode u_asr_frame_decode(
    .clk            (sys_clk      ),
    .rst_n          (rst_n        ),
    .uart_rx_data   (uart_rx_data ),
    .uart_rx_done   (uart_rx_done ),
    .cmd_id         (cmd_id       ),
    .cmd_valid      (cmd_valid    ),
    .frame_err      (frame_err    )
    );

//-----------------------模式寄存器---------------------------
//mode 是持续保持的寄存器，mode_upd 只在更新那一刻给一个脉冲
always @(posedge sys_clk or negedge rst_n) begin
    if(!rst_n) begin
        mode     <= 3'd0;
        mode_upd <= 1'b0;
    end
    else if(cmd_valid) begin
        mode     <= cmd_id[2:0];       //01~05 只用低 3 位就够
        mode_upd <= 1'b1;
    end
    else
        mode_upd <= 1'b0;
end

//-----------------------乱码帧指示---------------------------
//收到 5 个字节但帧尾不对、或某个字节的停止位不对，就拉高并一直保持到按复位。
//这个标志是最省事的排障手段：
//  一直为低 且命令没反应 -> 模块根本没发，或线接错/没共地
//  被拉高               -> 收到了数据但对不上，优先怀疑波特率不一致
//
//之所以是"拉高保持"而不是一个时钟的脉冲：33.333MHz 下一拍脉冲肉眼和外接 LED 都看不见，
//而要判断的是一次偶发错误，锁住才有意义。要重新开始观察就按一下复位键。
//（原来是 8 位计数器，引脚不够，只引 1 位出来。）
always @(posedge sys_clk or negedge rst_n) begin
    if(!rst_n)
        frame_err_flag <= 1'b0;
    else if(frame_err || rx_frame_err)
        frame_err_flag <= 1'b1;
end

//-----------------------回发请求挂起-------------------------
//cmd_valid 只有一拍宽，若这时回发状态机正忙，请求会被直接丢掉。用户不会为了
//一次确认重说一遍，所以先锁存，等回到 S_IDLE 再补发。
assign cmd_upd = cmd_valid;

always @(posedge sys_clk or negedge rst_n) begin
    if(!rst_n)
        cmd_pend <= 1'b0;
    else if(!ECHO_EN)
        cmd_pend <= 1'b0;
    else if(cmd_upd)
        cmd_pend <= 1'b1;
    else if(tx_state == S_IDLE)     //帧正是在这一拍装进 echo_shift 的
        cmd_pend <= 1'b0;
end

//-----------------------原样回发同一帧-----------------------
//整帧先拼进 40 位寄存器，再按"最高字节先发"的顺序移位取出。
always @(posedge sys_clk or negedge rst_n) begin
    if(!rst_n) begin
        tx_state   <= S_IDLE;
        gap_cnt    <= 32'd0;
        echo_idx   <= 3'd0;
        echo_shift <= 40'd0;
    end
    else begin
        case(tx_state)
            S_IDLE: begin
                if(ECHO_EN && cmd_pend) begin
                    echo_shift <= {8'hAA, 8'h55, cmd_id, 8'h55, 8'hAA};
                    echo_idx   <= 3'd0;
                    gap_cnt    <= 32'd0;
                    tx_state   <= S_GAP;
                end
            end

            //等一小会儿再发，避免模块刚播完音还没准备好收
            S_GAP: begin
                if(gap_cnt >= GAP_CNT_MAX - 1'b1)
                    tx_state <= S_SEND;
                else
                    gap_cnt <= gap_cnt + 1'b1;
            end

            //uart_tx 在 uart_tx_en 拉高的这一拍就把 echo_shift[39:32] 锁进它自己的移位寄存器，
            //所以这里左移 8 位是安全的：本拍发出去的仍是移位前的那个字节。
            //注意条件只能是 !uart_tx_busy。uart_tx_en 就是 (tx_state==S_SEND) && !uart_tx_busy，
            //再与上 !uart_tx_en 恒为假，状态机会永远停在 S_SEND、无限重发同一个字节。
            S_SEND: begin
                if(!uart_tx_busy) begin
                    echo_shift <= {echo_shift[31:0], 8'h00};
                    if(echo_idx == 3'd4)
                        tx_state <= S_IDLE;
                    else
                        echo_idx <= echo_idx + 1'b1;
                end
            end

            default: tx_state <= S_IDLE;
        endcase
    end
end

assign uart_tx_data = echo_shift[39:32];
assign uart_tx_en   = (tx_state == S_SEND) && !uart_tx_busy;

//-----------------------UART 发送---------------------------
uart_tx #(
    .CLK_FREQ       (CLK_FREQ ),
    .UART_BPS       (UART_BPS ))
    u_uart_tx(
    .clk            (sys_clk      ),
    .rst_n          (rst_n        ),
    .uart_tx_en     (uart_tx_en   ),
    .uart_tx_data   (uart_tx_data ),
    .uart_txd       (asr_txd      ),
    .uart_tx_busy   (uart_tx_busy )
    );

endmodule
