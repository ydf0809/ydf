`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/28 22:54:38
// Design Name: 
// Module Name: weight_bram_beh
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


module weight_bram_beh #(
    parameter P_DATA_WIDTH = 64,
    parameter P_DEPTH      = 16,     // = num_input/4
    parameter P_INIT_FILE  = ""
) (
    input  wire                          clka,
    input  wire                          ena,
    input  wire [$clog2(P_DEPTH)-1:0]    addra,
    output wire [P_DATA_WIDTH-1:0]       douta
);
    reg [P_DATA_WIDTH-1:0] mem [0:P_DEPTH-1];
    reg [P_DATA_WIDTH-1:0] rd1, rd2;

    initial begin
        if (P_INIT_FILE != "") $readmemh(P_INIT_FILE, mem);
    end

    // 输出流水线始终打拍 (等效真实 BMG regce 常使能)。
    // 不可用 ena 门控: NPU 在 FLUSHING(ena=0) 阶段仍需接收最后 2 个在途权重数据。
    always @(posedge clka) begin
        rd1 <= mem[addra];   // 第1级: 地址 -> 数据
        rd2 <= rd1;          // 第2级: 输出寄存 (共 2 拍延迟)
    end

    assign douta = rd2;
endmodule

