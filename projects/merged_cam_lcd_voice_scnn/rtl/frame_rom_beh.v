`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/28 22:27:26
// Design Name: 
// Module Name: frame_rom_beh
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


module frame_rom_beh #(
    parameter P_DATA_WIDTH = 24,      // = P_CIN * P_PIXEL_BITS
    parameter P_DEPTH      = 256,     // = H*W
    parameter P_INIT_FILE  = ""
) (
    input  wire [$clog2(P_DEPTH)-1:0] addr,
    output wire [P_DATA_WIDTH-1:0]    data
);
    reg [P_DATA_WIDTH-1:0] mem [0:P_DEPTH-1];
    initial begin
    if (P_INIT_FILE != "") 
        	$readmemh(P_INIT_FILE, mem);
    end
    
    assign data = mem[addr];
    
endmodule
