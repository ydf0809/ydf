`timescale 1ns / 1ps

module spi_master(
    input  wire       clk,        // 系统时钟（推荐使用后续MMCM生成的 50MHz）
    input  wire       rst_n,      // 异步复位，低电平有效
    
    // 用户逻辑接口
    input  wire       req,        // 发送请求信号 (拉高1个时钟周期触发一次发送)
    input  wire [7:0] data_in,    // 待发送的 8-bit 数据
    input  wire       dc_in,      // 数据/命令标志: 0=命令(Command), 1=数据(Data)
    output reg        busy,       // 忙等待标志: 1=正在发送,此时不能发新数据
    
    // SPI 物理接口 (接ILI9488)
    output reg        spi_cs,     // 片选信号 (低有效)
    output reg        spi_scl,    // SPI时钟
    output reg        spi_sda,    // SPI MOSI 数据线
    output reg        spi_dc      // 数据/命令控制线
);

    reg [3:0] bit_cnt;   // 位计数器，发送8位数据需要计数
    reg [7:0] shift_reg; // 移位寄存器
    reg [2:0] state;     // 状态机
    
    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam SHIFT = 3'd2;
    localparam END_P = 3'd3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_cs  <= 1'b1;
            spi_scl <= 1'b0; // ILI9488 SPI Mode 0 (CPOL=0)
            spi_sda <= 1'b0;
            spi_dc  <= 1'b1;
            busy    <= 1'b0;
            bit_cnt <= 4'd0;
            state   <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    spi_scl <= 1'b0;
                    spi_cs  <= 1'b1;
                    if (req) begin
                        shift_reg <= data_in;
                        spi_dc    <= dc_in;
                        busy      <= 1'b1;
                        spi_cs    <= 1'b0;  // 拉低片选，准备发送
                        state     <= START;
                    end else begin
                        busy <= 1'b0;
                    end
                end
                
                START: begin
                    // SCL 低电平时准备好数据 (MSB first)
                    spi_sda <= shift_reg[7];
                    shift_reg <= {shift_reg[6:0], 1'b0}; // 左移
                    spi_scl <= 1'b0;
                    bit_cnt <= 4'd0;
                    state   <= SHIFT;
                end
                
                SHIFT: begin
                    if (spi_scl == 1'b0) begin
                        spi_scl <= 1'b1; // 上升沿，屏幕从SDA读取数据
                    end else begin
                        spi_scl <= 1'b0; // 下降沿，我们准备下一位数据
                        bit_cnt <= bit_cnt + 1'b1;
                        if (bit_cnt == 4'd7) begin // 8位全部发送完毕
                            state <= END_P;
                        end else begin
                            spi_sda <= shift_reg[7];
                            shift_reg <= {shift_reg[6:0], 1'b0};
                        end
                    end
                end
                
                END_P: begin
                    spi_cs <= 1'b1; // 拉高片选，结束发送
                    busy   <= 1'b0;
                    state  <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule