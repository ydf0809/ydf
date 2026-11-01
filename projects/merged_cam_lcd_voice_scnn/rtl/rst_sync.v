//----------------------------------------------------------------------------------------
// File name:           rst_sync
// Descriptions:        异步复位、同步释放
//
// 为什么需要它：
//   板载按键是机械触点，按下/松开瞬间会有几十到几百纳秒的抖动。如果直接把它当作
//   整个设计的异步复位，同一个抖动沿会以不同的时刻到达不同触发器，各触发器退出
//   复位的时间不一致，可能把 UART 状态机拍进一个非法状态。
//   这里把复位信号先打两拍再释放：释放沿与 sys_clk 同步，全设计同一拍出复位。
//
// 注意：复位必须"异步置位、同步释放"。采样用 sys_clk 的上升沿，而 sys_clk 来自
//       板上晶振，复位按下时它仍在跑，所以两级同步器一定能把复位值搬出去。
//----------------------------------------------------------------------------------------

module rst_sync #(
    parameter BTN_ACTIVE_LOW = 1     //1: 按键按下为低电平(板上按键常闭到地)  0: 按下为高
)(
    input       sys_clk     ,        //系统时钟
    input       btn_n       ,        //板载按键输入，低电平有效

    output      rst_n                //同步后的复位，低电平有效
);

//wire define
wire btn_rst;                        //归一化成"高电平表示复位有效"

//reg define
reg rst_meta;                        //第一级同步：可能是亚稳态
reg rst_sync_r;                      //第二级同步：已经稳定

//*****************************************************
//**                    main code
//*****************************************************

//按键极性归一化：无论板上是高有效还是低有效，这里出来都是"1=复位中"
assign btn_rst = BTN_ACTIVE_LOW ? (~btn_n) : btn_n;

always @(posedge sys_clk or posedge btn_rst) begin
    if(btn_rst) begin
        rst_meta   <= 1'b1;
        rst_sync_r <= 1'b1;
    end
    else begin
        rst_meta   <= 1'b0;
        rst_sync_r <= rst_meta;
    end
end

assign rst_n = ~rst_sync_r;

endmodule
