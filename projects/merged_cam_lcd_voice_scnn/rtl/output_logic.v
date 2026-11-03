`timescale 1ns / 1ps

module output_logic #(
    parameter P_NUM_OUTPUT_NEURONS = 10,
    parameter P_T_MAX              = 100
) (
    input wire                               clk,
    input wire                               rst_n,

    input wire                               i_accum_en,
    input wire                               i_decision_en,

    input wire [P_NUM_OUTPUT_NEURONS-1:0]    i_lif_spike_vector,

    output reg [$clog2(P_NUM_OUTPUT_NEURONS)-1:0] o_predicted_label,
    output reg [$clog2(P_T_MAX + 1)-1:0]       o_max_spike_count,
    output reg [P_NUM_OUTPUT_NEURONS*$clog2(P_T_MAX + 1)-1:0] o_all_spike_counts,
    output reg                                   o_prediction_valid
);

    localparam LP_SPIKE_COUNTER_BITS = $clog2(P_T_MAX + 1);

    localparam LP_LABEL_WIDTH        = $clog2(P_NUM_OUTPUT_NEURONS);

    reg [LP_SPIKE_COUNTER_BITS-1:0] spike_counters_reg [P_NUM_OUTPUT_NEURONS-1:0];
    reg [LP_SPIKE_COUNTER_BITS-1:0] max_count_val_internal;
    reg [LP_LABEL_WIDTH-1:0]        max_index_val_internal;

    always @(posedge clk or negedge rst_n) begin
        integer i_loop_local;
        integer j_findmax_local;

        if (!rst_n) begin
            for (i_loop_local = 0; i_loop_local < P_NUM_OUTPUT_NEURONS; i_loop_local = i_loop_local + 1) begin
                spike_counters_reg[i_loop_local] <= {LP_SPIKE_COUNTER_BITS{1'b0}};
            end
            o_predicted_label      <= {LP_LABEL_WIDTH{1'b0}};
            o_max_spike_count      <= {LP_SPIKE_COUNTER_BITS{1'b0}};
            o_all_spike_counts     <= {P_NUM_OUTPUT_NEURONS*LP_SPIKE_COUNTER_BITS{1'b0}};
            o_prediction_valid     <= 1'b0;
            max_count_val_internal <= {LP_SPIKE_COUNTER_BITS{1'b0}};
            max_index_val_internal <= {LP_LABEL_WIDTH{1'b0}};
        end else begin
            o_prediction_valid <= 1'b0;
            if (i_accum_en) begin

                for (i_loop_local = 0; i_loop_local < P_NUM_OUTPUT_NEURONS; i_loop_local = i_loop_local + 1) begin
                    if (i_lif_spike_vector[i_loop_local] == 1'b1) begin
                        spike_counters_reg[i_loop_local] <= spike_counters_reg[i_loop_local] + 1;
                    end
                end
            end

            if (i_decision_en) begin

                max_count_val_internal = spike_counters_reg[0];
                max_index_val_internal = {LP_LABEL_WIDTH{1'b0}};
                for (j_findmax_local = 1; j_findmax_local < P_NUM_OUTPUT_NEURONS; j_findmax_local = j_findmax_local + 1) begin
                    if (spike_counters_reg[j_findmax_local] > max_count_val_internal) begin
                        max_count_val_internal = spike_counters_reg[j_findmax_local];
                        max_index_val_internal = j_findmax_local;
                    end
                end

                o_predicted_label      <= max_index_val_internal;
                o_max_spike_count      <= max_count_val_internal;
                for (i_loop_local = 0; i_loop_local < P_NUM_OUTPUT_NEURONS; i_loop_local = i_loop_local + 1) begin
                    o_all_spike_counts[i_loop_local*LP_SPIKE_COUNTER_BITS +: LP_SPIKE_COUNTER_BITS]
                        <= spike_counters_reg[i_loop_local];
                end
                o_prediction_valid     <= 1'b1;

                for (i_loop_local = 0; i_loop_local < P_NUM_OUTPUT_NEURONS; i_loop_local = i_loop_local + 1) begin
                    spike_counters_reg[i_loop_local] <= {LP_SPIKE_COUNTER_BITS{1'b0}};
                end
            end
        end
    end

endmodule
