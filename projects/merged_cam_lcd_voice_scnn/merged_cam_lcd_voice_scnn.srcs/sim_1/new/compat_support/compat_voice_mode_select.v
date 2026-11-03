module compat_voice_mode_select(
    input  wire       clk        ,
    input  wire       rst_n      ,

    input  wire [7:0] cmd        ,
    input  wire       cmd_valid  ,

    output wire       xunbi_en   ,
    output wire       vision_en  ,
    output wire       defense_en ,
    output wire       arm_en
);

reg [2:0] voice_mode;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        voice_mode <= 3'd0;
    else if(cmd_valid)
        voice_mode <= cmd[2:0];
end

assign xunbi_en  = (voice_mode == 3'd1);
assign vision_en = (voice_mode == 3'd2);
assign defense_en = (voice_mode == 3'd3);
assign arm_en    = (voice_mode == 3'd5);

endmodule
