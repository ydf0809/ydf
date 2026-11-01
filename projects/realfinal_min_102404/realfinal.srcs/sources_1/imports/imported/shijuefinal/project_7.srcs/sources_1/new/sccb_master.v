`timescale 1ns / 1ps

module sccb_master(
    input  wire       clk,        // 系统时钟 50MHz
    input  wire       rst_n,      // 复位
    input  wire       req,        // 发送请求
    input  wire [7:0] dev_addr,   // 设备地址 (0x42)
    input  wire [7:0] reg_addr,   // 寄存器地址
    input  wire [7:0] reg_data,   // 数据
    output reg        busy,       // 忙碌标志
    
    output reg        sio_c,      // SCL (SCCB 时钟)
    inout  wire       sio_d       // SDA (SCCB 数据)
);

    // 产生约 400KHz 的处理节拍 (每2.5us一个节拍)
    // 使得我们要输出的 100KHz I2C 每一个 bit 都可以被完美拆分成 4 步走
    // 完全符合 I2C/SCCB Setup & Hold 建立时间协议
    reg [8:0] clk_cnt; 
    reg       en; 
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            clk_cnt <= 9'd0;
            en <= 1'b0;
        end else if(clk_cnt == 9'd186) begin // 50Mhz下，125个周期就是 2.5us = 400KHz 节拍
            clk_cnt <= 9'd0;
            en <= 1'b1;
        end else begin
            clk_cnt <= clk_cnt + 1'b1;
            en <= 1'b0;
        end
    end

    reg [5:0]  state;
    reg [23:0] shift_reg;
    reg [3:0]  bit_cnt;
    reg [1:0]  byte_cnt;
    
    reg        sda_dir;
    reg        sda_out;
    assign sio_d = sda_dir ? sda_out : 1'bz;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state    <= 6'd0;
            busy     <= 1'b0;
            sio_c    <= 1'b1;
            sda_dir  <= 1'b1;
            sda_out  <= 1'b1;
            shift_reg<= 24'd0;
            bit_cnt  <= 4'd0;
            byte_cnt <= 2'd0;
        end else begin
            if(req && !busy) begin
                busy      <= 1'b1;
                // 拼接要发送的 3 个字节
                shift_reg <= {dev_addr, reg_addr, reg_data};
                state     <= 6'd1; // 从 START 开始
                bit_cnt   <= 4'd0;
                byte_cnt  <= 2'd0;
            end else if(busy && en) begin
                case(state)
                    // ==============================
                    // START 条件产生
                    // ==============================
                    // 1: SCL=1, SDA=1
                    6'd1: begin sio_c <= 1'b1; sda_dir <= 1'b1; sda_out <= 1'b1; state <= 6'd2; end
                    // 2: SCL=1 时 SDA 下降沿 (START!)
                    6'd2: begin sio_c <= 1'b1; sda_dir <= 1'b1; sda_out <= 1'b0; state <= 6'd3; end 
                    // 3: SCL 下降沿，准备进入发送
                    6'd3: begin sio_c <= 1'b0; sda_dir <= 1'b1; sda_out <= 1'b0; state <= 6'd4; end 
                    
                    // ==============================
                    // 单 Byte 数据的 8 个 bit 循环发送
                    // ==============================
                    // 4: SCL仍为0，总线控制端把新数据放到 SDA 上 (建立数据)
                    6'd4: begin 
                        sio_c <= 1'b0; 
                        sda_dir <= 1'b1; 
                        sda_out <= shift_reg[23];  // 每次发最顶上的最高位
                        state <= 6'd5; 
                    end 
                    // 5: 把 SCL 拉高，此时从机（摄像头）会在高电平期间采样读取 SDA
                    6'd5: begin sio_c <= 1'b1; state <= 6'd6; end 
                    // 6: 保持 SCL 为高，稍微等一等，让从机锁死数据
                    6'd6: begin sio_c <= 1'b1; state <= 6'd7; end 
                    // 7: 把 SCL 拉低，此 bit 宣告发送完毕。切换到下个 bit。
                    6'd7: begin 
                        sio_c <= 1'b0; 
                        shift_reg <= {shift_reg[22:0], 1'b0}; // 数据左移更新
                        if (bit_cnt == 4'd7) begin
                            bit_cnt <= 4'd0;
                            state <= 6'd8; // 8位发完，进入 ACK
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                            state <= 6'd4; // 没发完，继续发剩余位
                        end
                    end
                    
                    // ==============================
                    // 等待 ACK (Don't Care 机制兼容 SCCB)
                    // ==============================
                    // 8: SCL为0，总线控制权交给从机 (放开 SDA 设为输入)
                    6'd8: begin 
                        sio_c <= 1'b0; 
                        sda_dir <= 1'b0; // sda_dir为0就是高阻态(输入)，释放总线
                        state <= 6'd9; 
                    end 
                    // 9: SCL 拉高，产生让从机回复的脉冲
                    6'd9: begin sio_c <= 1'b1; state <= 6'd10; end 
                    // 10: SCL 保持高
                    6'd10: begin sio_c <= 1'b1; state <= 6'd11; end 
                    // 11: SCL 恢复为低。判断三个 Byte 我们发到了哪一个？
                    6'd11: begin 
                        sio_c <= 1'b0; 
                        if (byte_cnt == 2'd0) begin       // 第1个字节(设备地址)发完了
                            byte_cnt <= 2'd1; 
                            state <= 6'd4;  // 回去发寄存器地址
                        end else if (byte_cnt == 2'd1) begin // 第2个字节(寄存器地址)发完了
                            byte_cnt <= 2'd2; 
                            state <= 6'd4;  // 回去发寄存器数据
                        end else begin 
                            state <= 6'd12; // 3个全发完，去产生 STOP
                        end
                    end
                    
                    // ==============================
                    // STOP 条件产生
                    // ==============================
                    // 12: SCL为0期间，把 SDA 主动拉低准备发射
                    6'd12: begin sio_c <= 1'b0; sda_dir <= 1'b1; sda_out <= 1'b0; state <= 6'd13; end
                    // 13: 把 SCL 拉高
                    6'd13: begin sio_c <= 1'b1; sda_dir <= 1'b1; sda_out <= 1'b0; state <= 6'd14; end 
                    // 14: SCL=1 高电平期间 SDA 产生上升沿 (STOP!)
                    6'd14: begin sio_c <= 1'b1; sda_dir <= 1'b1; sda_out <= 1'b1; state <= 6'd15; end 
                    // 15: 结束所有动作，退出忙碌态
                    6'd15: begin busy <= 1'b0; state <= 6'd0; end
                    
                    default: state <= 6'd0;
                endcase
            end
        end
    end
endmodule