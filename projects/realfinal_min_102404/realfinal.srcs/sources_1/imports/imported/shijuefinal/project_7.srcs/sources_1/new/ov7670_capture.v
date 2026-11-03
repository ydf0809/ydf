// Assemble RGB565 byte pairs and maintain camera frame/page addresses.
`timescale 1ns / 1ps

module ov7670_capture(
    input  wire        pclk,
    input  wire        vsync,
    input  wire        href,
    input  wire [7:0]  din,

    output reg         we,
    output reg  [17:0] waddr,
    output reg  [15:0] dout,
    input  wire        lcd_rd_page,
    output reg         cam_latest_page,

    output reg         track_valid,
    output wire [15:0] track_data,
    output wire        track_vsync
);

    reg [15:0] x_cnt;
    reg [15:0] y_cnt;
    reg        byte_flag;
    reg [7:0]  temp_high;
    reg        wr_page;
    reg        drop_frame;


    reg rd_page_r1, rd_page_r2;
    always @(posedge pclk) begin
        rd_page_r1 <= lcd_rd_page;
        rd_page_r2 <= rd_page_r1;
    end

    reg vsync_r;
    reg href_r, href_r2;
    reg [7:0] din_r;
    always @(posedge pclk) begin
        din_r <= din;
        vsync_r <= vsync;
        href_r  <= href;
        href_r2 <= href_r;
    end

    wire [7:0] din_real = din_r;
    assign track_data = dout;
    assign track_vsync = vsync_r;

    initial begin
        x_cnt=0;y_cnt=0;byte_flag=0;temp_high=0;wr_page=0;drop_frame=0;
        cam_latest_page=0;rd_page_r1=0;rd_page_r2=0;vsync_r=0;
        href_r=0;href_r2=0;din_r=0;we=0;waddr=0;dout=0;track_valid=0;
    end

    always @(posedge pclk) begin
        track_valid <= 1'b0;

        if (vsync_r == 1'b1 && vsync == 1'b0) begin

            if (drop_frame == 1'b0) begin
                cam_latest_page <= wr_page;
            end

            if (rd_page_r2 == ~wr_page) begin
                drop_frame <= 1'b1;
            end else begin
                drop_frame <= 1'b0;
                wr_page <= ~wr_page;
            end
        end

        if (vsync_r == 1'b1) begin
            x_cnt     <= 16'd0;
            y_cnt     <= 16'd0;
            byte_flag <= 1'b0;
            we        <= 1'b0;
        end else begin
            if (href_r2 == 1'b1 && href_r == 1'b0) begin
                y_cnt     <= y_cnt + 1'b1;
                x_cnt     <= 16'd0;
                byte_flag <= 1'b0;
                we        <= 1'b0;
            end
            else if (href_r == 1'b1) begin
                if (byte_flag == 1'b0) begin
                    temp_high <= din_real;
                    byte_flag <= 1'b1;
                    we        <= 1'b0;
                    track_valid <= 1'b0;
                end else begin
                    dout      <= {temp_high, din_real};
                    byte_flag <= 1'b0;

                    if (x_cnt >= 170 && x_cnt < 470 && y_cnt >= 40 && y_cnt < 440) begin
                        track_valid <= 1'b1;
                        if (drop_frame == 1'b0) begin
                            we    <= 1'b1;
                            if (wr_page == 1'b0) begin
                                waddr <= (y_cnt - 40) * 300 + (x_cnt - 170);
                            end else begin
                                waddr <= 18'd120000 + (y_cnt - 40) * 300 + (x_cnt - 170);
                            end
                        end else begin
                            we    <= 1'b0;
                        end
                    end else begin
                        track_valid <= 1'b0;
                        we    <= 1'b0;
                    end

                    x_cnt <= x_cnt + 1'b1;
                end
            end else begin
                we <= 1'b0;
            end
        end
    end
endmodule
