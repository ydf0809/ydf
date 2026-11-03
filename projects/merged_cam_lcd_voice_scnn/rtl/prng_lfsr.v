// The 32-bit LFSR uses feedback taps 31,21,1,0; output uses the pre-shift high byte.
`timescale 1ns / 1ps

module prng_lfsr #(
    parameter INSTANCE_ID                    = 0,
    parameter P_PRNG_LFSR_WIDTH              = 32,
    parameter P_PIXEL_INTENSITY_BITS    = 8
) (
    input wire                                      clk,
    input wire                                      rst_n,
    input wire                                      i_enable_prng,

    output reg [P_PIXEL_INTENSITY_BITS-1:0]    o_random_output_reg,
    output reg                                      o_random_output_valid
);

    reg [P_PRNG_LFSR_WIDTH-1:0] lfsr_reg;

    wire feedback_bit;

    assign feedback_bit = (P_PRNG_LFSR_WIDTH == 32) ?
                          (lfsr_reg[0] ^ lfsr_reg[1] ^ lfsr_reg[21] ^ lfsr_reg[31]) :
                          lfsr_reg[P_PRNG_LFSR_WIDTH-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin

            automatic logic [P_PRNG_LFSR_WIDTH-1:0] base_seed;
            automatic logic [P_PRNG_LFSR_WIDTH-1:0] id_contribution;
            automatic logic [P_PRNG_LFSR_WIDTH-1:0] initial_seed_calc;
            base_seed = P_PRNG_LFSR_WIDTH'('hACE1F00D);

            id_contribution = P_PRNG_LFSR_WIDTH'(INSTANCE_ID) * P_PRNG_LFSR_WIDTH'('h10101011);

            id_contribution = id_contribution ^
                            (P_PRNG_LFSR_WIDTH'(INSTANCE_ID) << 7) ^
                            (P_PRNG_LFSR_WIDTH'(INSTANCE_ID) << 15) ^
                            (P_PRNG_LFSR_WIDTH'(INSTANCE_ID) << 23);
            initial_seed_calc = base_seed ^ id_contribution;
            if (initial_seed_calc == {P_PRNG_LFSR_WIDTH{1'b0}}) begin

                lfsr_reg <= P_PRNG_LFSR_WIDTH'(('hDEADBEEF + INSTANCE_ID + (INSTANCE_ID >> 3) + 1));
                if (lfsr_reg == {P_PRNG_LFSR_WIDTH{1'b0}}) begin
                    lfsr_reg <= P_PRNG_LFSR_WIDTH'(INSTANCE_ID + 1'b1);
                     if (lfsr_reg == {P_PRNG_LFSR_WIDTH{1'b0}}) lfsr_reg <= 1;
                end
            end else begin
                lfsr_reg <= initial_seed_calc;
            end
            o_random_output_reg   <= {P_PIXEL_INTENSITY_BITS{1'b0}};
            o_random_output_valid <= 1'b0;
        end else begin
            o_random_output_valid <= 1'b0;

            if (i_enable_prng) begin
                lfsr_reg <= {lfsr_reg[P_PRNG_LFSR_WIDTH-2:0], feedback_bit};

                o_random_output_reg   <= lfsr_reg[P_PRNG_LFSR_WIDTH-1 : P_PRNG_LFSR_WIDTH - P_PIXEL_INTENSITY_BITS];
                o_random_output_valid <= 1'b1;

            end
        end
    end

endmodule
