module top_asr_voice #(
    parameter CLK_FREQ        = 33333333,
    parameter UART_BPS        = 115200  ,
    parameter ECHO_EN         = 1'b1    ,
    parameter GAP_MS          = 10      ,
    parameter BTN_ACTIVE_LOW  = 1'b1
)(
    input               sys_clk       ,
    input               btn_n         ,

    input               asr_rxd       ,
    output              asr_txd       ,

    output reg  [2:0]   mode          ,
    output reg          mode_upd      ,
    output reg          frame_err_flag
);

localparam GAP_CNT_MAX = CLK_FREQ / 1000 * GAP_MS;

wire [7:0] uart_rx_data  ;
wire       uart_rx_done  ;
wire       rx_frame_err  ;
wire [7:0] cmd_id        ;
wire       cmd_valid     ;
wire       frame_err     ;
wire       rst_n         ;
wire       uart_tx_busy  ;
wire       uart_tx_en    ;
wire [7:0] uart_tx_data  ;
wire       cmd_upd       ;

reg  [39:0] echo_shift  ;
reg  [2:0]  echo_idx    ;
reg  [1:0]  tx_state    ;
reg  [31:0] gap_cnt     ;
reg         cmd_pend    ;

localparam S_IDLE = 2'd0,
           S_GAP  = 2'd1,
           S_SEND = 2'd2;

rst_sync #(
    .BTN_ACTIVE_LOW (BTN_ACTIVE_LOW))
    u_rst_sync(
    .sys_clk        (sys_clk  ),
    .btn_n          (btn_n    ),
    .rst_n          (rst_n    )
    );

uart_rx #(
    .CLK_FREQ       (CLK_FREQ ),
    .UART_BPS       (UART_BPS ))
    u_uart_rx(
    .clk            (sys_clk      ),
    .rst_n          (rst_n        ),
    .uart_rxd       (asr_rxd      ),
    .uart_rx_done   (uart_rx_done ),
    .uart_rx_data   (uart_rx_data ),
    .frame_err      (rx_frame_err )
    );

asr_frame_decode u_asr_frame_decode(
    .clk            (sys_clk      ),
    .rst_n          (rst_n        ),
    .uart_rx_data   (uart_rx_data ),
    .uart_rx_done   (uart_rx_done ),
    .cmd_id         (cmd_id       ),
    .cmd_valid      (cmd_valid    ),
    .frame_err      (frame_err    )
    );

always @(posedge sys_clk or negedge rst_n) begin
    if(!rst_n) begin
        mode     <= 3'd0;
        mode_upd <= 1'b0;
    end
    else if(cmd_valid) begin
        mode     <= cmd_id[2:0];
        mode_upd <= 1'b1;
    end
    else
        mode_upd <= 1'b0;
end

always @(posedge sys_clk or negedge rst_n) begin
    if(!rst_n)
        frame_err_flag <= 1'b0;
    else if(frame_err || rx_frame_err)
        frame_err_flag <= 1'b1;
end

assign cmd_upd = cmd_valid;

always @(posedge sys_clk or negedge rst_n) begin
    if(!rst_n)
        cmd_pend <= 1'b0;
    else if(!ECHO_EN)
        cmd_pend <= 1'b0;
    else if(cmd_upd)
        cmd_pend <= 1'b1;
    else if(tx_state == S_IDLE)
        cmd_pend <= 1'b0;
end

always @(posedge sys_clk or negedge rst_n) begin
    if(!rst_n) begin
        tx_state   <= S_IDLE;
        gap_cnt    <= 32'd0;
        echo_idx   <= 3'd0;
        echo_shift <= 40'd0;
    end
    else begin
        case(tx_state)
            S_IDLE: begin
                if(ECHO_EN && cmd_pend) begin
                    echo_shift <= {8'hAA, 8'h55, cmd_id, 8'h55, 8'hAA};
                    echo_idx   <= 3'd0;
                    gap_cnt    <= 32'd0;
                    tx_state   <= S_GAP;
                end
            end

            S_GAP: begin
                if(gap_cnt >= GAP_CNT_MAX - 1'b1)
                    tx_state <= S_SEND;
                else
                    gap_cnt <= gap_cnt + 1'b1;
            end

            S_SEND: begin
                if(!uart_tx_busy) begin
                    echo_shift <= {echo_shift[31:0], 8'h00};
                    if(echo_idx == 3'd4)
                        tx_state <= S_IDLE;
                    else
                        echo_idx <= echo_idx + 1'b1;
                end
            end

            default: tx_state <= S_IDLE;
        endcase
    end
end

assign uart_tx_data = echo_shift[39:32];
assign uart_tx_en   = (tx_state == S_SEND) && !uart_tx_busy;

uart_tx #(
    .CLK_FREQ       (CLK_FREQ ),
    .UART_BPS       (UART_BPS ))
    u_uart_tx(
    .clk            (sys_clk      ),
    .rst_n          (rst_n        ),
    .uart_tx_en     (uart_tx_en   ),
    .uart_tx_data   (uart_tx_data ),
    .uart_txd       (asr_txd      ),
    .uart_tx_busy   (uart_tx_busy )
    );

endmodule
