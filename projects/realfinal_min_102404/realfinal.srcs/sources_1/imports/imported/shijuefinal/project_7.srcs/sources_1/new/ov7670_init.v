`timescale 1ns / 1ps

module ov7670_init(
    input  wire clk,         // 75MHz 时钟
    input  wire rst_n,       // 复位信号
    
    output wire sio_c,
    inout  wire sio_d,
    output reg  init_done
);

    wire i2c_busy;
    reg  i2c_req;
    reg  [7:0] reg_addr;
    reg  [7:0] reg_data;
    
    reg [15:0] rom [0:78];
    initial begin
        // --- 核心系统设置 (不修改任何窗口边界寄存器！保持绝对的 640x480 VGA) ---
        rom[0]  = {8'h12, 8'h80}; // 软复位
        rom[1]  = {8'hFF, 8'hFF}; // 软件延时
        rom[2]  = {8'h12, 8'h04}; // COM7: VGA(640x480) 原分辨率，并且是RGB出图
        rom[3]  = {8'h11, 8'h00}; // CLKRC: 时钟绝不分频 (默认)
        rom[4]  = {8'h3E, 8'h00}; // COM14: 不人为缩放
        rom[5]  = {8'h0C, 8'h00}; // COM3: 默认
        rom[6]  = {8'h8C, 8'h00}; // RGB444: 关，不用它
        rom[7]  = {8'h40, 8'hD0}; // COM15: RGB565，满量程(00-FF) 【极其重要】
        rom[8]  = {8'h1E, 8'h30}; // MVFP: 图像镜像/上下翻转 (通常有需要)
        
        // --- 颜色通道、增强矩阵 (解决灰绿屏色调问题，恢复正常鲜艳色彩) ---
        rom[9]  = {8'h3D, 8'h80}; // COM13: 必须恢复为 0xC0！开启自动 U/V 饱和度与 Gamma！
        rom[10] = {8'h4F, 8'h80}; // MTX1 (官方经典 RGB565 色彩增强矩阵)
        rom[11] = {8'h50, 8'h80}; // MTX2
        rom[12] = {8'h51, 8'h00}; // MTX3
        rom[13] = {8'h52, 8'h22}; // MTX4
        rom[14] = {8'h53, 8'h5E}; // MTX5
        rom[15] = {8'h54, 8'h80}; // MTX6
        rom[16] = {8'h58, 8'h9E}; // MTXS
        rom[17] = {8'hB0, 8'h84}; // 色彩工作模式配置
        
        // --- 自动曝光(AEC)、自动白平衡(AWB)与增益(AGC) (没有这些就是黑屏或暗影) ---
        rom[18] = {8'h13, 8'hE7}; // COM8: 全开 AGC, AWB, AEC, 以及极其关键的【开启工频条纹抑制 0x20】
        rom[19] = {8'h14, 8'h18}; // COM9: AGC增益天花板限制在4x(原16x)，彻底消除暗光下的严重绿色噪点！
        rom[20] = {8'h00, 8'h00}; // AGC 增益低位
        rom[21] = {8'h04, 8'h00}; // AEC 自动曝光低位
        rom[22] = {8'h10, 8'h00}; // AECH
        
        rom[23] = {8'h3B, 8'h0A}; // COM11: 关闭Night Mode(防止帧率突降导致水波纹)，但保留50Hz抗闪烁
        rom[24] = {8'h9D, 8'h4C}; // BD50ST: 50Hz 工频抑制带数值
        rom[25] = {8'h9E, 8'h3F}; // BD60ST: 60Hz 备用参数
        
        rom[26] = {8'h0E, 8'h61}; // COM5 
        rom[27] = {8'h0F, 8'h4B}; // COM6
        rom[28] = {8'h16, 8'h02};
        rom[29] = {8'h21, 8'h02};
        rom[30] = {8'h22, 8'h91};
        rom[31] = {8'h29, 8'h07};
        rom[32] = {8'h33, 8'h0B};
        rom[33] = {8'h35, 8'h0B};
        rom[34] = {8'h37, 8'h1D};
        rom[35] = {8'h38, 8'h71};
        rom[36] = {8'h39, 8'h2A};
        rom[37] = {8'h3C, 8'h78}; // COM12
        rom[38] = {8'h4D, 8'h40};
        rom[39] = {8'h4E, 8'h20};
        rom[40] = {8'h69, 8'h00}; // GFIX
        
        // --- 镜头边缘亮度补偿 ---
        rom[41] = {8'h70, 8'h3A}; 
        rom[42] = {8'h71, 8'h35}; 
        rom[43] = {8'h72, 8'h11}; 
        rom[44] = {8'h73, 8'hF0}; 
        
        // --- 时钟像素边缘与消条纹 (非常重要：抹平和对齐PCLK，抗屏幕抖动条纹) ---
        rom[45] = {8'hA2, 8'h02}; 
        rom[46] = {8'h6B, 8'h4A};
        rom[47] = {8'h74, 8'h10};
        rom[48] = {8'h8D, 8'h4F};
        rom[49] = {8'h8E, 8'h00};
        rom[50] = {8'h8F, 8'h00};
        rom[51] = {8'h90, 8'h00};
        rom[52] = {8'h91, 8'h00};
        rom[53] = {8'h96, 8'h00};
        rom[54] = {8'h9A, 8'h00};
        rom[55] = {8'hB1, 8'h0C};
        rom[56] = {8'hB2, 8'h0E}; 
        rom[57] = {8'hB3, 8'h82};
        rom[58] = {8'hB8, 8'h0A};
        
        // --- Gamma 伽马曲线 ---
        rom[59] = {8'h7A, 8'h20};
        rom[60] = {8'h7B, 8'h10}; 
        rom[61] = {8'h7C, 8'h1E}; 
        rom[62] = {8'h7D, 8'h35}; 
        rom[63] = {8'h7E, 8'h5A}; 
        rom[64] = {8'h7F, 8'h69}; 
        rom[65] = {8'h80, 8'h76}; 
        rom[66] = {8'h81, 8'h80}; 
        rom[67] = {8'h82, 8'h88}; 
        rom[68] = {8'h83, 8'h8F};
        rom[69] = {8'h84, 8'h96}; 
        rom[70] = {8'h85, 8'hA3}; 
        rom[71] = {8'h86, 8'hAF}; 
        rom[72] = {8'h87, 8'hC4}; 
        rom[73] = {8'h88, 8'hD7}; 
        rom[74] = {8'h89, 8'hE8};
        
        rom[75] = {8'h15, 8'h00}; // COM10: 恢复默认，防止HREF变质
        rom[76] = {8'h42, 8'h00}; // COM17: 绝不开启彩条，只取真像素！
        
        // --- 预留槽位 ---
        rom[77] = {8'hFF, 8'hFF};
        rom[78] = {8'hFE, 8'hFE}; // 结束标志
    end

    reg [6:0] idx; // 调整位宽以容纳大于64的状态
    reg [23:0] delay_cnt;
    
    sccb_master u_sccb(
        .clk      (clk),
        .rst_n    (rst_n),
        .req      (i2c_req),
        .dev_addr (8'h42), // 摄像头 I2C 写入地址
        .reg_addr (reg_addr),
        .reg_data (reg_data),
        .busy     (i2c_busy),
        .sio_c    (sio_c),
        .sio_d    (sio_d)
    );

    // 状态机
    reg [2:0] state;
    localparam S_PWR_UP_DELAY = 3'd0; // 新增：上电物理延时
    localparam S_IDLE         = 3'd1;
    localparam S_DELAY        = 3'd2;
    localparam S_I2C_REQ      = 3'd3;
    localparam S_I2C_WAIT     = 3'd4;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            idx       <= 5'd0;
            i2c_req   <= 1'b0;
            delay_cnt <= 24'd0;
            init_done <= 1'b0;
            state     <= S_PWR_UP_DELAY; // 从上电延时开始
        end else begin
            case(state)
                S_PWR_UP_DELAY: begin 
                    // 等待大约 20ms 让摄像头电源和锁相环彻底稳固
                    if (delay_cnt < 24'd1_500_000) begin
                        delay_cnt <= delay_cnt + 1'b1;
                    end else begin
                        delay_cnt <= 24'd0;
                        state     <= S_IDLE;
                    end
                end
                
                S_IDLE: begin
                    if (!init_done && !i2c_busy && !i2c_req) begin
                         if (rom[idx] == 16'hFFFF) begin 
                             state <= S_DELAY;
                         end else if (rom[idx] == 16'hFEFE) begin 
                             init_done <= 1'b1;
                         end else begin
                             reg_addr <= rom[idx][15:8];
                             reg_data <= rom[idx][7:0];
                             state    <= S_I2C_REQ; 
                         end
                    end
                end
                
                S_DELAY: begin 
                    if (delay_cnt < 24'd2_000_000) begin
                        delay_cnt <= delay_cnt + 1'b1;
                    end else begin
                        delay_cnt <= 24'd0;
                        idx       <= idx + 1'b1;
                        state     <= S_IDLE;
                    end
                end
                
                S_I2C_REQ: begin 
                    i2c_req <= 1'b1;
                    if (i2c_req && i2c_busy) begin 
                        i2c_req <= 1'b0;
                        state   <= S_I2C_WAIT;
                    end
                end
                
                S_I2C_WAIT: begin 
                    if (!i2c_busy) begin 
                        idx   <= idx + 1'b1; 
                        state <= S_IDLE;
                    end
                end
                
                default: state <= S_PWR_UP_DELAY;
            endcase
        end
    end
endmodule