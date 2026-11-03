`timescale 1ns / 1ps

module control_unit_cnn #(
    parameter P_T_MAX = 20
) (
    input  wire clk,
    input  wire rst_n,
    input  wire i_start_image,
    output wire o_busy,
    output reg  o_done_image,

    output reg  o_encode_start,
    input  wire i_encode_done,

    output reg  o_chain_start,
    output reg  o_chain_clear,
    input  wire i_chain_done,

    output reg  o_clf_step_start,
    input  wire i_clf_step_done,
    output reg  o_clf_decide
);
    localparam TW = $clog2(P_T_MAX + 1);
    reg [TW-1:0] t;

    localparam S_IDLE=4'd0, S_ENC_S=4'd1, S_ENC_W=4'd2, S_CH_S=4'd3, S_CH_W=4'd4,
               S_CL_S=4'd5, S_CL_W=4'd6, S_NEXT=4'd7, S_DEC=4'd8, S_IDONE=4'd9;
    reg [3:0] state;

    assign o_busy = (state != S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; t<=0;
            o_encode_start<=0; o_chain_start<=0; o_chain_clear<=0;
            o_clf_step_start<=0; o_clf_decide<=0; o_done_image<=0;
        end else begin
            o_encode_start<=0; o_chain_start<=0; o_chain_clear<=0;
            o_clf_step_start<=0; o_clf_decide<=0; o_done_image<=0;
            case (state)
                S_IDLE:  if (i_start_image) begin t<=0; state<=S_ENC_S; end
                S_ENC_S: begin o_encode_start<=1'b1; state<=S_ENC_W; end
                S_ENC_W: if (i_encode_done) state<=S_CH_S;
                S_CH_S:  begin o_chain_start<=1'b1; o_chain_clear<=(t==0); state<=S_CH_W; end
                S_CH_W:  if (i_chain_done) state<=S_CL_S;
                S_CL_S:  begin o_clf_step_start<=1'b1; state<=S_CL_W; end
                S_CL_W:  if (i_clf_step_done) state<=S_NEXT;
                S_NEXT:  if (t == P_T_MAX-1) state<=S_DEC;
                         else begin t<=t+1'b1; state<=S_ENC_S; end
                S_DEC:   begin o_clf_decide<=1'b1; state<=S_IDONE; end
                S_IDONE: begin o_done_image<=1'b1; state<=S_IDLE; end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
