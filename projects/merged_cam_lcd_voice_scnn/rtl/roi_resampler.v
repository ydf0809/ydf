// Average each 2x2 RGB sample from a 128x128 ROI into the 64x64 network frame.
`timescale 1ns / 1ps

module roi_resampler #(
    parameter integer ROI_W = 128,
    parameter integer OUT_W = 64,
    parameter integer OUT_H = 64,
    parameter integer START_DELAY = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_sync,
    input  wire        enable,

    input  wire [9:0]  roi_x,
    input  wire [8:0]  roi_y,

    input  wire        pixel_valid,
    input  wire [9:0]  pixel_x,
    input  wire [8:0]  pixel_y,
    input  wire [15:0] pixel_rgb565,

    output reg         out_we,
    output reg  [11:0] out_addr,
    output reg  [23:0] out_data,
    output reg         frame_done
);
    localparam integer LAST_REL = ROI_W - 1;

    reg        pending;
    reg [3:0]  start_delay;
    reg        capture_active;
    reg [9:0]  roi_x_lat;
    reg [8:0]  roi_y_lat;

    reg [15:0] line_mem [0:ROI_W-1];
    reg [7:0]  top_left_r;
    reg [7:0]  top_left_g;
    reg [7:0]  top_left_b;
    reg [7:0]  bottom_left_r;
    reg [7:0]  bottom_left_g;
    reg [7:0]  bottom_left_b;

    wire [9:0] rel_x = pixel_x - roi_x_lat;
    wire [8:0] rel_y = pixel_y - roi_y_lat;
    wire       in_roi = (pixel_x >= roi_x_lat) &&
                        (pixel_x < roi_x_lat + ROI_W) &&
                        (pixel_y >= roi_y_lat) &&
                        (pixel_y < roi_y_lat + ROI_W);

    wire [4:0] cur_r5 = pixel_rgb565[15:11];
    wire [5:0] cur_g6 = pixel_rgb565[10:5];
    wire [4:0] cur_b5 = pixel_rgb565[4:0];
    wire [7:0] cur_r  = {cur_r5, cur_r5[4:2]};
    wire [7:0] cur_g  = {cur_g6, cur_g6[5:4]};
    wire [7:0] cur_b  = {cur_b5, cur_b5[4:2]};

    wire [15:0] line_pixel = line_mem[rel_x];
    wire [4:0] line_r5 = line_pixel[15:11];
    wire [5:0] line_g6 = line_pixel[10:5];
    wire [4:0] line_b5 = line_pixel[4:0];
    wire [7:0] line_r  = {line_r5, line_r5[4:2]};
    wire [7:0] line_g  = {line_g6, line_g6[5:4]};
    wire [7:0] line_b  = {line_b5, line_b5[4:2]};

    wire [9:0] sum_r = {2'b00, top_left_r} + {2'b00, line_r} +
                       {2'b00, bottom_left_r} + {2'b00, cur_r};
    wire [9:0] sum_g = {2'b00, top_left_g} + {2'b00, line_g} +
                       {2'b00, bottom_left_g} + {2'b00, cur_g};
    wire [9:0] sum_b = {2'b00, top_left_b} + {2'b00, line_b} +
                       {2'b00, bottom_left_b} + {2'b00, cur_b};

    always @(posedge clk) begin
        if (capture_active && pixel_valid && in_roi && !rel_y[0])
            line_mem[rel_x] <= pixel_rgb565;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending        <= 1'b0;
            start_delay    <= 4'd0;
            capture_active <= 1'b0;
            roi_x_lat      <= 10'd236;
            roi_y_lat      <= 9'd136;
            top_left_r     <= 8'd0;
            top_left_g     <= 8'd0;
            top_left_b     <= 8'd0;
            bottom_left_r  <= 8'd0;
            bottom_left_g  <= 8'd0;
            bottom_left_b  <= 8'd0;
            out_we         <= 1'b0;
            out_addr       <= 12'd0;
            out_data       <= 24'd0;
            frame_done     <= 1'b0;
        end else begin
            out_we     <= 1'b0;
            frame_done <= 1'b0;

            if (frame_sync) begin
                pending        <= enable;
                start_delay    <= 4'd0;
                capture_active <= 1'b0;
            end else if (pending) begin
                if (start_delay == START_DELAY - 1) begin
                    pending        <= 1'b0;
                    capture_active <= enable;
                    roi_x_lat      <= roi_x;
                    roi_y_lat      <= roi_y;
                end else begin
                    start_delay <= start_delay + 1'b1;
                end
            end else if (capture_active && !enable) begin

                capture_active <= 1'b0;
            end

            if (capture_active && pixel_valid && in_roi) begin
                if (rel_y[0]) begin
                    if (!rel_x[0]) begin

                        top_left_r    <= line_r;
                        top_left_g    <= line_g;
                        top_left_b    <= line_b;
                        bottom_left_r <= cur_r;
                        bottom_left_g <= cur_g;
                        bottom_left_b <= cur_b;
                    end else begin

                        out_we   <= 1'b1;
                        out_addr <= {rel_y[6:1], rel_x[6:1]};
                        out_data <= {sum_r[9:2], sum_g[9:2], sum_b[9:2]};
                        if ((rel_x == LAST_REL) && (rel_y == LAST_REL)) begin
                            capture_active <= 1'b0;
                            frame_done     <= 1'b1;
                        end
                    end
                end
            end
        end
    end
endmodule
