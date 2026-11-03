module compat_link_tx #(
    parameter CLK_FREQ = 33333333,
    parameter UART_BPS = 115200
)(
    input  wire       clk     ,
    input  wire       rst_n   ,

    input  wire       req     ,
    input  wire [7:0] cmd     ,

    output wire       txd     ,
    output wire       busy
);

localparam [1:0] S_IDLE = 2'd0,
                 S_SEND = 2'd1;

reg  [1:0]  state;
reg  [39:0] shift;
reg  [2:0]  idx;
reg         pend;
reg  [7:0]  pend_cmd;

wire        tx_busy;
wire        tx_en;
wire [7:0]  tx_data;

assign tx_en   = (state == S_SEND) && !tx_busy;
assign tx_data = shift[39:32];
assign busy    = (state != S_IDLE) || pend;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state    <= S_IDLE;
        shift    <= 40'd0;
        idx      <= 3'd0;
        pend     <= 1'b0;
        pend_cmd <= 8'd0;
    end
    else begin
        case(state)
            S_IDLE: begin
                if(pend) begin
                    shift <= {8'hAA, 8'h55, pend_cmd, 8'h55, 8'hAA};
                    idx   <= 3'd0;
                    state <= S_SEND;
                end
            end

            S_SEND: begin
                if(!tx_busy) begin
                    shift <= {shift[31:0], 8'h00};
                    if(idx == 3'd4)
                        state <= S_IDLE;
                    else
                        idx <= idx + 1'b1;
                end
            end

            default: state <= S_IDLE;
        endcase

        if(req) begin
            pend     <= 1'b1;
            pend_cmd <= cmd;
        end
        else if((state == S_IDLE) && pend)
            pend <= 1'b0;
    end
end

compat_uart_tx #(
    .CLK_FREQ (CLK_FREQ),
    .UART_BPS (UART_BPS))
    u_uart_tx(
    .clk          (clk    ),
    .rst_n        (rst_n  ),
    .uart_tx_en   (tx_en  ),
    .uart_tx_data (tx_data),
    .uart_txd     (txd    ),
    .uart_tx_busy (tx_busy )
    );

endmodule
