module uart_rx #(
    parameter CLK_FREQ = 50000000,
    parameter UART_BPS = 115200
)(
    input               clk         ,
    input               rst_n       ,

    input               uart_rxd    ,
    output reg          uart_rx_done,
    output reg  [7:0]   uart_rx_data,
    output reg          frame_err
);

localparam BAUD_CNT_MAX = CLK_FREQ / UART_BPS;
localparam HALF_CNT     = BAUD_CNT_MAX / 2;

reg        rxd_d0;
reg        rxd_d1;
reg        rxd_d2;
reg        rx_busy;
reg        rx_done_d;
reg [3:0]  bit_cnt;
reg [15:0] baud_cnt;
reg [7:0]  rx_shift;

wire start_en;
wire samp_en;

assign start_en = rxd_d2 & (~rxd_d1) & (~rx_busy);
assign samp_en  = (baud_cnt == HALF_CNT - 1'b1);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rxd_d0 <= 1'b1;
        rxd_d1 <= 1'b1;
        rxd_d2 <= 1'b1;
    end
    else begin
        rxd_d0 <= uart_rxd;
        rxd_d1 <= rxd_d0;
        rxd_d2 <= rxd_d1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        rx_busy <= 1'b0;
    else if(start_en)
        rx_busy <= 1'b1;
    else if(rx_done_d)
        rx_busy <= 1'b0;
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        baud_cnt <= 16'd0;
    else if(rx_busy) begin
        if(baud_cnt >= BAUD_CNT_MAX - 1'b1)
            baud_cnt <= 16'd0;
        else
            baud_cnt <= baud_cnt + 1'b1;
    end
    else
        baud_cnt <= 16'd0;
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        bit_cnt <= 4'd0;
    else if(rx_busy) begin
        if(baud_cnt == BAUD_CNT_MAX - 1'b1)
            bit_cnt <= bit_cnt + 1'b1;
    end
    else
        bit_cnt <= 4'd0;
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        rx_shift <= 8'd0;
    else if(rx_busy && samp_en) begin
        if(bit_cnt >= 4'd1 && bit_cnt <= 4'd8)
            rx_shift <= {rxd_d2, rx_shift[7:1]};
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        uart_rx_done <= 1'b0;
        uart_rx_data <= 8'd0;
        frame_err    <= 1'b0;
        rx_done_d    <= 1'b0;
    end
    else begin
        uart_rx_done <= 1'b0;
        frame_err    <= 1'b0;
        rx_done_d    <= 1'b0;

        if(rx_busy && samp_en && (bit_cnt == 4'd9)) begin
            uart_rx_done <= 1'b1;
            uart_rx_data <= rx_shift;
            rx_done_d    <= 1'b1;
            if(~rxd_d2)
                frame_err <= 1'b1;
        end
    end
end

endmodule
