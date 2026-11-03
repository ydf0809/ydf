// Banked network frame RAM; separate camera write and network read clocks.
`timescale 1ns / 1ps

module drone_frame_ram (
    input  wire        clk_wr,
    input  wire        wr_en,
    input  wire [12:0] wr_addr,
    input  wire [23:0] wr_data,

    input  wire        clk_rd,
    input  wire        rd_bank,
    input  wire [11:0] rd_addr,
    output reg  [23:0] rd_data
);
    (* ram_style = "block" *) reg [23:0] mem [0:8191];

    always @(posedge clk_wr) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    always @(posedge clk_rd) begin
        rd_data <= mem[{rd_bank, rd_addr}];
    end
endmodule
