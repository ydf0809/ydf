`timescale 1ns / 1ps

module pool_engine #(
    parameter P_IN_H  = 8,
    parameter P_IN_W  = 8,
    parameter P_CH    = 8,
    parameter P_POOL  = 2
) (
    input  wire                                  clk,
    input  wire                                  rst_n,
    input  wire                                  i_start,
    output wire                                  o_busy,
    output reg                                   o_done,

    output wire [$clog2(P_IN_H*P_IN_W)-1:0]      o_in_raddr,
    input  wire [P_CH-1:0]                       i_in_rdata,

    output reg                                   o_out_we,
    output reg  [$clog2((P_IN_H/P_POOL)*(P_IN_W/P_POOL))-1:0] o_out_waddr,
    output reg  [P_CH-1:0]                        o_out_wdata
);
    localparam OUT_H   = P_IN_H / P_POOL;
    localparam OUT_W   = P_IN_W / P_POOL;
    localparam IN_AW   = $clog2(P_IN_H*P_IN_W);
    localparam OUT_AW  = $clog2(OUT_H*OUT_W);
    localparam TAPS    = P_POOL*P_POOL;
    localparam TAPW    = $clog2(TAPS);

    localparam S_IDLE=2'd0, S_ACC=2'd1, S_WRITE=2'd2, S_DONE=2'd3;
    reg [1:0] state;

    reg [$clog2(OUT_H)-1:0] orr;
    reg [$clog2(OUT_W)-1:0] occ;
    reg [TAPW:0]            j;
    reg [P_CH-1:0]          acc;

    assign o_busy = (state != S_IDLE);

    integer dr_i, dc_i, inr_i, inc_i;
    reg [IN_AW-1:0] in_addr_c;
    always @(*) begin
        dr_i  = j / P_POOL;
        dc_i  = j - dr_i*P_POOL;
        inr_i = orr*P_POOL + dr_i;
        inc_i = occ*P_POOL + dc_i;
        in_addr_c = inr_i*P_IN_W + inc_i;
    end
    assign o_in_raddr = in_addr_c;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            orr <= 0; occ <= 0; j <= 0; acc <= 0;
            o_out_we <= 1'b0; o_out_waddr <= 0; o_out_wdata <= 0;
            o_done <= 1'b0;
        end else begin
            o_done   <= 1'b0;
            o_out_we <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (i_start) begin
                        orr <= 0; occ <= 0; j <= 0; acc <= 0;
                        state <= S_ACC;
                    end
                end
                S_ACC: begin
                    acc <= acc | i_in_rdata;
                    if (j == TAPS-1) state <= S_WRITE;
                    else             j     <= j + 1'b1;
                end
                S_WRITE: begin
                    o_out_we    <= 1'b1;
                    o_out_waddr <= orr*OUT_W + occ;
                    o_out_wdata <= acc;

                    if (orr == OUT_H-1 && occ == OUT_W-1) begin
                        state <= S_DONE;
                    end else begin
                        if (occ == OUT_W-1) begin occ <= 0; orr <= orr + 1'b1; end
                        else                      occ <= occ + 1'b1;
                        acc   <= 0;
                        j     <= 0;
                        state <= S_ACC;
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
