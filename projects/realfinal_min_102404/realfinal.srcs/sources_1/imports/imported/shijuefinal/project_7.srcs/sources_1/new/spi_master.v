`timescale 1ns / 1ps

module spi_master(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       req,
    input  wire [7:0] data_in,
    input  wire       dc_in,
    output reg        busy,

    output reg        spi_cs,
    output reg        spi_scl,
    output reg        spi_sda,
    output reg        spi_dc
);

    reg [3:0] bit_cnt;
    reg [7:0] shift_reg;
    reg [2:0] state;

    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam SHIFT = 3'd2;
    localparam END_P = 3'd3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_cs  <= 1'b1;
            spi_scl <= 1'b0;
            spi_sda <= 1'b0;
            spi_dc  <= 1'b1;
            busy    <= 1'b0;
            bit_cnt <= 4'd0;
            state   <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    spi_scl <= 1'b0;
                    spi_cs  <= 1'b1;
                    if (req) begin
                        shift_reg <= data_in;
                        spi_dc    <= dc_in;
                        busy      <= 1'b1;
                        spi_cs    <= 1'b0;
                        state     <= START;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                START: begin

                    spi_sda <= shift_reg[7];
                    shift_reg <= {shift_reg[6:0], 1'b0};
                    spi_scl <= 1'b0;
                    bit_cnt <= 4'd0;
                    state   <= SHIFT;
                end

                SHIFT: begin
                    if (spi_scl == 1'b0) begin
                        spi_scl <= 1'b1;
                    end else begin
                        spi_scl <= 1'b0;
                        bit_cnt <= bit_cnt + 1'b1;
                        if (bit_cnt == 4'd7) begin
                            state <= END_P;
                        end else begin
                            spi_sda <= shift_reg[7];
                            shift_reg <= {shift_reg[6:0], 1'b0};
                        end
                    end
                end

                END_P: begin
                    spi_cs <= 1'b1;
                    busy   <= 1'b0;
                    state  <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
