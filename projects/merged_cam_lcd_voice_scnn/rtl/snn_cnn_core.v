`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/28 22:34:42
// Design Name: 
// Module Name: snn_cnn_core
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


module snn_cnn_core #(
    parameter P_IN_H   = 16,
    parameter P_IN_W   = 16,
    parameter P_CIN    = 3,
    parameter P_C1     = 8,
    parameter P_C2     = 16,
    parameter P_K      = 3,
    parameter P_NUM_OUT= 2,
    parameter P_T_MAX  = 8,
    parameter P_VBITS  = 26,
    parameter P_VFRAC  = 12,
    parameter P_W1_FILE = "",
    parameter P_W2_FILE = "",
    parameter P_FC0_FILE = "",
    parameter P_FC1_FILE = ""
) (
    input  wire clk,
    input  wire rst_n,
    input  wire i_start_image,
    output wire o_busy,
    output wire o_done_image,

    output wire [$clog2(P_NUM_OUT)-1:0] o_label,
    output wire [$clog2(P_T_MAX+1)-1:0] o_max_count,
    output wire [P_NUM_OUT*$clog2(P_T_MAX+1)-1:0] o_all_spike_counts,
    output wire                         o_label_valid,

    // 编码握手 (外部编码器)
    output wire o_encode_start,
    input  wire i_encode_done,
    // 输入脉冲RAM写入 (外部编码器/TB)
    input  wire                              i_in_we,
    input  wire [$clog2(P_IN_H*P_IN_W)-1:0]  i_in_waddr,
    input  wire [P_CIN-1:0]                  i_in_wdata
);
    localparam H3 = P_IN_H/8, W3 = P_IN_W/8;

    // 控制 <-> 链路 / 分类头 握手线
    wire chain_start, chain_clear, chain_done;
    wire clf_step_start, clf_step_done, clf_decide;

    // 链路 pool3 <-> 分类头 特征读
    wire [$clog2(H3*W3)-1:0] feat_addr;
    wire [P_C2-1:0]          feat_data;

    control_unit_cnn #(
    	.P_T_MAX(P_T_MAX)
    ) u_ctrl (
        .clk(clk), 
        .rst_n(rst_n),
        .i_start_image(i_start_image), 
        .o_busy(o_busy), 
        .o_done_image(o_done_image),
        .o_encode_start(o_encode_start), 
        .i_encode_done(i_encode_done),
        .o_chain_start(chain_start), 
        .o_chain_clear(chain_clear), 
        .i_chain_done(chain_done),
        .o_clf_step_start(clf_step_start), 
        .i_clf_step_done(clf_step_done), 
        .o_clf_decide(clf_decide)
    );

    scnn_chain #(
        .P_IN_H(P_IN_H), 
        .P_IN_W(P_IN_W), 
        .P_CIN(P_CIN), 
        .P_C1(P_C1), 
        .P_C2(P_C2), 
        .P_K(P_K),
        .P_VBITS(P_VBITS), 
        .P_VFRAC(P_VFRAC), 
        .P_W1_FILE(P_W1_FILE), 
        .P_W2_FILE(P_W2_FILE)
    ) u_chain (
        .clk(clk), 
        .rst_n(rst_n), 
        .i_start(chain_start), 
        .i_clear(chain_clear),
        .o_done(chain_done), 
        .o_busy(),
        .i_in_we(i_in_we), 
        .i_in_waddr(i_in_waddr), 
        .i_in_wdata(i_in_wdata),
        .i_fo_raddr(feat_addr), 
        .o_fo_rdata(feat_data)
    );

    fc_classifier #(
        .P_H3(H3), 
        .P_W3(W3), 
        .P_FEAT_CH(P_C2), 
        .P_NUM_OUT(P_NUM_OUT),
        .P_VBITS(P_VBITS), 
        .P_VFRAC(P_VFRAC), 
        .P_T_MAX(P_T_MAX),
        .P_W0_FILE(P_FC0_FILE), 
        .P_W1_FILE(P_FC1_FILE)
    ) u_clf (
        .clk(clk), 
        .rst_n(rst_n),
        .i_clear(chain_clear),
        .i_step_start(clf_step_start), 
        .i_decide(clf_decide), 
        .o_step_done(clf_step_done),
        .o_feat_raddr(feat_addr), 
        .i_feat_rdata(feat_data),
        .o_label(o_label), 
        .o_max_count(o_max_count), 
        .o_all_spike_counts(o_all_spike_counts),
        .o_label_valid(o_label_valid)
    );
endmodule

