`timescale 1ns / 1ps

module frame_buffer #(
    parameter DEPTH  = 240000,
    parameter ADDR_W = 18,
    parameter DATA_W = 16
)(
    input  wire              clk_wr,
    input  wire              wr_en,
    input  wire [ADDR_W-1:0] wr_addr,
    input  wire [DATA_W-1:0] wr_data,

    input  wire              clk_rd,
    input  wire [ADDR_W-1:0] rd_addr,
    output reg  [DATA_W-1:0] rd_data
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
