module ov5640_capture #(
    // 有效帧总尺寸(这里摄像头配成 640x480)
    parameter integer PIX_W = 640,
    parameter integer PIX_H = 480,
    // 需要缓存到 BRAM 的中央窗口，默认 600x400
    parameter integer CAP_X0 = 20,   // 窗口左边界 x (落在 PIX_W 内)
    parameter integer CAP_Y0 = 40,   // 窗口上边界 y (落在 PIX_H 内)
    parameter integer CAP_W  = 600,
    parameter integer CAP_H  = 400
)(
    input  wire        sys_rst_n,        // 复位，低有效
    input  wire        cfg_done,         // OV5640 初始化完成，之后才采集

    input  wire        cam_pclk,         // 摄像头像素时钟
    input  wire        cam_vsync,        // 场同步
    input  wire        cam_href,         // 行有效
    input  wire [7:0]  cam_data,         // 摄像头数据

    output reg         cmos_frame_vsync, // 帧同步(打拍对齐)
    output reg         cmos_frame_href,  // 行有效(打拍对齐)
    output reg         cmos_frame_valid, // 写使能(在 600x400 窗口内为高)
    output reg  [15:0] cmos_frame_data   // RGB565 像素
);

    localparam integer XMAX = CAP_X0 + CAP_W - 1;  // 默认 619
    localparam integer YMAX = CAP_Y0 + CAP_H - 1;  // 默认 439

    reg        cam_vsync_d0, cam_vsync_d1;
    reg        cam_href_d0,  cam_href_d1;
    reg        byte_flag;        // 0=第一字节 1=第二字节
    reg [7:0]  data_high;        // 第一字节暂存

    reg [9:0]  x_cnt;            // 行内已拼像素计数(从 href 高算起)
    reg [9:0]  y_cnt;            // 已走过数据行数(从 vsync 后算起)

    // 帧起始沿。OV5640 DVP 默认 VSYNC 每帧一个脉冲(高有效)。
    // 若你的摄像头极性相反，把这里改成 ~cam_vsync_d0 & cam_vsync_d1 即可。
    wire vsync_pos = cam_vsync_d0 & (~cam_vsync_d1);
    wire href_neg  = (~cam_href_d0) & cam_href_d1;

    // ---- 输入打拍，用于找沿 ----
    always @(posedge cam_pclk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            cam_vsync_d0 <= 1'b0;  cam_vsync_d1 <= 1'b0;
            cam_href_d0  <= 1'b0;  cam_href_d1  <= 1'b0;
        end else begin
            cam_vsync_d0 <= cam_vsync; cam_vsync_d1 <= cam_vsync_d0;
            cam_href_d0  <= cam_href;  cam_href_d1  <= cam_href_d0;
        end
    end

    // ---- 行/场计数 ----
    always @(posedge cam_pclk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            x_cnt     <= 10'd0;
            y_cnt     <= 10'd0;
            byte_flag <= 1'b0;
        end
        else if(vsync_pos) begin        // 新帧，全部清零
            x_cnt     <= 10'd0;
            y_cnt     <= 10'd0;
            byte_flag <= 1'b0;
        end
        else if(cam_href_d0) begin      // 行有效期间，两拍拼一像素
            byte_flag <= ~byte_flag;
            if(byte_flag)
                x_cnt <= x_cnt + 1'b1;  // 每完成一个像素 x+1
        end
        else if(href_neg) begin         // 行结束
            x_cnt     <= 10'd0;
            y_cnt     <= y_cnt + 1'b1;  // 行数+1
            byte_flag <= 1'b0;
        end
    end

    // ---- 拼像素 + 窗口裁剪 ----
    // 字节序：第二字节放高位。OV7725 上曾验证需 {cam_data, data_high}；
    // 若 OV5640 显示出来 R/B 或左右反，可在此处反转拼序或用镜像寄存器。
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

    // ---- 打拍对齐输出 ----
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