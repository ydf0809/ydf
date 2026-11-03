// Signed LIF update: v+((I-v)>>>1); threshold is 1<<FRAC, with hard reset after firing.
`timescale 1ns / 1ps

module lif_neuron_cell #(

    parameter P_NEURON_VALUE_TOTAL_BITS      = 26,
    parameter P_NEURON_VALUE_FRAC_BITS = 12
) (
    input wire                                    clk,
    input wire                                    rst_n,
    input wire                                    i_clear,
    input wire                                    i_enable_neuron,
    input wire signed [P_NEURON_VALUE_TOTAL_BITS-1:0]  i_input_current_I,

    output reg                                    o_spike_out,
    output reg                                    o_spike_valid
);

    localparam signed [P_NEURON_VALUE_TOTAL_BITS-1:0] LP_V_THRESHOLD_FIXED =
        (P_NEURON_VALUE_FRAC_BITS >= 0 && P_NEURON_VALUE_FRAC_BITS < P_NEURON_VALUE_TOTAL_BITS) ?
        (1'b1 << P_NEURON_VALUE_FRAC_BITS) :
        P_NEURON_VALUE_TOTAL_BITS'(1);

    localparam signed [P_NEURON_VALUE_TOTAL_BITS-1:0] LP_V_RESET_FIXED     = {P_NEURON_VALUE_TOTAL_BITS{1'b0}};

    reg signed [P_NEURON_VALUE_TOTAL_BITS-1:0] membrane_potential_v_reg;

    wire signed [P_NEURON_VALUE_TOTAL_BITS-1:0] diff_I_v_comb;
    wire signed [P_NEURON_VALUE_TOTAL_BITS-1:0] delta_v_component_comb;
    wire signed [P_NEURON_VALUE_TOTAL_BITS-1:0] v_candidate_potential_comb;

    assign diff_I_v_comb = i_input_current_I - membrane_potential_v_reg;
    assign delta_v_component_comb = diff_I_v_comb >>> 1;
    assign v_candidate_potential_comb = membrane_potential_v_reg + delta_v_component_comb;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            membrane_potential_v_reg   <= LP_V_RESET_FIXED;
            o_spike_out                <= 1'b0;
            o_spike_valid              <= 1'b0;
        end else begin
            o_spike_valid <= 1'b0;

            if (i_clear) begin
                membrane_potential_v_reg <= LP_V_RESET_FIXED;
                o_spike_out              <= 1'b0;
            end else if (i_enable_neuron) begin
                o_spike_valid <= 1'b1;

                if (v_candidate_potential_comb >= LP_V_THRESHOLD_FIXED) begin
                    o_spike_out                <= 1'b1;
                    membrane_potential_v_reg   <= LP_V_RESET_FIXED;
                end else begin
                    o_spike_out   <= 1'b0;
                    membrane_potential_v_reg   <= v_candidate_potential_comb;
                end
            end
        end
    end

endmodule
