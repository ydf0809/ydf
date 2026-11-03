`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/28 22:24:08
// Design Name: 
// Module Name: snn_cnn_top
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


module snn_cnn_top #(
    parameter P_IN_H   = 16,
    parameter P_IN_W   = 16,
    parameter P_CIN    = 3,
    parameter P_C1     = 8,
    parameter P_C2     = 16,
    parameter P_K      = 3,
    parameter P_NUM_OUT= 2,
    parameter P_T_MAX  = 8,
    parameter P_PIXEL_BITS = 8,
    parameter P_VBITS  = 26,
    parameter P_VFRAC  = 12,
    parameter P_W1_FILE   = "",
    parameter P_W2_FILE   = "",
    parameter P_FC0_FILE  = "",
    parameter P_FC1_FILE  = ""
) (
    input  wire clk,
    input  wire i_frame_clk,
    input  wire rst_n,
    input  wire i_start_image,
    output wire o_busy,
    output wire o_done_image,
    output wire [$clog2(P_NUM_OUT)-1:0] o_label,
    output wire [$clog2(P_T_MAX+1)-1:0] o_max_count,
    output wire [P_NUM_OUT*$clog2(P_T_MAX+1)-1:0] o_all_spike_counts,
    output wire                         o_label_valid,

    input  wire        i_frame_bank,
    input  wire        i_frame_we,
    input  wire [12:0] i_frame_addr,
    input  wire [23:0] i_frame_data
);
    localparam POS = P_IN_H*P_IN_W;

    // 控制 <-> 前端 握手 + 输入RAM写
    wire encode_start, encode_done;
    wire             in_we;
    wire [$clog2(POS)-1:0] in_waddr;
    wire [P_CIN-1:0] in_wdata;

    // 前端 <-> 帧ROM
    wire [$clog2(POS)-1:0]          frame_addr;
    wire [P_CIN*P_PIXEL_BITS-1:0]   frame_data;

    drone_frame_ram u_frame (
        .clk_wr  (i_frame_clk),
        .wr_en   (i_frame_we),
        .wr_addr (i_frame_addr),
        .wr_data (i_frame_data),
        .clk_rd  (clk),
        .rd_bank (i_frame_bank),
        .rd_addr (frame_addr),
        .rd_data (frame_data)
    );

    input_frontend #(
        .P_H(P_IN_H), 
        .P_W(P_IN_W), 
        .P_CIN(P_CIN), 
        .P_PIXEL_BITS(P_PIXEL_BITS)
    ) u_front (
        .clk(clk), 
        .rst_n(rst_n),
        .i_encode_start(encode_start), 
        .o_encode_done(encode_done),
        .o_frame_addr(frame_addr), 
        .i_frame_data(frame_data),
        .o_in_we(in_we), 
        .o_in_waddr(in_waddr), 
        .o_in_wdata(in_wdata)
    );

    snn_cnn_core #(
        .P_IN_H(P_IN_H), 
        .P_IN_W(P_IN_W), 
        .P_CIN(P_CIN), 
        .P_C1(P_C1), 
        .P_C2(P_C2), 
        .P_K(P_K),
        .P_NUM_OUT(P_NUM_OUT), 
        .P_T_MAX(P_T_MAX), 
        .P_VBITS(P_VBITS), 
        .P_VFRAC(P_VFRAC),
        .P_W1_FILE(P_W1_FILE), 
        .P_W2_FILE(P_W2_FILE), 
        .P_FC0_FILE(P_FC0_FILE), 
        .P_FC1_FILE(P_FC1_FILE)
    ) u_core (
        .clk(clk), 
        .rst_n(rst_n), 
        .i_start_image(i_start_image),
        .o_busy(o_busy), 
        .o_done_image(o_done_image),
        .o_label(o_label), 
        .o_max_count(o_max_count), 
        .o_all_spike_counts(o_all_spike_counts),
        .o_label_valid(o_label_valid),
        .o_encode_start(encode_start), 
        .i_encode_done(encode_done),
        .i_in_we(in_we), 
        .i_in_waddr(in_waddr), 
        .i_in_wdata(in_wdata)
    );
endmodule

