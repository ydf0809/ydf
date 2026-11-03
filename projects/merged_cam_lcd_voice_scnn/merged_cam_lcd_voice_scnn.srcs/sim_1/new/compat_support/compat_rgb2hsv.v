`timescale 1ns / 1ps

module compat_rgb2hsv(
    input  wire        clk,
    input  wire        rst_n,
    
    input  wire        rgb_valid,
    input  wire [15:0] rgb565_in,
    
    output reg         hsv_valid,
    output reg  [8:0]  hsv_h, 
    output reg  [7:0]  hsv_s, 
    output reg  [7:0]  hsv_v  
);

    wire [7:0] r0 = {rgb565_in[15:11], rgb565_in[15:13]};
    wire [7:0] g0 = {rgb565_in[10:5],  rgb565_in[10:9]};
    wire [7:0] b0 = {rgb565_in[4:0],   rgb565_in[4:2]};
    wire [7:0] max0 = (r0 >= g0 && r0 >= b0) ? r0 : ((g0 >= r0 && g0 >= b0) ? g0 : b0);
    wire [7:0] min0 = (r0 <= g0 && r0 <= b0) ? r0 : ((g0 <= r0 && g0 <= b0) ? g0 : b0);
    wire [7:0] delta0 = max0 - min0;

    reg [7:0] r_reg, g_reg, b_reg, max_reg, delta_reg;
    reg valid_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_reg <= 0;
            r_reg <= 0; g_reg <= 0; b_reg <= 0;
            max_reg <= 0; delta_reg <= 0;
        end else begin
            valid_reg <= rgb_valid;
            r_reg <= r0; g_reg <= g0; b_reg <= b0;
            max_reg <= max0; delta_reg <= delta0;
        end
    end

    reg [8:0] h_next;
    reg [7:0] s_next;
    reg [7:0] v_next;
    
    always @(*) begin
        v_next = max_reg;
        //  ?   1  ?   16'd255   ?  λ ?? 
        s_next = (max_reg == 0) ? 8'd0 : ((delta_reg * 16'd255) / max_reg);
        
        if (delta_reg == 0) begin
            h_next = 9'd0;
        end else if (max_reg == r_reg) begin
            //  ?   2  ?   16'd60   ? ?  ??为    ?  ?    
            if (g_reg >= b_reg) h_next = ((g_reg - b_reg) * 16'd60) / delta_reg;
            else                h_next = 9'd360 - (((b_reg - g_reg) * 16'd60) / delta_reg);
        end else if (max_reg == g_reg) begin
            if (b_reg >= r_reg) h_next = 9'd120 + (((b_reg - r_reg) * 16'd60) / delta_reg);
            else                h_next = 9'd120 - (((r_reg - b_reg) * 16'd60) / delta_reg);
        end else begin
            if (r_reg >= g_reg) h_next = 9'd240 + (((r_reg - g_reg) * 16'd60) / delta_reg);
            else                h_next = 9'd240 - (((g_reg - r_reg) * 16'd60) / delta_reg);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hsv_valid <= 1'b0;
            hsv_h <= 9'd0; hsv_s <= 8'd0; hsv_v <= 8'd0;
        end else begin
            hsv_valid <= valid_reg;
            hsv_h <= h_next; hsv_s <= s_next; hsv_v <= v_next;
        end
    end
endmodule