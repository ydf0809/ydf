`timescale 1ns / 1ps
//============================================================================
// frame_buffer.v
//  600x400 帧缓存：简单双口 RAM，写口在摄像头像素钟域，读口在 LCD 像素钟域。
//
//  原来底座工程用的是 blk_mem_gen IP（Simple_Dual_Port_RAM / 240000x16 /
//  读延迟 1 拍 / 读口不加输出寄存器）。这里换成同参数的推断写法，行为等价，
//  好处是整个工程不依赖任何 IP，xsim 和综合脚本能一把跑通。
//
//  读延迟正好 1 拍：lcd_cam_text 的时序就是按这个写的（见该文件头部说明），
//  改这里必须同时改那边。
//
//  容量折算到 xc7z020 的 RAMB36：240000 / 2048 = 117.2 -> 118 块
//  （RAMB36 按 2048x18 用，16 位数据位宽），芯片共 140 块，够用。
//============================================================================
module frame_buffer #(
    parameter DEPTH  = 240000,      // 600*400
    parameter ADDR_W = 18,          // 2^18 = 262144 >= 240000
    parameter DATA_W = 16           // RGB565
)(
    input  wire              clk_wr,    // cam_pclk
    input  wire              wr_en,
    input  wire [ADDR_W-1:0] wr_addr,
    input  wire [DATA_W-1:0] wr_data,

    input  wire              clk_rd,    // 33.333MHz LCD 像素钟
    input  wire [ADDR_W-1:0] rd_addr,
    output reg  [DATA_W-1:0] rd_data    // 比 rd_addr 晚 1 拍
);

    reg [DATA_W-1:0] mem [0:DEPTH-1];

    always @(posedge clk_wr) begin
        if(wr_en)
            mem[wr_addr] <= wr_data;
    end

    always @(posedge clk_rd) begin
        rd_data <= mem[rd_addr];
    end

endmodule
