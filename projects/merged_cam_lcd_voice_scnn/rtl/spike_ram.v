`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/28 22:51:14
// Design Name: 
// Module Name: spike_ram
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module spike_ram #(
    parameter P_WIDTH = 8,      // 通道数 (每个位置的脉冲位宽)
    parameter P_DEPTH = 4096    // 位置数 = H*W
) (
    input  wire                          clk,
    // 写端口 (同步)
    input  wire                          i_we,
    input  wire [$clog2(P_DEPTH)-1:0]    i_waddr,
    input  wire [P_WIDTH-1:0]            i_wdata,
    // 读端口 (组合异步, 仅行为级)
    input  wire [$clog2(P_DEPTH)-1:0]    i_raddr,
    output wire [P_WIDTH-1:0]            o_rdata
);
    reg [P_WIDTH-1:0] mem [0:P_DEPTH-1];

    always @(posedge clk) begin
        if (i_we) mem[i_waddr] <= i_wdata;
    end

    assign o_rdata = mem[i_raddr];
endmodule