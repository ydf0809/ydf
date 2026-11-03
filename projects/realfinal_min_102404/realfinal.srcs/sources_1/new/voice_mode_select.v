//----------------------------------------------------------------------------------------
// File name:           voice_mode_select
// Descriptions:        按语音/YOLO 命令选工作模式（下层板）
//
// 规则：**工作模式只由链路上的命令决定**（板上拨码开关已经拆掉了）。
//
//   命令号（链路字节 bit7=0，来自 link_demux 的 cmd_valid）:
//     1 循迹   -> xunbi_en  = 1   （打开五路循迹 -> xunbi_core -> 麦克轮这条路）
//     2 跟随   -> vision_en = 1   （打开摄像头颜色跟随 -> 滤波后的 chassis_control -> 麦克轮）
//     5 装卸货 -> arm_en    = 1   （机械臂；重跑一遍动作的复位脉冲在 arm_voice_trigger 里）
//     3 防空   -> defense_en = 1  （上层 OV5640 目标框 -> 舵机 4/6，底盘停止）
//     4 以及其它值 -> 全部不使能（停车/待命）
//
//   上电后还没收到任何命令时 voice_mode=0，三个都不使能 —— 先站着等指令。
//
// 为什么做成"状态"而不是"命令一响就置起"：
//   只在收到"循迹"时把一个标志置起、再也没法清，说了循迹以后就停不下来了。
//   做成状态以后：说"循迹"开、说"跟随/防空/停下"关、说"装卸货"走机械臂，都能来回切。
//----------------------------------------------------------------------------------------

module voice_mode_select(
    input  wire       clk        ,   //系统时钟
    input  wire       rst_n      ,   //复位，低有效

    input  wire [7:0] cmd        ,   //链路上的命令号
    input  wire       cmd_valid  ,   //命令帧有效（一个时钟周期）

    output wire       xunbi_en   ,   //循迹：开五路循迹 -> xunbi_core -> 麦克轮
    output wire       vision_en  ,   //视觉/跟随（命令 2 打开）
    output wire       defense_en ,   //防空：红色目标驱动舵机 4/6
    output wire       arm_en         //机械臂
);

//reg define
reg [2:0] voice_mode;    //最近一条命令的命令号，0 = 还没收到过

//*****************************************************
//**                    main code
//*****************************************************

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        voice_mode <= 3'd0;
    else if(cmd_valid)
        voice_mode <= cmd[2:0];      //1 循迹 / 2 跟随 / 3 防空 / 4 停下 / 5 装卸货
end

assign xunbi_en  = (voice_mode == 3'd1);
assign vision_en = (voice_mode == 3'd2);   //命令 2（跟随）：打开视觉跟随
assign defense_en = (voice_mode == 3'd3);  //命令 3（防空）：上层目标框驱动机械臂云台
assign arm_en    = (voice_mode == 3'd5);

endmodule
