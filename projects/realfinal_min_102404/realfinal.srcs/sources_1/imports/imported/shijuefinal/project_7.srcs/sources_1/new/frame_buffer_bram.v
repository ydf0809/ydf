`timescale 1ns / 1ps

module frame_buffer_bram(
    input  wire        clka,    // 写时钟 (连接OV7670的 PCLK)
    input  wire        wea,     // 写使能
    input  wire [17:0] addra,   // 写地址 (0 ~ 153599)
    input  wire [15:0] dina,    // 写入的16位RGB565像素
    
    input  wire        clkb,    // 读时钟 (连接系统时钟 33.333MHz)
    input  wire [17:0] addrb,   // 读地址 (0 ~ 153599)
    output reg  [15:0] doutb    // 读出的数据给LCD
);

    // 声明长条形 RAM: 容量翻倍，支持双缓冲 320x400
    // 地址划分：第一块(Frame 0) 0 ~ 127999；第二块(Frame 1) 131072 ~ 259071
    (* ram_style = "block" *) reg [15:0] ram [0:262143]; 
    
    always @(posedge clka) begin
        if (wea) begin
            ram[addra] <= dina;
        end
    end
    
    always @(posedge clkb) begin
        doutb <= ram[addrb];
    end

endmodule
