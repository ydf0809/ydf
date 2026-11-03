//----------------------------------------------------------------------------------------
// File name:           arm_voice_trigger
// Descriptions:        上层板发来『装卸货』命令 -> 启动下层板机械臂定点放置动作
//
// 用法：接到板间链路的输出上
//   cmd / cmd_valid  <- board_link 的 peer_cmd / peer_valid
//   arm_req          -> 一路"该动机械臂了"的保持电平，和板上开关的 arm_en 或起来用
//   arm_rst_n        -> 直接当机械臂模块的复位用：平时为 1，收到命令后拉低 RST_HOLD_MS
//                       毫秒再放开，机械臂就从它自己的上电等待开始重跑一遍动作
//
// 为什么用"复位脉冲"而不是"使能电平"：
//   arm_pick_place_once_top 是一个跑一趟就停在 S_DONE 的状态机。只给使能电平的话，
//   第二次说『装卸货』它已经在 S_DONE 里不动了。给它一个复位脉冲再放开，
//   就等于"从头再来一遍"，每说一次都会重跑，这才符合"说一次动一次"的预期。
//   （这也是原来那个工程用开关拨 001 启动的道理：开关从 000 拨到 001 时释放复位。）
//
// 注意：arm_pick_place_once_top 内部有 STARTUP_WAIT_MS 的上电等待（默认 10 秒），
//       所以命令来了以后要等这么久机械臂才开始动，那是它自己的等待，不是没响应。
//----------------------------------------------------------------------------------------

module arm_voice_trigger #(
    parameter integer CLK_FREQ    = 33_333_333,  //系统时钟频率(Hz)
    parameter [7:0]   ARM_CMD     = 8'd5,        //哪一条命令号算『装卸货』
    parameter integer RST_HOLD_MS = 1            //复位脉冲宽度(ms)：够机械臂状态机复位就行
)(
    input  wire       clk       ,   //系统时钟
    input  wire       rst_n     ,   //复位，低有效

    input  wire [7:0] cmd       ,   //收到的命令号
    input  wire       cmd_valid ,   //收到一整帧有效（一个时钟周期的高脉冲）

    output reg        arm_req   ,   //收到过『装卸货』就保持高
    output reg        arm_rst_n     //给机械臂的复位：平时 1，收到命令后拉低 RST_HOLD_MS 毫秒
);

//localparam define
localparam integer RST_TICKS = (CLK_FREQ / 1000) * RST_HOLD_MS;   //复位脉冲的时钟数

//reg define
reg [31:0] rst_cnt;

//*****************************************************
//**                    main code
//*****************************************************

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        arm_req   <= 1'b0;
        rst_cnt   <= 32'd0;
        arm_rst_n <= 1'b1;
    end
    else if(cmd_valid && (cmd == ARM_CMD)) begin
        arm_req   <= 1'b1;          //『装卸货』收到，保持住
        rst_cnt   <= RST_TICKS;     //复位脉冲重新计时（连说两次也是重跑一遍）
        arm_rst_n <= 1'b0;
    end
    else if(rst_cnt != 32'd0) begin
        rst_cnt   <= rst_cnt - 1'b1;
        arm_rst_n <= 1'b0;
    end
    else begin
        arm_rst_n <= 1'b1;          //复位释放：机械臂开始上电等待，然后做动作
    end
end

endmodule
