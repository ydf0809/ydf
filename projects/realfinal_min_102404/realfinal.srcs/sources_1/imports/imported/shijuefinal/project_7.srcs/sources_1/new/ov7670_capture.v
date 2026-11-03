`timescale 1ns / 1ps

module ov7670_capture(
    input  wire        pclk,    // 像素时钟
    input  wire        vsync,   // 场同步
    input  wire        href,    // 行同步
    input  wire [7:0]  din,     // 8位摄像头数据线
    
    output reg         we,      // 写使能
    output reg  [17:0] waddr,   // 写地址 (0~262143 支持双帧)
    output reg  [15:0] dout,    // RGB像素输出
    input  wire        lcd_rd_page,  // 监听屏幕当前正在锁死读哪一页
    output reg         cam_latest_page, // 输出我刚刚写完的是哪一页
    
    // 给颜色追踪器旁路输出的实时监控流
    output reg         track_valid, 
    output wire [15:0] track_data,
    output wire        track_vsync
);

    reg [15:0] x_cnt;
    reg [15:0] y_cnt;
    reg        byte_flag; 
    reg [7:0]  temp_high;
    reg        wr_page;
    reg        drop_frame; // 乒乓抗撞车丢帧标志
    
    assign track_data = {temp_high, din_real};
    assign track_vsync = vsync_r;
    
    // 同步LCD传来的正读页锁定信号
    reg rd_page_r1, rd_page_r2;
    always @(posedge pclk) begin
        rd_page_r1 <= lcd_rd_page;
        rd_page_r2 <= rd_page_r1;
    end
    
    reg vsync_r;
    reg href_r, href_r2;
    always @(posedge pclk) begin
        vsync_r <= vsync;
        href_r  <= href;       
        href_r2 <= href_r;
    end
    
    wire [7:0] din_real = din; 

    always @(posedge pclk) begin
        // 捕获场同步的下降沿，代表一帧新数据来了！
        if (vsync_r == 1'b1 && vsync == 1'b0) begin
            // 只有上一个帧没有被撞车丢弃时，当前停留的 wr_page 才是一幅完美画作！
            if (drop_frame == 1'b0) begin
                cam_latest_page <= wr_page; // 强势宣布：本页已完全写好、随时可以取用
            end
            
            // 【乒乓防碰车守护】：如果我们要写的下一页，正是LCD在读的页，说明画面正在被拿走！本帧罢工作废
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
                    track_valid <= 1'b0; // 必须在接收高字节的这一拍将追踪信号拉低，否则每个像素会被算成两拍！
                end else begin
                    dout      <= {temp_high, din_real}; 
                    byte_flag <= 1'b0;
                    
                    // 只截取中心 300x400
                    if (x_cnt >= 170 && x_cnt < 470 && y_cnt >= 40 && y_cnt < 440) begin
                        track_valid <= 1'b1; // 给追踪引擎全覆盖！
                        if (drop_frame == 1'b0) begin
                            we    <= 1'b1;
                            if (wr_page == 1'b0) begin
                                waddr <= (y_cnt - 40) * 300 + (x_cnt - 170); // 0 ~ 119999
                            end else begin
                                waddr <= 18'd120000 + (y_cnt - 40) * 300 + (x_cnt - 170); // 120000 ~ 239999，刚好跑满240000深度！
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