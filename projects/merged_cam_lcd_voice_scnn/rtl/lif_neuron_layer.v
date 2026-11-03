`timescale 1ns / 1ps

module lif_neuron_layer #(
    parameter P_NUM_OUTPUT_NEURONS        = 10,
    parameter P_NEURON_VALUE_TOTAL_BITS   = 26,
    parameter P_NEURON_VALUE_FRAC_BITS = 12
) (
    input wire                                                                    clk,
    input wire                                                                    rst_n,
    input wire                                                                    i_clear,
    input wire                                                                    i_enable_layer,
    input wire signed [P_NUM_OUTPUT_NEURONS-1:0] [P_NEURON_VALUE_TOTAL_BITS-1:0]  i_all_currents_I,

    output wire [P_NUM_OUTPUT_NEURONS-1:0]                                        o_all_spikes_out,
    output wire                                                                   o_all_spikes_valid
);

    wire [P_NUM_OUTPUT_NEURONS-1:0]       neuron_cell_spike_outs_w;
    wire [P_NUM_OUTPUT_NEURONS-1:0]       neuron_cell_spike_valids_w;

    genvar n_idx, i_assign_spike;

    generate
        for (n_idx = 0; n_idx < P_NUM_OUTPUT_NEURONS; n_idx = n_idx + 1) begin : gen_lif_cells_in_layer

            lif_neuron_cell #(
                .P_NEURON_VALUE_TOTAL_BITS      (P_NEURON_VALUE_TOTAL_BITS),
                .P_NEURON_VALUE_FRAC_BITS (P_NEURON_VALUE_FRAC_BITS)
            ) u_lif_cell_inst (
                .clk                        (clk),
                .rst_n                      (rst_n),
                .i_clear                    (i_clear),
                .i_enable_neuron            (i_enable_layer),
                .i_input_current_I          (i_all_currents_I[n_idx]),

                .o_spike_out                (neuron_cell_spike_outs_w[n_idx]),
                .o_spike_valid              (neuron_cell_spike_valids_w[n_idx])
            );

        end
    endgenerate

    generate
        for (i_assign_spike = 0; i_assign_spike < P_NUM_OUTPUT_NEURONS; i_assign_spike = i_assign_spike + 1) begin : gen_assign_output_spikes
            assign o_all_spikes_out[i_assign_spike] = neuron_cell_spike_outs_w[i_assign_spike];
        end
    endgenerate

    assign o_all_spikes_valid = neuron_cell_spike_valids_w[0];

endmodule
