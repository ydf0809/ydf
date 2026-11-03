`timescale 1ns / 1ps

module sccb_master(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       req,
    input  wire [7:0] dev_addr,
    input  wire [7:0] reg_addr,
    input  wire [7:0] reg_data,
    output reg        busy,

    output reg        sio_c,
    inout  wire       sio_d
);

    reg [8:0] clk_cnt;
    reg       en;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            clk_cnt <= 9'd0;
            en <= 1'b0;
        end else if(clk_cnt == 9'd186) begin
            clk_cnt <= 9'd0;
            en <= 1'b1;
        end else begin
            clk_cnt <= clk_cnt + 1'b1;
            en <= 1'b0;
        end
    end

    reg [5:0]  state;
    reg [23:0] shift_reg;
    reg [3:0]  bit_cnt;
    reg [1:0]  byte_cnt;

    reg        sda_dir;
    reg        sda_out;
    assign sio_d = sda_dir ? sda_out : 1'bz;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state    <= 6'd0;
            busy     <= 1'b0;
            sio_c    <= 1'b1;
            sda_dir  <= 1'b1;
            sda_out  <= 1'b1;
            shift_reg<= 24'd0;
            bit_cnt  <= 4'd0;
            byte_cnt <= 2'd0;
        end else begin
            if(req && !busy) begin
                busy      <= 1'b1;

                shift_reg <= {dev_addr, reg_addr, reg_data};
                state     <= 6'd1;
                bit_cnt   <= 4'd0;
                byte_cnt  <= 2'd0;
            end else if(busy && en) begin
                case(state)

                    6'd1: begin sio_c <= 1'b1; sda_dir <= 1'b1; sda_out <= 1'b1; state <= 6'd2; end

                    6'd2: begin sio_c <= 1'b1; sda_dir <= 1'b1; sda_out <= 1'b0; state <= 6'd3; end

                    6'd3: begin sio_c <= 1'b0; sda_dir <= 1'b1; sda_out <= 1'b0; state <= 6'd4; end

                    6'd4: begin
                        sio_c <= 1'b0;
                        sda_dir <= 1'b1;
                        sda_out <= shift_reg[23];
                        state <= 6'd5;
                    end

                    6'd5: begin sio_c <= 1'b1; state <= 6'd6; end

                    6'd6: begin sio_c <= 1'b1; state <= 6'd7; end

                    6'd7: begin
                        sio_c <= 1'b0;
                        shift_reg <= {shift_reg[22:0], 1'b0};
                        if (bit_cnt == 4'd7) begin
                            bit_cnt <= 4'd0;
                            state <= 6'd8;
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                            state <= 6'd4;
                        end
                    end

                    6'd8: begin
                        sio_c <= 1'b0;
                        sda_dir <= 1'b0;
                        state <= 6'd9;
                    end

                    6'd9: begin sio_c <= 1'b1; state <= 6'd10; end

                    6'd10: begin sio_c <= 1'b1; state <= 6'd11; end

                    6'd11: begin
                        sio_c <= 1'b0;
                        if (byte_cnt == 2'd0) begin
                            byte_cnt <= 2'd1;
                            state <= 6'd4;
                        end else if (byte_cnt == 2'd1) begin
                            byte_cnt <= 2'd2;
                            state <= 6'd4;
                        end else begin
                            state <= 6'd12;
                        end
                    end

                    6'd12: begin sio_c <= 1'b0; sda_dir <= 1'b1; sda_out <= 1'b0; state <= 6'd13; end

                    6'd13: begin sio_c <= 1'b1; sda_dir <= 1'b1; sda_out <= 1'b0; state <= 6'd14; end

                    6'd14: begin sio_c <= 1'b1; sda_dir <= 1'b1; sda_out <= 1'b1; state <= 6'd15; end

                    6'd15: begin busy <= 1'b0; state <= 6'd0; end

                    default: state <= 6'd0;
                endcase
            end
        end
    end
endmodule
