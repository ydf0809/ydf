module compat_link_rx #(
    parameter CLK_FREQ = 33333333,
    parameter UART_BPS = 115200
)(
    input  wire       clk       ,
    input  wire       rst_n     ,

    input  wire       rxd       ,

    output wire [7:0] peer_cmd  ,
    output wire       peer_valid,
    output wire       err
);

wire [7:0] rx_data       ;
wire       rx_done       ;
wire       rx_frame_err  ;
wire [7:0] dec_cmd       ;
wire       dec_valid     ;
wire       dec_frame_err ;

compat_uart_rx #(
    .CLK_FREQ (CLK_FREQ),
    .UART_BPS (UART_BPS))
    u_uart_rx(
    .clk          (clk        ),
    .rst_n        (rst_n      ),
    .uart_rxd     (rxd        ),
    .uart_rx_done (rx_done    ),
    .uart_rx_data (rx_data    ),
    .frame_err    (rx_frame_err)
    );

asr_frame_decode u_asr_frame_decode(
    .clk          (clk        ),
    .rst_n        (rst_n      ),
    .uart_rx_data (rx_data    ),
    .uart_rx_done (rx_done    ),
    .cmd_id       (dec_cmd    ),
    .cmd_valid    (dec_valid  ),
    .frame_err    (dec_frame_err)
    );

assign peer_cmd   = dec_cmd;
assign peer_valid = dec_valid;
assign err        = dec_frame_err | rx_frame_err;

endmodule
