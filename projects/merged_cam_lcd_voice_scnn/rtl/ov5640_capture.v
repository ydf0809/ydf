// Capture RGB565 byte pairs in the camera pixel-clock domain.
module ov5640_capture #(

    parameter integer PIX_W = 640,
    parameter integer PIX_H = 480,

    parameter integer CAP_X0 = 20,
    parameter integer CAP_Y0 = 40,
    parameter integer CAP_W  = 600,
    parameter integer CAP_H  = 400
)(
    input  wire        sys_rst_n,
    input  wire        cfg_done,

    input  wire        cam_pclk,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_data,

    output reg         cmos_frame_vsync,
    output reg         cmos_frame_href,
    output reg         cmos_frame_valid,
    output reg  [15:0] cmos_frame_data
);

    localparam integer XMAX = CAP_X0 + CAP_W - 1;
    localparam integer YMAX = CAP_Y0 + CAP_H - 1;

    reg        cam_vsync_d0, cam_vsync_d1;
    reg        cam_href_d0,  cam_href_d1;
    reg        byte_flag;
    reg [7:0]  data_high;

    reg [9:0]  x_cnt;
    reg [9:0]  y_cnt;

    wire vsync_pos = cam_vsync_d0 & (~cam_vsync_d1);
    wire href_neg  = (~cam_href_d0) & cam_href_d1;

    always @(posedge cam_pclk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            cam_vsync_d0 <= 1'b0;  cam_vsync_d1 <= 1'b0;
            cam_href_d0  <= 1'b0;  cam_href_d1  <= 1'b0;
        end else begin
            cam_vsync_d0 <= cam_vsync; cam_vsync_d1 <= cam_vsync_d0;
            cam_href_d0  <= cam_href;  cam_href_d1  <= cam_href_d0;
        end
    end

    always @(posedge cam_pclk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            x_cnt     <= 10'd0;
            y_cnt     <= 10'd0;
            byte_flag <= 1'b0;
        end
        else if(vsync_pos) begin
            x_cnt     <= 10'd0;
            y_cnt     <= 10'd0;
            byte_flag <= 1'b0;
        end
        else if(cam_href_d0) begin
            byte_flag <= ~byte_flag;
            if(byte_flag)
                x_cnt <= x_cnt + 1'b1;
        end
        else if(href_neg) begin
            x_cnt     <= 10'd0;
            y_cnt     <= y_cnt + 1'b1;
            byte_flag <= 1'b0;
        end
    end

    always @(posedge cam_pclk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            data_high        <= 8'd0;
            cmos_frame_data  <= 16'd0;
            cmos_frame_valid <= 1'b0;
        end
        else if(cfg_done && cam_href_d0) begin
            if(!byte_flag) begin
                data_high        <= cam_data;
                cmos_frame_valid <= 1'b0;
            end else begin
                cmos_frame_data <= {cam_data, data_high};
                if(x_cnt >= CAP_X0 && x_cnt <= XMAX &&
                   y_cnt >= CAP_Y0 && y_cnt <= YMAX)
                    cmos_frame_valid <= 1'b1;
                else
                    cmos_frame_valid <= 1'b0;
            end
        end else begin
            cmos_frame_valid <= 1'b0;
        end
    end

    always @(posedge cam_pclk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            cmos_frame_vsync <= 1'b0;
            cmos_frame_href  <= 1'b0;
        end else begin
            cmos_frame_vsync <= cam_vsync_d0;
            cmos_frame_href  <= cam_href_d0;
        end
    end

endmodule
