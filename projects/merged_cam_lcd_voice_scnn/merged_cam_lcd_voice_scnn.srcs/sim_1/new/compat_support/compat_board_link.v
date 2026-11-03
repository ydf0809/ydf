module compat_board_link #(
    parameter CLK_FREQ = 33333333,
    parameter UART_BPS = 115200,
    parameter ECHO_EN  = 1'b0
)(
    input  wire       clk       ,
    input  wire       rst_n     ,

    input  wire       link_rx   ,
    output wire       link_tx   ,

    input  wire [7:0] local_cmd ,
    input  wire       local_send,

    output wire [7:0] peer_cmd  ,
    output wire       peer_valid,
    output       reg  link_err
);

wire [7:0] rx_cmd   ;
wire       rx_valid ;
wire       rx_err   ;
wire       tx_req   ;
wire [7:0] tx_cmd   ;

assign tx_req = local_send | (ECHO_EN & rx_valid & ~rx_cmd[7]);
assign tx_cmd = local_send ? local_cmd : rx_cmd;

compat_link_rx #(
    .CLK_FREQ (CLK_FREQ),
    .UART_BPS (UART_BPS))
    u_link_rx(
    .clk        (clk      ),
    .rst_n      (rst_n    ),
    .rxd        (link_rx  ),
    .peer_cmd   (rx_cmd   ),
    .peer_valid (rx_valid ),
    .err        (rx_err   )
    );

compat_link_tx #(
    .CLK_FREQ (CLK_FREQ),
    .UART_BPS (UART_BPS))
    u_link_tx(
    .clk    (clk    ),
    .rst_n  (rst_n  ),
    .req    (tx_req ),
    .cmd    (tx_cmd ),
    .txd    (link_tx),
    .busy   (       )
    );

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        link_err <= 1'b0;
    else if(rx_err)
        link_err <= 1'b1;
end

assign peer_cmd   = rx_cmd;
assign peer_valid = rx_valid;

endmodule
