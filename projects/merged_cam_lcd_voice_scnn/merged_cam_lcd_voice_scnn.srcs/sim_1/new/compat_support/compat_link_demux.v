//----------------------------------------------------------------------------------------
// File name:           link_demux
// Descriptions:        下层板：把链路收到的字节分成两类，并把循迹状态锁存住
//
// 字节格式（见 track_send.v）：
//   bit7=1 -> 循迹状态帧：低 5 位锁进 track_pat（下层把它的 5 位直接喂给 xunbi_core）
//   bit7=0 -> 命令号（1~5）：cmd_valid 给一拍脉冲，下游按命令号做事
//
// 为什么要锁存：命令号帧的字节也走同一个 peer_cmd，如果直接拿 peer_cmd[4:0] 当状态，
// 收到命令 2 的瞬间状态会变成 5'b00010，轮子会抽一下。所以状态单独存一份。
//----------------------------------------------------------------------------------------

module compat_link_demux #(
    parameter integer CLK_FREQ   = 33_333_333,   //系统时钟频率(Hz)
    parameter integer TIMEOUT_MS = 50            //多久没收到循迹帧就当"丢线"(ms)
)(
    input  wire       clk        ,   //系统时钟
    input  wire       rst_n      ,   //复位，低有效

    input  wire [7:0] peer_cmd   ,   //board_link 解出的字节
    input  wire       peer_valid ,   //收到一整帧（一拍）
    input  wire       bbox_busy  ,   //bbox 分包期间屏蔽普通字节解释

    output reg  [4:0] track_pat  ,   //循迹状态，保持住（{l2,l1,m,r1,r2}）
    output reg        track_upd  ,   //循迹状态更新（一拍）
    output wire       cmd_valid      //这一帧是命令号（一拍），命令号在 peer_cmd[4:0]
);

//localparam define
localparam integer TIMEOUT_TICKS = (CLK_FREQ / 1000) * TIMEOUT_MS;   //超时时钟数

//reg define
reg [20:0] idle_cnt;

//*****************************************************
//**                    main code
//*****************************************************

// 0x40 starts a bbox burst; bbox_busy rises one cycle later. Rejecting it here
// as well means only real mode commands 1..5 can change the robot mode.
assign cmd_valid = peer_valid & ~peer_cmd[7] & ~bbox_busy &
                   (peer_cmd >= 8'd1) & (peer_cmd <= 8'd5);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        track_pat <= 5'd0;
        track_upd <= 1'b0;
        idle_cnt  <= 21'd0;
    end
    else begin
        track_upd <= 1'b0;
        if(bbox_busy) begin
            if(peer_valid)
                idle_cnt <= 21'd0;
        end
        else if(peer_valid && peer_cmd[7]) begin
            track_pat <= peer_cmd[4:0];
            track_upd <= 1'b1;
            idle_cnt  <= 21'd0;
        end
        else if(peer_valid) begin
            idle_cnt <= 21'd0;          //命令帧也说明链路是活的，但不改循迹状态
        end
        else if(idle_cnt < TIMEOUT_TICKS[20:0]) begin
            idle_cnt <= idle_cnt + 1'b1;
        end
        else begin
            //看门狗：超过 TIMEOUT_MS 没有新的循迹帧（上层板掉电/线断了），
            //当作"丢线"处理 -> 下层 line_follow_ctrl 判 line_lost -> 轮子停。
            //不做这件事的话，下层会一直拿最后一帧状态继续跑，很危险。
            track_pat <= 5'd0;
        end
    end
end

endmodule
