module track_send #(
    parameter integer CLK_FREQ        = 33_333_333,
    parameter integer SEND_PERIOD_US  = 1000
)(
    input  wire       clk           ,
    input  wire       rst_n         ,

    input  wire       track_l2      ,
    input  wire       track_l1      ,
    input  wire       track_m       ,
    input  wire       track_r1      ,
    input  wire       track_r2      ,

    input  wire       mode_upd      ,
    input  wire [7:0] mode_cmd      ,

    output reg  [7:0] local_cmd     ,
    output reg        local_send
);

localparam integer SEND_TICKS = (CLK_FREQ / 1000000) * SEND_PERIOD_US;

reg [4:0]  pat_d0;
reg [4:0]  pat_d1;
reg [15:0] send_cnt;

wire [4:0] track_pat;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        pat_d0 <= 5'd0;
        pat_d1 <= 5'd0;
    end
    else begin
        pat_d0 <= {track_l2, track_l1, track_m, track_r1, track_r2};
        pat_d1 <= pat_d0;
    end
end

assign track_pat = ~pat_d1;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        send_cnt  <= 16'd0;
        local_cmd <= 8'd0;
        local_send<= 1'b0;
    end
    else begin
        local_send <= 1'b0;

        if(mode_upd) begin
            local_cmd  <= {3'b000, mode_cmd[4:0]};
            local_send <= 1'b1;
            send_cnt   <= 16'd0;
        end
        else if(send_cnt >= SEND_TICKS[15:0] - 16'd1) begin
            send_cnt   <= 16'd0;
            local_cmd  <= {1'b1, 2'b00, track_pat};
            local_send <= 1'b1;
        end
        else begin
            send_cnt <= send_cnt + 1'b1;
        end
    end
end

endmodule
