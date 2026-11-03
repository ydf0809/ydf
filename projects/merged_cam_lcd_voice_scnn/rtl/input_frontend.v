`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/28 22:29:19
// Design Name: 
// Module Name: input_frontend
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


module input_frontend #(
    parameter P_H           = 16,
    parameter P_W           = 16,
    parameter P_CIN         = 3,
    parameter P_PIXEL_BITS  = 8,
    parameter P_PRNG_WIDTH  = 32
) (
    input  wire clk,
    input  wire rst_n,
    input  wire i_encode_start,
    output reg  o_encode_done,

    // 帧 ROM 读 (组合读, 每地址 = 一个像素的 P_CIN 个通道强度)
    output wire [$clog2(P_H*P_W)-1:0]       o_frame_addr,
    input  wire [P_CIN*P_PIXEL_BITS-1:0]    i_frame_data,

    // 写下游输入脉冲 RAM
    output reg                              o_in_we,
    output reg  [$clog2(P_H*P_W)-1:0]       o_in_waddr,
    output reg  [P_CIN-1:0]                 o_in_wdata
);
    localparam POS = P_H*P_W;
    localparam AW  = $clog2(POS);

    reg [AW-1:0] pos;
    reg          prng_en;

    // 每通道一个 PRNG
    wire [P_PIXEL_BITS-1:0] rnd      [0:P_CIN-1];
    wire                    rnd_vld  [0:P_CIN-1];
    genvar gi;
    generate
        for (gi = 0; gi < P_CIN; gi = gi + 1) begin : gen_prng
            prng_lfsr #(
                .INSTANCE_ID(gi+1), 
                .P_PRNG_LFSR_WIDTH(P_PRNG_WIDTH),
                .P_PIXEL_INTENSITY_BITS(P_PIXEL_BITS)
            ) u_prng (
                .clk(clk), 
                .rst_n(rst_n), 
                .i_enable_prng(prng_en),
                .o_random_output_reg(rnd[gi]), 
                .o_random_output_valid(rnd_vld[gi])
            );
        end
    endgenerate

    assign o_frame_addr = pos;

    // 组合: 当前像素各通道脉冲 = (随机数 < 强度)
    integer ci;
    reg [P_CIN-1:0] spikes_c;
    always @(*) begin
        for (ci = 0; ci < P_CIN; ci = ci + 1)
            spikes_c[ci] = (rnd[ci] < i_frame_data[ci*P_PIXEL_BITS +: P_PIXEL_BITS]);
    end

    // FSM: 每像素 2 拍 (REQ 让 PRNG 前进一次, CAP 取随机数比较并写脉冲)
    localparam S_IDLE=2'd0, S_REQ=2'd1, S_CAP=2'd2, S_DONE=2'd3;
    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; pos<=0; prng_en<=0;
            o_in_we<=0; o_in_waddr<=0; o_in_wdata<=0; o_encode_done<=0;
        end else begin
            prng_en<=0; o_in_we<=0; o_encode_done<=0;
            case (state)
                S_IDLE: if (i_encode_start) begin pos<=0; state<=S_REQ; end
                S_REQ:  begin prng_en<=1'b1; state<=S_CAP; end   // PRNG 前进一次
                S_CAP:  begin
                    o_in_we    <= 1'b1;        // 写当前像素脉冲
                    o_in_waddr <= pos;
                    o_in_wdata <= spikes_c;
                    if (pos == POS-1) state<=S_DONE;
                    else begin pos<=pos+1'b1; state<=S_REQ; end
                end
                S_DONE: begin o_encode_done<=1'b1; state<=S_IDLE; end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule

