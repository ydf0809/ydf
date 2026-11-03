`timescale 1ns / 1ps

module atk4384_driver(
    input  wire        clk,        
    input  wire        rst_n,      
    
    input  wire        cam_latest_page,
    output reg         lcd_rd_page,
    
    input  wire [10:0] box_x,
    input  wire [10:0] box_y,
    input  wire [10:0] box_w,      
    input  wire [10:0] box_h,

    output reg  [17:0] ram_addr,   
    input  wire [15:0] ram_data,   
    
    output wire        lcd_cs,
    output wire        lcd_scl,
    output wire        lcd_sda,
    output wire        lcd_dc,
    output reg         lcd_res     
);

    reg        spi_req;
    reg  [7:0] spi_data;
    reg        spi_dc;
    wire       spi_busy;
    
    reg [4:0]  init_idx;
    reg [8:0]  init_rom [0:15]; 
    
    initial begin
        init_rom[0]  = 9'h0_11; // Sleep Out
        init_rom[1]  = 9'h0_36; // Memory Access Control
        init_rom[2]  = 9'h1_48; // Portrait (MX=0, MY=1, MV=0, BGR=1)
        init_rom[3]  = 9'h0_3A; // Interface Pixel Format
        init_rom[4]  = 9'h1_66; // 18 bit/pixel (RGB666) -> SPI 强制要求 3 Bytes/pixel
        init_rom[5]  = 9'h0_29; // Display ON
        init_rom[6]  = 9'h1_FF; // 结束标志
    end

    reg [3:0] state;
    localparam S_HW_RST      = 4'd0;
    localparam S_HW_DELAY    = 4'd1;
    localparam S_INIT        = 4'd2;
    localparam S_WAIT_VSYNC  = 4'd3; 
    localparam S_SET_ADDR    = 4'd4;
    localparam S_WRITE_PIXEL = 4'd5;
    localparam S_WAIT_SPI    = 4'd6;
    
    reg [23:0] delay_cnt;
    localparam DELAY_120MS = 24'd9_000_000; 
    
    reg [3:0]  next_state;
    reg [15:0] x_cnt;
    reg [15:0] y_cnt;
    reg [1:0]  rgb_byte_cnt;
    reg        read_wait; 
    
    reg        ack_synced_1, ack_synced_2;
    always @(posedge clk) begin
        ack_synced_1 <= cam_latest_page;
        ack_synced_2 <= ack_synced_1;
    end
    
    reg [10:0] box_x_r1, box_x_r2, locked_box_x;
    reg [10:0] box_y_r1, box_y_r2, locked_box_y;
    reg [10:0] box_w_r1, box_w_r2, locked_box_w;
    reg [10:0] box_h_r1, box_h_r2, locked_box_h;
    
    always @(posedge clk) begin
        box_x_r1 <= box_x; box_x_r2 <= box_x_r1;
        box_y_r1 <= box_y; box_y_r2 <= box_y_r1;
        box_w_r1 <= box_w; box_w_r2 <= box_w_r1;
        box_h_r1 <= box_h; box_h_r2 <= box_h_r1;
    end

    spi_master u_spi (
        .clk     (clk),
        .rst_n   (rst_n),
        .req     (spi_req),
        .data_in (spi_data),
        .dc_in   (spi_dc),
        .busy    (spi_busy),
        .spi_cs  (lcd_cs),
        .spi_scl (lcd_scl),
        .spi_sda (lcd_sda),
        .spi_dc  (lcd_dc)
    );

    // =========================================================
    // 修复：将绘图连线判定移动到 always 块外部运算
    // =========================================================
    wire [10:0] half_w = locked_box_w >> 1;
    wire [10:0] half_h = locked_box_h >> 1;
    wire [10:0] bleft  = (locked_box_x > half_w) ? locked_box_x - half_w : 0;
    wire [10:0] bright = locked_box_x + half_w;
    wire [10:0] btop   = (locked_box_y > half_h) ? locked_box_y - half_h : 0;
    wire [10:0] bbot   = locked_box_y + half_h;
    
    wire is_h_line = (x_cnt >= bleft + 10 && x_cnt <= bright + 10) && 
                     ((y_cnt - 40) == btop || (y_cnt - 40) == btop+1 || (y_cnt - 40) == bbot || (y_cnt - 40) == bbot-1);
    wire is_v_line = ((y_cnt - 40) >= btop && (y_cnt - 40) <= bbot) && 
                     (x_cnt == bleft + 10 || x_cnt == bleft + 11 || x_cnt == bright + 10 || x_cnt == bright + 9);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_HW_RST;
            lcd_res      <= 1'b0; 
            delay_cnt    <= 24'd0;
            init_idx     <= 5'd0;
            spi_req      <= 1'b0;
            x_cnt        <= 16'd0;
            y_cnt        <= 16'd0;
            rgb_byte_cnt <= 2'd0;
            ram_addr     <= 18'd0;
            read_wait    <= 1'b0;
            lcd_rd_page  <= 1'b0;
        end else begin
            case (state)
                S_HW_RST: begin 
                    if (delay_cnt < 24'd750_000) begin 
                        delay_cnt <= delay_cnt + 1'b1;
                        lcd_res   <= 1'b0;
                    end else begin
                        delay_cnt <= 24'd0;
                        lcd_res   <= 1'b1;         
                        state     <= S_HW_DELAY;
                    end
                end
                
                S_HW_DELAY: begin 
                    if (delay_cnt < DELAY_120MS) begin
                        delay_cnt <= delay_cnt + 1'b1;
                    end else begin
                        delay_cnt <= 24'd0;
                        state     <= S_INIT;
                    end
                end
                
                S_INIT: begin 
                    if (!spi_busy && !spi_req) begin
                        if (init_rom[init_idx] == 9'h1_FF) begin
                            if (delay_cnt < DELAY_120MS) begin
                                delay_cnt <= delay_cnt + 1'b1;
                            end else begin
                                delay_cnt <= 24'd0;
                                state <= S_WAIT_VSYNC;
                                init_idx <= 5'd0;
                            end
                        end else begin
                            spi_dc   <= init_rom[init_idx][8];
                            spi_data <= init_rom[init_idx][7:0];
                            spi_req  <= 1'b1;
                            next_state <= S_INIT;
                            state <= S_WAIT_SPI;
                        end
                    end
                end
                
                S_WAIT_VSYNC: begin
                    x_cnt <= 16'd0;
                    y_cnt <= 16'd0;
                    lcd_rd_page <= ack_synced_2; 
                    locked_box_x <= box_x_r2;    
                    locked_box_y <= box_y_r2;
                    locked_box_w <= box_w_r2;
                    locked_box_h <= box_h_r2;
                    state <= S_SET_ADDR; 
                end
                
                S_SET_ADDR: begin 
                    if (!spi_busy && !spi_req) begin
                         if (init_idx == 0)      {spi_dc, spi_data} <= {1'b0, 8'h2A}; 
                         else if (init_idx == 1) {spi_dc, spi_data} <= {1'b1, 8'h00}; 
                         else if (init_idx == 2) {spi_dc, spi_data} <= {1'b1, 8'h00}; 
                         else if (init_idx == 3) {spi_dc, spi_data} <= {1'b1, 8'h01}; 
                         else if (init_idx == 4) {spi_dc, spi_data} <= {1'b1, 8'h3F}; 
                         else if (init_idx == 5) {spi_dc, spi_data} <= {1'b0, 8'h2B}; 
                         else if (init_idx == 6) {spi_dc, spi_data} <= {1'b1, 8'h00}; 
                         else if (init_idx == 7) {spi_dc, spi_data} <= {1'b1, 8'h00}; 
                         else if (init_idx == 8) {spi_dc, spi_data} <= {1'b1, 8'h01}; 
                         else if (init_idx == 9) {spi_dc, spi_data} <= {1'b1, 8'hDF}; 
                         else if (init_idx == 10){spi_dc, spi_data} <= {1'b0, 8'h2C}; 
                         
                         spi_req <= 1'b1;
                         next_state <= S_SET_ADDR;
                         state <= S_WAIT_SPI;
                    end
                end
                
                S_WRITE_PIXEL: begin 
                    if (!spi_busy && !spi_req) begin
                        if (y_cnt < 40 || y_cnt >= 440 || x_cnt < 10 || x_cnt >= 310) begin
                            spi_dc  <= 1'b1;
                            if (rgb_byte_cnt == 2'd0)      spi_data <= 8'h00; 
                            else if (rgb_byte_cnt == 2'd1) spi_data <= 8'h00;  
                            else if (rgb_byte_cnt == 2'd2) spi_data <= 8'h00; 
                            
                            spi_req <= 1'b1;
                            next_state <= S_WRITE_PIXEL;
                            state <= S_WAIT_SPI;
                        end else begin
                            if (!read_wait) begin
                                if (lcd_rd_page == 1'b0) begin
                                    ram_addr <= (y_cnt - 40) * 300 + (x_cnt - 10);
                                end else begin
                                    ram_addr <= 18'd120000 + (y_cnt - 40) * 300 + (x_cnt - 10);
                                end
                                read_wait <= 1'b1; 
                            end else begin
                                spi_dc <= 1'b1;
                                
                                // 直接在这里调用外部判断好的是否重合边框的布尔信号
                                if (is_h_line || is_v_line) begin
                                    if (rgb_byte_cnt == 2'd0)      spi_data <= 8'hF8; 
                                    else if (rgb_byte_cnt == 2'd1) spi_data <= 8'h00; 
                                    else if (rgb_byte_cnt == 2'd2) spi_data <= 8'h00; 
                                end else begin
                                    if (rgb_byte_cnt == 2'd0)      spi_data <= {ram_data[15:11], 3'b000}; 
                                    else if (rgb_byte_cnt == 2'd1) spi_data <= {ram_data[10:5],  2'b00};  
                                    else if (rgb_byte_cnt == 2'd2) spi_data <= {ram_data[4:0],   3'b000}; 
                                end
                                
                                spi_req <= 1'b1;
                                next_state <= S_WRITE_PIXEL;
                                state <= S_WAIT_SPI;
                            end
                        end
                    end
                end

                S_WAIT_SPI: begin
                    spi_req <= 1'b0;
                    if (!spi_busy) begin
                        if (next_state == S_INIT) begin
                            init_idx <= init_idx + 1'b1;
                            state <= S_INIT;
                        end
                        else if (next_state == S_SET_ADDR) begin
                            if (init_idx == 10) begin
                                init_idx <= 5'd0;
                                state <= S_WRITE_PIXEL; 
                            end else begin
                                init_idx <= init_idx + 1'b1;
                                state <= S_SET_ADDR;
                            end
                        end
                        else if (next_state == S_WRITE_PIXEL) begin
                            if (rgb_byte_cnt == 2'd2) begin 
                                rgb_byte_cnt <= 2'd0;
                                read_wait    <= 1'b0;   
                                
                                if (x_cnt == 319) begin
                                    x_cnt <= 16'd0;
                                    if (y_cnt == 479) begin
                                        y_cnt <= 16'd0; 
                                        state <= S_WAIT_VSYNC; 
                                    end else begin
                                        y_cnt <= y_cnt + 1'b1;
                                        state <= S_WRITE_PIXEL;
                                    end
                                end else begin
                                    x_cnt <= x_cnt + 1'b1;
                                    state <= S_WRITE_PIXEL;
                                end
                            end else begin
                                rgb_byte_cnt <= rgb_byte_cnt + 1'b1; 
                                state <= S_WRITE_PIXEL;
                            end
                        end
                    end
                end
                
                default: state <= S_HW_RST;
            endcase
        end
    end
endmodule