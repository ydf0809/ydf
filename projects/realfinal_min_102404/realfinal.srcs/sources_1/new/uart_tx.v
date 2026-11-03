module uart_tx #(
    parameter CLK_FREQ = 50000000,
    parameter UART_BPS = 115200
)(
    input               clk         ,
    input               rst_n       ,

    input               uart_tx_en  ,
    input       [7:0]   uart_tx_data,
    output reg          uart_txd    ,
    output reg          uart_tx_busy
);

localparam BAUD_CNT_MAX = CLK_FREQ / UART_BPS;

reg [15:0] baud_cnt;
reg [3:0]  bit_idx;
reg [7:0]  tx_data_r;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        uart_tx_busy <= 1'b0;
        uart_txd     <= 1'b1;
        baud_cnt     <= 16'd0;
        bit_idx      <= 4'd0;
        tx_data_r    <= 8'd0;
    end

    else if(uart_tx_en && !uart_tx_busy) begin
        uart_tx_busy <= 1'b1;
        uart_txd     <= 1'b0;
        baud_cnt     <= 16'd0;
        bit_idx      <= 4'd0;
        tx_data_r    <= uart_tx_data;
    end

    else if(uart_tx_busy) begin
        if(baud_cnt >= BAUD_CNT_MAX - 1'b1) begin
            baud_cnt <= 16'd0;
            if(bit_idx == 4'd9) begin
                uart_tx_busy <= 1'b0;
                uart_txd     <= 1'b1;
                bit_idx      <= 4'd0;
            end
            else begin
                bit_idx   <= bit_idx + 1'b1;
                tx_data_r <= {1'b0, tx_data_r[7:1]};

                if(bit_idx >= 4'd8)
                    uart_txd <= 1'b1;
                else
                    uart_txd <= tx_data_r[0];
            end
        end
        else
            baud_cnt <= baud_cnt + 1'b1;
    end
end

endmodule
