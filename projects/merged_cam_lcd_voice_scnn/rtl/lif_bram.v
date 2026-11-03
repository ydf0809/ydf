// Per-position LIF state in dual-port block RAM; signed arithmetic shift and hard reset.
`timescale 1ns / 1ps

module lif_bram #(
    parameter P_NUM_POS = 64,
    parameter P_CH      = 8,
    parameter P_VBITS   = 26,
    parameter P_VFRAC   = 12
) (
    input  wire                              clk,
    input  wire                              rst_n,

    input  wire                              i_clear,
    output reg                               o_clear_done,

    input  wire                              i_valid,
    input  wire [$clog2(P_NUM_POS)-1:0]      i_addr,
    input  wire [P_CH*P_VBITS-1:0]           i_currents,

    output reg                               o_valid,
    output reg  [$clog2(P_NUM_POS)-1:0]      o_addr,
    output reg  [P_CH-1:0]                   o_spikes
);
    localparam ADDRW = $clog2(P_NUM_POS);
    localparam DW    = P_CH*P_VBITS;
    localparam signed [P_VBITS-1:0] V_TH = (1 <<< P_VFRAC);

    reg [ADDRW-1:0] addr_s1;
    reg [DW-1:0]    cur_s1;
    reg             valid_s1;

    localparam S_IDLE=2'd0, S_CLEAR=2'd1, S_DONE=2'd2;
    reg [1:0]     cstate;
    reg [ADDRW:0] clr_cnt;
    wire          clearing = (cstate == S_CLEAR);

    reg  [DW-1:0] vmem_rd;
    wire [DW-1:0] v_next_packed;
    wire [P_CH-1:0] spk_comb;
    genvar c;
    generate
        for (c = 0; c < P_CH; c = c + 1) begin : gen_lif
            wire signed [P_VBITS-1:0] v_old = vmem_rd[c*P_VBITS +: P_VBITS];
            wire signed [P_VBITS-1:0] i_cur = cur_s1 [c*P_VBITS +: P_VBITS];
            wire signed [P_VBITS-1:0] diff  = i_cur - v_old;
            wire signed [P_VBITS-1:0] cand  = v_old + (diff >>> 1);
            assign spk_comb[c]                         = (cand >= V_TH);
            assign v_next_packed[c*P_VBITS +: P_VBITS] = (cand >= V_TH) ? {P_VBITS{1'b0}} : cand;
        end
    endgenerate

    (* ram_style = "block" *) reg [DW-1:0] vmem [0:P_NUM_POS-1];

    wire             ram_we    = valid_s1 | clearing;
    wire [ADDRW-1:0] ram_waddr = clearing ? clr_cnt[ADDRW-1:0] : addr_s1;
    wire [DW-1:0]    ram_wdata = clearing ? {DW{1'b0}}         : v_next_packed;

    always @(posedge clk) begin
        if (ram_we) vmem[ram_waddr] <= ram_wdata;
        vmem_rd <= vmem[i_addr];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_s1<=0; cur_s1<=0; valid_s1<=0;
            o_valid<=0; o_addr<=0; o_spikes<=0; o_clear_done<=0;
            cstate<=S_IDLE; clr_cnt<=0;
        end else begin
            o_valid      <= 1'b0;
            o_clear_done <= 1'b0;

            addr_s1  <= i_addr;
            cur_s1   <= i_currents;
            valid_s1 <= i_valid && (cstate == S_IDLE);

            if (valid_s1) begin
                o_addr   <= addr_s1;
                o_spikes <= spk_comb;
                o_valid  <= 1'b1;
            end

            case (cstate)
                S_IDLE:  if (i_clear) begin clr_cnt <= 0; cstate <= S_CLEAR; end
                S_CLEAR: if (clr_cnt == P_NUM_POS-1) cstate <= S_DONE;
                         else                        clr_cnt <= clr_cnt + 1'b1;
                S_DONE:  begin o_clear_done <= 1'b1; cstate <= S_IDLE; end
                default: cstate <= S_IDLE;
            endcase
        end
    end
endmodule
