`timescale 1ns / 1ps

module fc_classifier #(
    parameter P_H3        = 2,
    parameter P_W3        = 2,
    parameter P_FEAT_CH   = 16,
    parameter P_NUM_OUT   = 2,
    parameter P_WBITS     = 16,
    parameter P_VBITS     = 26,
    parameter P_VFRAC     = 12,
    parameter P_T_MAX     = 20,
    parameter P_W0_FILE   = "",
    parameter P_W1_FILE   = ""
) (
    input  wire clk,
    input  wire rst_n,
    input  wire i_clear,
    input  wire i_step_start,
    input  wire i_decide,
    output reg  o_step_done,

    output reg  [$clog2(P_H3*P_W3)-1:0] o_feat_raddr,
    input  wire [P_FEAT_CH-1:0]         i_feat_rdata,

    output wire [$clog2(P_NUM_OUT)-1:0] o_label,
    output wire [$clog2(P_T_MAX+1)-1:0] o_max_count,
    output wire [P_NUM_OUT*$clog2(P_T_MAX+1)-1:0] o_all_spike_counts,
    output wire                         o_label_valid
);
    localparam FEAT_POS = P_H3*P_W3;
    localparam FCIN     = FEAT_POS*P_FEAT_CH;
    localparam DEPTH    = FCIN/4;
    localparam BAW      = $clog2(DEPTH);

    reg [FCIN-1:0] flat_vec;
    reg [$clog2(FEAT_POS)-1:0] pp;

    reg                       npu_start;
    wire [BAW-1:0] a0, a1; wire ena0, ena1; wire [63:0] d0, d1;
    wire signed [P_VBITS-1:0] cur0, cur1; wire vld0, vld1;

    drone_fc0_rom u_w0 (
        .clka(clk), .ena(ena0), .addra(a0), .douta(d0));
    drone_fc1_rom u_w1 (
        .clka(clk), .ena(ena1), .addra(a1), .douta(d1));

    neuron_processing_unit #(
        .P_NUM_INPUT_PIXELS(FCIN), .P_WEIGHT_BIT_WIDTH(P_WBITS),
        .P_NEURON_VALUE_TOTAL_BITS(P_VBITS), .P_NEURON_VALUE_FRAC_BITS(P_VFRAC),
        .P_BRAM_DATA_WIDTH(64), .P_BRAM_ADDR_WIDTH(BAW), .P_BRAM_EFFECTIVE_DEPTH(DEPTH)
    ) u_npu0 (
        .clk(clk), .rst_n(rst_n), .i_calc_start(npu_start),
        .i_input_spike_vector(flat_vec), .i_bram_dout_raw(d0),
        .o_bram_addr_to_issue(a0), .o_bram_ena(ena0),
        .o_output_current_I(cur0), .o_current_valid_out(vld0));

    neuron_processing_unit #(
        .P_NUM_INPUT_PIXELS(FCIN), .P_WEIGHT_BIT_WIDTH(P_WBITS),
        .P_NEURON_VALUE_TOTAL_BITS(P_VBITS), .P_NEURON_VALUE_FRAC_BITS(P_VFRAC),
        .P_BRAM_DATA_WIDTH(64), .P_BRAM_ADDR_WIDTH(BAW), .P_BRAM_EFFECTIVE_DEPTH(DEPTH)
    ) u_npu1 (
        .clk(clk), .rst_n(rst_n), .i_calc_start(npu_start),
        .i_input_spike_vector(flat_vec), .i_bram_dout_raw(d1),
        .o_bram_addr_to_issue(a1), .o_bram_ena(ena1),
        .o_output_current_I(cur1), .o_current_valid_out(vld1));

    wire [P_NUM_OUT*P_VBITS-1:0] lif_currents;
    assign lif_currents[0*P_VBITS +: P_VBITS] = cur0;
    assign lif_currents[1*P_VBITS +: P_VBITS] = cur1;
    reg                       lif_en;
    wire [P_NUM_OUT-1:0]      lif_spikes;
    wire                      lif_valid;

    lif_neuron_layer #(
        .P_NUM_OUTPUT_NEURONS(P_NUM_OUT), .P_NEURON_VALUE_TOTAL_BITS(P_VBITS),
        .P_NEURON_VALUE_FRAC_BITS(P_VFRAC)
    ) u_lif (
        .clk(clk), .rst_n(rst_n), .i_enable_layer(lif_en),
        .i_clear(i_clear),
        .i_all_currents_I(lif_currents),
        .o_all_spikes_out(lif_spikes), .o_all_spikes_valid(lif_valid));

    reg accum_en, dec_en;
    output_logic #(.P_NUM_OUTPUT_NEURONS(P_NUM_OUT), .P_T_MAX(P_T_MAX)) u_out (
        .clk(clk), .rst_n(rst_n),
        .i_accum_en(accum_en), .i_decision_en(dec_en),
        .i_lif_spike_vector(lif_spikes),
        .o_predicted_label(o_label), .o_max_spike_count(o_max_count),
        .o_all_spike_counts(o_all_spike_counts),
        .o_prediction_valid(o_label_valid));

    localparam S_IDLE=3'd0, S_FLAT=3'd1, S_FC=3'd2, S_FCW=3'd3,
               S_LIF=3'd4, S_LIFW=3'd5, S_ACC=3'd6, S_DONE=3'd7;
    reg [2:0] state;

    integer ch;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; pp<=0; flat_vec<=0; o_feat_raddr<=0;
            npu_start<=0; lif_en<=0; accum_en<=0; dec_en<=0; o_step_done<=0;
        end else begin
            npu_start<=0; lif_en<=0; accum_en<=0; dec_en<=0; o_step_done<=0;
            case (state)
                S_IDLE: begin
                    if (i_step_start) begin
                        pp <= 0; o_feat_raddr <= 0; state <= S_FLAT;
                    end else if (i_decide) begin
                        dec_en <= 1'b1;
                    end
                end
                S_FLAT: begin

                    for (ch = 0; ch < P_FEAT_CH; ch = ch + 1)
                        flat_vec[FCIN-1 - (ch*FEAT_POS + pp)] <= i_feat_rdata[ch];
                    if (pp == FEAT_POS-1) begin
                        state <= S_FC;
                    end else begin
                        pp <= pp + 1'b1;
                        o_feat_raddr <= pp + 1'b1;
                    end
                end
                S_FC:   begin npu_start <= 1'b1; state <= S_FCW; end
                S_FCW:  if (vld0) state <= S_LIF;
                S_LIF:  begin lif_en <= 1'b1; state <= S_LIFW; end
                S_LIFW: if (lif_valid) state <= S_ACC;
                S_ACC:  begin accum_en <= 1'b1; state <= S_DONE; end
                S_DONE: begin o_step_done <= 1'b1; state <= S_IDLE; end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
