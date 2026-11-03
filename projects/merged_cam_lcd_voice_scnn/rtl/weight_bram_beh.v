`timescale 1ns / 1ps

module weight_bram_beh #(
    parameter P_DATA_WIDTH = 64,
    parameter P_DEPTH      = 16,
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

    always @(posedge clka) begin
        rd1 <= mem[addra];
        rd2 <= rd1;
    end

    assign douta = rd2;
endmodule
