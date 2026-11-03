module link_demux #(
    parameter integer CLK_FREQ   = 33_333_333,
    parameter integer TIMEOUT_MS = 50
)(
    input  wire       clk        ,
    input  wire       rst_n      ,

    input  wire [7:0] peer_cmd   ,
    input  wire       peer_valid ,

    output reg  [4:0] track_pat  ,
    output reg        track_upd  ,
    output wire       cmd_valid
);

localparam integer TIMEOUT_TICKS = (CLK_FREQ / 1000) * TIMEOUT_MS;

reg [20:0] idle_cnt;

assign cmd_valid = peer_valid & ~peer_cmd[7];

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        track_pat <= 5'd0;
        track_upd <= 1'b0;
        idle_cnt  <= 21'd0;
    end
    else begin
        track_upd <= 1'b0;
        if(peer_valid && peer_cmd[7]) begin
            track_pat <= peer_cmd[4:0];
            track_upd <= 1'b1;
            idle_cnt  <= 21'd0;
        end
        else if(peer_valid) begin
            idle_cnt <= 21'd0;
        end
        else if(idle_cnt < TIMEOUT_TICKS[20:0]) begin
            idle_cnt <= idle_cnt + 1'b1;
        end
        else begin

            track_pat <= 5'd0;
        end
    end
end

endmodule
