// Decode received voice-module frames into one-cycle command strobes.
module asr_frame_decode(
    input               clk         ,
    input               rst_n       ,

    input       [7:0]   uart_rx_data,
    input               uart_rx_done,

    output reg  [7:0]   cmd_id      ,
    output reg          cmd_valid   ,
    output reg          frame_err
);

parameter HEAD1 = 8'hAA;
parameter HEAD2 = 8'h55;
parameter TAIL1 = 8'h55;
parameter TAIL2 = 8'hAA;

localparam S_HEAD1 = 3'd0,
           S_HEAD2 = 3'd1,
           S_CMD   = 3'd2,
           S_TAIL1 = 3'd3,
           S_TAIL2 = 3'd4;

reg [2:0] state   ;
reg [7:0] cmd_id_t;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state     <= S_HEAD1;
        cmd_id_t  <= 8'd0;
        cmd_id    <= 8'd0;
        cmd_valid <= 1'b0;
        frame_err <= 1'b0;
    end
    else begin
        cmd_valid <= 1'b0;
        frame_err <= 1'b0;

        if(uart_rx_done) begin
            case(state)

                S_HEAD1: state <= (uart_rx_data == HEAD1) ? S_HEAD2 : S_HEAD1;

                S_HEAD2: state <= (uart_rx_data == HEAD2) ? S_CMD   :
                                  (uart_rx_data == HEAD1) ? S_HEAD2 : S_HEAD1;

                S_CMD  : begin
                    cmd_id_t <= uart_rx_data;
                    state    <= S_TAIL1;
                end

                S_TAIL1: state <= (uart_rx_data == TAIL1) ? S_TAIL2 :
                                  (uart_rx_data == HEAD1) ? S_HEAD2 : S_HEAD1;

                S_TAIL2: begin
                    state <= S_HEAD1;
                    if(uart_rx_data == TAIL2) begin
                        cmd_id    <= cmd_id_t;
                        cmd_valid <= 1'b1;
                    end
                    else
                        frame_err <= 1'b1;
                end

                default: state <= S_HEAD1;
            endcase
        end
    end
end

endmodule
