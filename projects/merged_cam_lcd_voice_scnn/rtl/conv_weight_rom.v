`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/28 22:51:47
// Design Name: 
// Module Name: conv_weight_rom
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


module conv_weight_rom #(
    parameter P_CIN          = 3,
    parameter P_COUT         = 8,
    parameter P_K            = 3,
    parameter P_WEIGHT_BITS  = 16,
    parameter P_INIT_FILE    = ""
) (
    input  wire [$clog2(P_K*P_K)-1:0]            i_tap_addr,   // 0..K*K-1
    output wire [P_CIN*P_COUT*P_WEIGHT_BITS-1:0] o_word
);
    localparam TAPS  = P_K * P_K;
    localparam WWORD = P_CIN * P_COUT * P_WEIGHT_BITS;

    reg [WWORD-1:0] rom [0:TAPS-1];

    initial begin
        if (P_INIT_FILE != "") $readmemh(P_INIT_FILE, rom);
    end

    assign o_word = rom[i_tap_addr];
endmodule

