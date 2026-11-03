`timescale 1ns / 1ps

module scnn_chain #(
    parameter P_IN_H   = 16,
    parameter P_IN_W   = 16,
    parameter P_CIN    = 3,
    parameter P_C1     = 8,
    parameter P_C2     = 16,
    parameter P_K      = 3,
    parameter P_WBITS  = 16,
    parameter P_VBITS  = 26,
    parameter P_VFRAC  = 12,
    parameter P_W1_FILE = "",
    parameter P_W2_FILE = ""
) (
    input  wire clk,
    input  wire rst_n,
    input  wire i_start,
    input  wire i_clear,
    output reg  o_done,
    output wire o_busy,

    input  wire                              i_in_we,
    input  wire [$clog2(P_IN_H*P_IN_W)-1:0]  i_in_waddr,
    input  wire [P_CIN-1:0]                  i_in_wdata,

    input  wire [$clog2((P_IN_H/8)*(P_IN_W/8))-1:0] i_fo_raddr,
    output wire [P_C2-1:0]                    o_fo_rdata
);

    localparam P1_H = P_IN_H/2, P1_W = P_IN_W/2;
    localparam P2_H = P1_H/2,   P2_W = P1_W/2;
    localparam P3_H = P2_H/2,   P3_W = P2_W/2;

    localparam IN_POS = P_IN_H*P_IN_W;
    localparam P1_POS = P1_H*P1_W;
    localparam P2_POS = P2_H*P2_W;
    localparam P3_POS = P3_H*P3_W;

    wire [$clog2(IN_POS)-1:0] in_raddr;  wire [P_CIN-1:0] in_rdata;

    wire c1_owe; wire [$clog2(IN_POS)-1:0] c1_owaddr; wire [P_C1-1:0] c1_owdata;
    wire [$clog2(IN_POS)-1:0] c1_raddr;  wire [P_C1-1:0] c1_rdata;

    wire p1_owe; wire [$clog2(P1_POS)-1:0] p1_owaddr; wire [P_C1-1:0] p1_owdata;
    wire [$clog2(P1_POS)-1:0] p1_raddr;  wire [P_C1-1:0] p1_rdata;

    wire c2_owe; wire [$clog2(P1_POS)-1:0] c2_owaddr; wire [P_C2-1:0] c2_owdata;
    wire [$clog2(P1_POS)-1:0] c2_raddr;  wire [P_C2-1:0] c2_rdata;

    wire p2_owe; wire [$clog2(P2_POS)-1:0] p2_owaddr; wire [P_C2-1:0] p2_owdata;
    wire [$clog2(P2_POS)-1:0] p2_raddr;  wire [P_C2-1:0] p2_rdata;

    wire p3_owe; wire [$clog2(P3_POS)-1:0] p3_owaddr; wire [P_C2-1:0] p3_owdata;

    wire [$clog2(P_K*P_K)-1:0] w1_addr; wire [P_CIN*P_C1*P_WBITS-1:0] w1_word;
    wire [$clog2(P_K*P_K)-1:0] w2_addr; wire [P_C1*P_C2*P_WBITS-1:0]  w2_word;

    reg  c1_start, c1_clear, p1_start, c2_start, c2_clear, p2_start, p3_start;
    wire c1_done, p1_done, c2_done, p2_done, p3_done;

    spike_ram #(.P_WIDTH(P_CIN), .P_DEPTH(IN_POS)) u_in_ram (
        .clk(clk), .i_we(i_in_we), .i_waddr(i_in_waddr), .i_wdata(i_in_wdata),
        .i_raddr(in_raddr), .o_rdata(in_rdata));
    spike_ram #(.P_WIDTH(P_C1), .P_DEPTH(IN_POS)) u_c1_ram (
        .clk(clk), .i_we(c1_owe), .i_waddr(c1_owaddr), .i_wdata(c1_owdata),
        .i_raddr(c1_raddr), .o_rdata(c1_rdata));
    spike_ram #(.P_WIDTH(P_C1), .P_DEPTH(P1_POS)) u_p1_ram (
        .clk(clk), .i_we(p1_owe), .i_waddr(p1_owaddr), .i_wdata(p1_owdata),
        .i_raddr(p1_raddr), .o_rdata(p1_rdata));
    spike_ram #(.P_WIDTH(P_C2), .P_DEPTH(P1_POS)) u_c2_ram (
        .clk(clk), .i_we(c2_owe), .i_waddr(c2_owaddr), .i_wdata(c2_owdata),
        .i_raddr(c2_raddr), .o_rdata(c2_rdata));
    spike_ram #(.P_WIDTH(P_C2), .P_DEPTH(P2_POS)) u_p2_ram (
        .clk(clk), .i_we(p2_owe), .i_waddr(p2_owaddr), .i_wdata(p2_owdata),
        .i_raddr(p2_raddr), .o_rdata(p2_rdata));
    spike_ram #(.P_WIDTH(P_C2), .P_DEPTH(P3_POS)) u_p3_ram (
        .clk(clk), .i_we(p3_owe), .i_waddr(p3_owaddr), .i_wdata(p3_owdata),
        .i_raddr(i_fo_raddr), .o_rdata(o_fo_rdata));

    drone_conv1_rom u_w1 (.i_tap_addr(w1_addr), .o_word(w1_word));
    drone_conv2_rom u_w2 (.i_tap_addr(w2_addr), .o_word(w2_word));

    conv_engine #(.P_IMG_H(P_IN_H), .P_IMG_W(P_IN_W), .P_CIN(P_CIN), .P_COUT(P_C1),
                  .P_K(P_K), .P_WEIGHT_BITS(P_WBITS), .P_VBITS(P_VBITS), .P_VFRAC(P_VFRAC)) u_conv1 (
        .clk(clk), .rst_n(rst_n), .i_start(c1_start), .i_clear_mem(c1_clear),
        .o_busy(), .o_done(c1_done),
        .o_in_raddr(in_raddr), .i_in_rdata(in_rdata),
        .o_w_addr(w1_addr), .i_w_word(w1_word),
        .o_out_we(c1_owe), .o_out_waddr(c1_owaddr), .o_out_wdata(c1_owdata));

    pool_engine #(.P_IN_H(P_IN_H), .P_IN_W(P_IN_W), .P_CH(P_C1), .P_POOL(2)) u_pool1 (
        .clk(clk), .rst_n(rst_n), .i_start(p1_start), .o_busy(), .o_done(p1_done),
        .o_in_raddr(c1_raddr), .i_in_rdata(c1_rdata),
        .o_out_we(p1_owe), .o_out_waddr(p1_owaddr), .o_out_wdata(p1_owdata));

    conv_engine #(.P_IMG_H(P1_H), .P_IMG_W(P1_W), .P_CIN(P_C1), .P_COUT(P_C2),
                  .P_K(P_K), .P_WEIGHT_BITS(P_WBITS), .P_VBITS(P_VBITS), .P_VFRAC(P_VFRAC)) u_conv2 (
        .clk(clk), .rst_n(rst_n), .i_start(c2_start), .i_clear_mem(c2_clear),
        .o_busy(), .o_done(c2_done),
        .o_in_raddr(p1_raddr), .i_in_rdata(p1_rdata),
        .o_w_addr(w2_addr), .i_w_word(w2_word),
        .o_out_we(c2_owe), .o_out_waddr(c2_owaddr), .o_out_wdata(c2_owdata));

    pool_engine #(.P_IN_H(P1_H), .P_IN_W(P1_W), .P_CH(P_C2), .P_POOL(2)) u_pool2 (
        .clk(clk), .rst_n(rst_n), .i_start(p2_start), .o_busy(), .o_done(p2_done),
        .o_in_raddr(c2_raddr), .i_in_rdata(c2_rdata),
        .o_out_we(p2_owe), .o_out_waddr(p2_owaddr), .o_out_wdata(p2_owdata));

    pool_engine #(.P_IN_H(P2_H), .P_IN_W(P2_W), .P_CH(P_C2), .P_POOL(2)) u_pool3 (
        .clk(clk), .rst_n(rst_n), .i_start(p3_start), .o_busy(), .o_done(p3_done),
        .o_in_raddr(p2_raddr), .i_in_rdata(p2_rdata),
        .o_out_we(p3_owe), .o_out_waddr(p3_owaddr), .o_out_wdata(p3_owdata));

    localparam S_IDLE=4'd0, S_C1S=4'd1, S_C1W=4'd2, S_P1S=4'd3, S_P1W=4'd4,
               S_C2S=4'd5, S_C2W=4'd6, S_P2S=4'd7, S_P2W=4'd8,
               S_P3S=4'd9, S_P3W=4'd10, S_DONE=4'd11;
    reg [3:0] state;
    reg       clr_latch;

    assign o_busy = (state != S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            c1_start<=0; c1_clear<=0; p1_start<=0; c2_start<=0; c2_clear<=0; p2_start<=0; p3_start<=0;
            clr_latch<=0; o_done<=0;
        end else begin

            c1_start<=0; c1_clear<=0; p1_start<=0; c2_start<=0; c2_clear<=0; p2_start<=0; p3_start<=0;
            o_done<=0;
            case (state)
                S_IDLE: if (i_start) begin clr_latch <= i_clear; state <= S_C1S; end
                S_C1S:  begin c1_start<=1; c1_clear<=clr_latch; state<=S_C1W; end
                S_C1W:  if (c1_done) state<=S_P1S;
                S_P1S:  begin p1_start<=1; state<=S_P1W; end
                S_P1W:  if (p1_done) state<=S_C2S;
                S_C2S:  begin c2_start<=1; c2_clear<=clr_latch; state<=S_C2W; end
                S_C2W:  if (c2_done) state<=S_P2S;
                S_P2S:  begin p2_start<=1; state<=S_P2W; end
                S_P2W:  if (p2_done) state<=S_P3S;
                S_P3S:  begin p3_start<=1; state<=S_P3W; end
                S_P3W:  if (p3_done) state<=S_DONE;
                S_DONE: begin o_done<=1; state<=S_IDLE; end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
