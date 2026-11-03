`timescale 1ns / 1ps

module frame_rom_beh #(
    parameter P_DATA_WIDTH = 24,
    parameter P_DEPTH      = 256,
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
