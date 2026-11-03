`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/28 22:52:19
// Design Name: 
// Module Name: conv_engine
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


module conv_engine #(
    parameter P_IMG_H        = 8,
    parameter P_IMG_W        = 8,
    parameter P_CIN          = 3,
    parameter P_COUT         = 8,
    parameter P_K            = 3,
    parameter P_WEIGHT_BITS  = 16,
    parameter P_VBITS        = 26,
    parameter P_VFRAC        = 12
) (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              i_start,        // 处理一个时间步
    input  wire                              i_clear_mem,    // 本次处理前先清零膜电位(新图像)
    output wire                              o_busy,
    output reg                               o_done,         // 单周期脉冲: 本时间步处理完毕

    // 输入脉冲 RAM (组合读)
    output wire [$clog2(P_IMG_H*P_IMG_W)-1:0] o_in_raddr,
    input  wire [P_CIN-1:0]                   i_in_rdata,

    // 权重 ROM (组合读)
    output wire [$clog2(P_K*P_K)-1:0]         o_w_addr,
    input  wire [P_CIN*P_COUT*P_WEIGHT_BITS-1:0] i_w_word,

    // 输出脉冲 RAM (同步写)
    output reg                               o_out_we,
    output reg  [$clog2(P_IMG_H*P_IMG_W)-1:0] o_out_waddr,
    output reg  [P_COUT-1:0]                  o_out_wdata
);
    localparam POS   = P_IMG_H * P_IMG_W;
    localparam ADDRW = $clog2(POS);
    localparam TAPS  = P_K * P_K;
    localparam TAPW  = $clog2(TAPS);
    localparam PAD   = (P_K-1)/2;

    // ---- FSM ----
    localparam S_IDLE=3'd0, S_CLR=3'd1, S_SET=3'd2, S_TAP=3'd3,
               S_LIF=3'd4, S_WAIT=3'd5, S_DONE=3'd6;
    reg [2:0] state;

    reg [$clog2(P_IMG_H)-1:0] r;
    reg [$clog2(P_IMG_W)-1:0] c;
    reg [TAPW:0]              k;       // 0..TAPS-1
    reg                       clr_pulse;

    reg signed [P_VBITS-1:0]  acc [0:P_COUT-1];

    assign o_busy   = (state != S_IDLE);
    assign o_w_addr = k[TAPW-1:0];

    // ---- 组合: 当前 tap 的邻域地址、越界判定、各输出通道贡献 ----
    integer ci_i, co_i, kk_h, kk_w, nr_i, nc_i;
    reg                      inb_c;
    reg [ADDRW-1:0]          nbr_addr_c;
    reg signed [P_VBITS-1:0] contrib_c [0:P_COUT-1];

    always @(*) begin
        kk_h = k / P_K;
        kk_w = k - kk_h*P_K;
        nr_i = r + kk_h - PAD;
        nc_i = c + kk_w - PAD;
        inb_c = (nr_i >= 0) && (nr_i < P_IMG_H) && (nc_i >= 0) && (nc_i < P_IMG_W);
        nbr_addr_c = inb_c ? (nr_i*P_IMG_W + nc_i) : {ADDRW{1'b0}};
        for (co_i = 0; co_i < P_COUT; co_i = co_i + 1) begin
            contrib_c[co_i] = {P_VBITS{1'b0}};
            for (ci_i = 0; ci_i < P_CIN; ci_i = ci_i + 1) begin
                if (inb_c && i_in_rdata[ci_i])
                    contrib_c[co_i] = contrib_c[co_i] +
                        $signed(i_w_word[(ci_i*P_COUT+co_i)*P_WEIGHT_BITS +: P_WEIGHT_BITS]);
            end
        end
    end

    assign o_in_raddr = nbr_addr_c;

    // 当前输出位置地址 + 打包电流给 lif_bram
    wire [ADDRW-1:0] pos_addr = r*P_IMG_W + c;
    wire [P_COUT*P_VBITS-1:0] acc_packed;
    genvar gp;
    generate
        for (gp = 0; gp < P_COUT; gp = gp + 1) begin : gen_pack
            assign acc_packed[gp*P_VBITS +: P_VBITS] = acc[gp];
        end
    endgenerate

    // ---- 内嵌 LIF 膜电位单元 ----
    wire                  lif_o_valid;
    wire [ADDRW-1:0]      lif_o_addr;
    wire [P_COUT-1:0]     lif_o_spikes;
    wire                  lif_clr_done;
    reg                   lif_i_valid;

    lif_bram #(
        .P_NUM_POS (POS),
        .P_CH      (P_COUT),
        .P_VBITS   (P_VBITS),
        .P_VFRAC   (P_VFRAC)
    ) u_lif (
        .clk          (clk),
        .rst_n        (rst_n),
        .i_clear      (clr_pulse),
        .o_clear_done (lif_clr_done),
        .i_valid      (lif_i_valid),
        .i_addr       (pos_addr),
        .i_currents   (acc_packed),
        .o_valid      (lif_o_valid),
        .o_addr       (lif_o_addr),
        .o_spikes     (lif_o_spikes)
    );

    integer z;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            r <= 0; c <= 0; k <= 0;
            clr_pulse   <= 1'b0;
            lif_i_valid <= 1'b0;
            o_out_we    <= 1'b0;
            o_out_waddr <= 0;
            o_out_wdata <= 0;
            o_done      <= 1'b0;
            for (z = 0; z < P_COUT; z = z + 1) acc[z] <= 0;
        end else begin
            o_done      <= 1'b0;
            o_out_we    <= 1'b0;
            lif_i_valid <= 1'b0;
            clr_pulse   <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (i_start) begin
                        r <= 0; c <= 0;
                        if (i_clear_mem) begin
                            clr_pulse <= 1'b1;     // 触发 lif 清零 (单周期脉冲)
                            state     <= S_CLR;
                        end else begin
                            state <= S_SET;
                        end
                    end
                end

                S_CLR: begin
                    if (lif_clr_done) state <= S_SET;
                end

                S_SET: begin
                    for (z = 0; z < P_COUT; z = z + 1) acc[z] <= 0;
                    k     <= 0;
                    state <= S_TAP;
                end

                S_TAP: begin
                    for (z = 0; z < P_COUT; z = z + 1)
                        acc[z] <= acc[z] + contrib_c[z];
                    if (k == TAPS-1) state <= S_LIF;
                    else             k     <= k + 1'b1;
                end

                S_LIF: begin
                    lif_i_valid <= 1'b1;          // 把累加电流交给 lif (隔1拍出脉冲)
                    state       <= S_WAIT;
                end

                S_WAIT: begin
                    if (lif_o_valid) begin
                        o_out_we    <= 1'b1;
                        o_out_waddr <= lif_o_addr;
                        o_out_wdata <= lif_o_spikes;
                        // 推进到下一个输出位置
                        if (r == P_IMG_H-1 && c == P_IMG_W-1) begin
                            state <= S_DONE;
                        end else begin
                            if (c == P_IMG_W-1) begin c <= 0; r <= r + 1'b1; end
                            else                      c <= c + 1'b1;
                            state <= S_SET;
                        end
                    end
                end

                S_DONE: begin
                    o_done <= 1'b1;
                    state  <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
