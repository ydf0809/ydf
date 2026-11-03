`timescale 1ns / 1ps

module spike_ram #(
    parameter P_WIDTH = 8,
    parameter P_DEPTH = 4096
) (
    input  wire                          clk,

    input  wire                          i_we,
    input  wire [$clog2(P_DEPTH)-1:0]    i_waddr,
    input  wire [P_WIDTH-1:0]            i_wdata,

    input  wire [$clog2(P_DEPTH)-1:0]    i_raddr,
    output wire [P_WIDTH-1:0]            o_rdata
);
    reg [P_WIDTH-1:0] mem [0:P_DEPTH-1];

    always @(posedge clk) begin
        if (i_we) mem[i_waddr] <= i_wdata;
    end

    assign o_rdata = mem[i_raddr];
endmodule
