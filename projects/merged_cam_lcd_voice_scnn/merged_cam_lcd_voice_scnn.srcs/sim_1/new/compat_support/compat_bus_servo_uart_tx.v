module compat_bus_servo_uart_tx #(
    parameter integer CLK_HZ = 33300000,
    parameter integer BAUD   = 115200
)(
    input  wire       sys_clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] data_in,
    output reg        txd,
    output reg        busy,
    output reg        done
);

    localparam integer BAUD_DIV = CLK_HZ / BAUD;

    reg [15:0] baud_cnt;
    reg [3:0]  bit_idx;
    reg [7:0]  shift_reg;

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            txd       <= 1'b1;
            busy      <= 1'b0;
            done      <= 1'b0;
            baud_cnt  <= 16'd0;
            bit_idx   <= 4'd0;
            shift_reg <= 8'd0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                txd      <= 1'b1;
                baud_cnt <= 16'd0;
                bit_idx  <= 4'd0;

                if (start) begin
                    busy      <= 1'b1;
                    shift_reg <= data_in;
                    txd       <= 1'b0;
                end else begin
                    busy <= 1'b0;
                end
            end else begin
                if (baud_cnt == BAUD_DIV - 1) begin
                    baud_cnt <= 16'd0;

                    if (bit_idx < 4'd8) begin
                        txd       <= shift_reg[0];
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        bit_idx   <= bit_idx + 1'b1;
                    end else if (bit_idx == 4'd8) begin
                        txd     <= 1'b1;
                        bit_idx <= 4'd9;
                    end else begin
                        busy    <= 1'b0;
                        txd     <= 1'b1;
                        done    <= 1'b1;
                        bit_idx <= 4'd0;
                    end
                end else begin
                    baud_cnt <= baud_cnt + 1'b1;
                end
            end
        end
    end

endmodule
