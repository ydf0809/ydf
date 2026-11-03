// Sum active signed weights. The highest 16-bit lane maps to the first feature in each word.
`timescale 1ns / 1ps

module neuron_processing_unit #(
    parameter P_NUM_INPUT_PIXELS       = 784,
    parameter P_WEIGHT_BIT_WIDTH       = 16,
    parameter P_NEURON_VALUE_TOTAL_BITS = 26,
    parameter P_NEURON_VALUE_FRAC_BITS  = 12,

    parameter P_BRAM_DATA_WIDTH        = 64,
    parameter P_BRAM_ADDR_WIDTH        = 8,
    parameter P_BRAM_EFFECTIVE_DEPTH   = 196
) (
    input wire                                          clk,
    input wire                                          rst_n,
    input wire                                          i_calc_start,
    input wire  [P_NUM_INPUT_PIXELS-1:0]                i_input_spike_vector,
    input wire signed [P_BRAM_DATA_WIDTH-1:0]           i_bram_dout_raw,

    output reg [P_BRAM_ADDR_WIDTH-1:0]                  o_bram_addr_to_issue,
    output reg                                          o_bram_ena,
    output reg signed [P_NEURON_VALUE_TOTAL_BITS-1:0]    o_output_current_I,
    output reg                                          o_current_valid_out
);

    localparam WEIGHTS_NUMS_PER_WORD = P_BRAM_DATA_WIDTH / P_WEIGHT_BIT_WIDTH;
    localparam ADDR_MAX_VAL           = P_BRAM_EFFECTIVE_DEPTH - 1;
    localparam BRAM_READ_LATENCY      = 2;

    localparam LP_CNT_WIDTH           = $clog2(P_BRAM_EFFECTIVE_DEPTH + 1);
    localparam NUM_INPUT_PIXELS_BITS  = $clog2(P_NUM_INPUT_PIXELS);

    localparam STATE_BITS           = 2;
    localparam S_IDLE_VAL           = 2'b00;
    localparam S_PROCESSING_VAL     = 2'b01;
    localparam S_FLUSHING_VAL       = 2'b10;
    localparam S_DONE_VAL           = 2'b11;

    reg [STATE_BITS-1:0] current_state_reg, next_state_reg;

    reg [P_NUM_INPUT_PIXELS-1:0]                   latched_spike_vector_reg;
    reg signed [P_NEURON_VALUE_TOTAL_BITS-1:0]      accumulator_reg;

    reg [P_BRAM_ADDR_WIDTH-1:0]                    addr_pipeline_reg  [BRAM_READ_LATENCY-1:0];
    reg                                            valid_pipeline_reg [BRAM_READ_LATENCY-1:0];

    reg [LP_CNT_WIDTH-1:0]                  issued_addr_count_reg;
    reg [LP_CNT_WIDTH-1:0]                  processed_data_count_reg;

    wire signed [P_NEURON_VALUE_TOTAL_BITS-1:0] terms_comb [WEIGHTS_NUMS_PER_WORD-1:0];
    wire signed [P_NEURON_VALUE_TOTAL_BITS-1:0] sum_of_N_active_weights_comb;

    integer k_idx;
    genvar j_gen, l_gen, m_gen;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state_reg        <= S_IDLE_VAL;
            latched_spike_vector_reg <= {P_NUM_INPUT_PIXELS{1'b0}};
            accumulator_reg          <= {P_NEURON_VALUE_TOTAL_BITS{1'b0}};
            o_bram_addr_to_issue     <= {P_BRAM_ADDR_WIDTH{1'b0}};
            issued_addr_count_reg    <= {P_BRAM_ADDR_WIDTH{1'b0}};
            processed_data_count_reg <= {P_BRAM_ADDR_WIDTH{1'b0}};
            o_output_current_I       <= {P_NEURON_VALUE_TOTAL_BITS{1'b0}};
            o_current_valid_out      <= 1'b0;
            for (k_idx = 0; k_idx < BRAM_READ_LATENCY; k_idx = k_idx + 1) begin
                addr_pipeline_reg[k_idx]  <= {P_BRAM_ADDR_WIDTH{1'b0}};
                valid_pipeline_reg[k_idx] <= 1'b0;
            end
        end else begin
            current_state_reg   <= next_state_reg;
            o_current_valid_out <= 1'b0;

            if (current_state_reg == S_IDLE_VAL && next_state_reg == S_PROCESSING_VAL) begin
                latched_spike_vector_reg <= i_input_spike_vector;
                accumulator_reg          <= {P_NEURON_VALUE_TOTAL_BITS{1'b0}};
                o_bram_addr_to_issue     <= {P_BRAM_ADDR_WIDTH{1'b0}};
                issued_addr_count_reg    <= {P_BRAM_ADDR_WIDTH{1'b0}};
                processed_data_count_reg <= {P_BRAM_ADDR_WIDTH{1'b0}};

                for (k_idx = 0; k_idx < BRAM_READ_LATENCY; k_idx = k_idx + 1) begin
                    valid_pipeline_reg[k_idx] <= 1'b0;
                end
            end

            if (current_state_reg == S_PROCESSING_VAL || current_state_reg == S_FLUSHING_VAL) begin

                for (k_idx = BRAM_READ_LATENCY - 1; k_idx > 0; k_idx = k_idx - 1) begin
                    addr_pipeline_reg[k_idx]  <= addr_pipeline_reg[k_idx-1];
                    valid_pipeline_reg[k_idx] <= valid_pipeline_reg[k_idx-1];
                end
                valid_pipeline_reg[0] <= o_bram_ena;
                addr_pipeline_reg[0]  <= o_bram_addr_to_issue;
            end
            if ((current_state_reg == S_PROCESSING_VAL || current_state_reg == S_FLUSHING_VAL) && valid_pipeline_reg[BRAM_READ_LATENCY-1]) begin
                accumulator_reg          <= accumulator_reg + sum_of_N_active_weights_comb;
                processed_data_count_reg <= processed_data_count_reg + 1;
            end

            if (current_state_reg == S_PROCESSING_VAL && o_bram_ena) begin
                issued_addr_count_reg  <= issued_addr_count_reg + 1;
                if (o_bram_addr_to_issue < ADDR_MAX_VAL) begin
                    o_bram_addr_to_issue <= o_bram_addr_to_issue + 1;
                end
            end

            if (current_state_reg == S_DONE_VAL) begin
                o_output_current_I  <= accumulator_reg;
                o_current_valid_out <= 1'b1;
            end
        end
    end

    wire signed [P_WEIGHT_BIT_WIDTH-1:0]       w_from_bram        [WEIGHTS_NUMS_PER_WORD-1:0];
    wire                                       s_for_aligned_addr [WEIGHTS_NUMS_PER_WORD-1:0];

    generate
        for (j_gen = 0; j_gen < WEIGHTS_NUMS_PER_WORD; j_gen = j_gen + 1) begin : gen_unpack_weights
            assign w_from_bram[j_gen] = i_bram_dout_raw[(j_gen+1)*P_WEIGHT_BIT_WIDTH-1 : j_gen*P_WEIGHT_BIT_WIDTH];
        end
    endgenerate

    generate
        for (l_gen = 0; l_gen < WEIGHTS_NUMS_PER_WORD; l_gen = l_gen + 1) begin : gen_select_spikes

            localparam logical_offset_in_group_g = (WEIGHTS_NUMS_PER_WORD - 1) - l_gen;
            wire [P_BRAM_ADDR_WIDTH-1:0] current_word_addr_from_pipe_w;
            assign current_word_addr_from_pipe_w = addr_pipeline_reg[BRAM_READ_LATENCY-1];

            wire [NUM_INPUT_PIXELS_BITS-1:0] global_raster_idx_of_spike_w;
            assign global_raster_idx_of_spike_w    = (current_word_addr_from_pipe_w * WEIGHTS_NUMS_PER_WORD) + logical_offset_in_group_g;
            assign s_for_aligned_addr[l_gen] = latched_spike_vector_reg[P_NUM_INPUT_PIXELS - 1 - global_raster_idx_of_spike_w];
        end
    endgenerate

    generate
        for (m_gen = 0; m_gen < WEIGHTS_NUMS_PER_WORD; m_gen = m_gen + 1) begin : gen_terms_for_sum
            assign terms_comb[m_gen] = s_for_aligned_addr[m_gen] ?
                                {{(P_NEURON_VALUE_TOTAL_BITS - P_WEIGHT_BIT_WIDTH){w_from_bram[m_gen][P_WEIGHT_BIT_WIDTH-1]}}, w_from_bram[m_gen]} :
                                {P_NEURON_VALUE_TOTAL_BITS{1'b0}};
        end
    endgenerate

    assign sum_of_N_active_weights_comb = terms_comb[0] + terms_comb[1] + terms_comb[2] + terms_comb[3];

    always @(current_state_reg or i_calc_start or issued_addr_count_reg or processed_data_count_reg) begin
        next_state_reg = current_state_reg;
        o_bram_ena     = 1'b0;
        case (current_state_reg)
            S_IDLE_VAL: begin
                if (i_calc_start) begin
                    next_state_reg = S_PROCESSING_VAL;
                end
            end
            S_PROCESSING_VAL: begin

                if (issued_addr_count_reg < P_BRAM_EFFECTIVE_DEPTH) begin
                    o_bram_ena     = 1'b1;
                    next_state_reg = S_PROCESSING_VAL;
                end else begin
                    o_bram_ena     = 1'b0;
                    next_state_reg = S_FLUSHING_VAL;
                end
            end
            S_FLUSHING_VAL: begin
                o_bram_ena = 1'b0;

                if (processed_data_count_reg == P_BRAM_EFFECTIVE_DEPTH) begin
                    next_state_reg = S_DONE_VAL;
                end else begin
                    next_state_reg = S_FLUSHING_VAL;
                end
            end
            S_DONE_VAL: begin
                next_state_reg = S_IDLE_VAL;
            end
            default: next_state_reg = S_IDLE_VAL;
        endcase
    end

endmodule
