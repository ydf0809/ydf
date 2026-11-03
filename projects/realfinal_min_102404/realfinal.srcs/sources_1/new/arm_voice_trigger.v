module arm_voice_trigger #(
    parameter integer CLK_FREQ    = 33_333_333,
    parameter [7:0]   ARM_CMD     = 8'd5,
    parameter integer RST_HOLD_MS = 1
)(
    input  wire       clk       ,
    input  wire       rst_n     ,

    input  wire [7:0] cmd       ,
    input  wire       cmd_valid ,

    output reg        arm_req   ,
    output reg        arm_rst_n
);

localparam integer RST_TICKS = (CLK_FREQ / 1000) * RST_HOLD_MS;

reg [31:0] rst_cnt;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        arm_req   <= 1'b0;
        rst_cnt   <= 32'd0;
        arm_rst_n <= 1'b1;
    end
    else if(cmd_valid && (cmd == ARM_CMD)) begin
        arm_req   <= 1'b1;
        rst_cnt   <= RST_TICKS;
        arm_rst_n <= 1'b0;
    end
    else if(rst_cnt != 32'd0) begin
        rst_cnt   <= rst_cnt - 1'b1;
        arm_rst_n <= 1'b0;
    end
    else begin
        arm_rst_n <= 1'b1;
    end
end

endmodule
