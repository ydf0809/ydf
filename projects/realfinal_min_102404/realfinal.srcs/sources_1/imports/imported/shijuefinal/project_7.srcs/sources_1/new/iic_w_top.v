module iic_w_top(
    input        sys_clk,
    input        rst_n,
    inout        SDA,
    output       SCL,
    
    // 【新接口】：接收实时的动态转速 (-100 ~ 100 补码)
    input [7:0]  motor1_spd,
    input [7:0]  motor2_spd,
    input [7:0]  motor3_spd,
    input [7:0]  motor4_spd,
    input        cmd_update_req // 发包更新请求冲激
);

    reg en;
    wire oe; 
    wire sda_in;
    reg [3:0]  length_byte;         
    wire [3:0] iic_cycle;      
    wire [6:0] slave_address;
    reg  [3:0] cnt_cycle;  
    
    reg  [7:0] data_one, data_two, data_three, data_four, data_five;
    wire [7:0] data_1_one, data_1_two, data_2_one, data_2_two, data_3_one;  
    wire sda_out;
    
    // 生成触发更新沿
    reg cmd_update_d1, cmd_update_d2;
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_update_d1 <= 1'b0;
            cmd_update_d2 <= 1'b0;
        end else begin
            cmd_update_d1 <= cmd_update_req;
            cmd_update_d2 <= cmd_update_d1;
        end
    end
    wire new_cmd_flag = cmd_update_d1 & ~cmd_update_d2;
    
    assign iic_cycle = 4'd3;
    assign slave_address = 7'b011_0100; // 电机板通信总址 0x34
    
    assign data_1_one = 8'd20;  // 电机类型寄存器
    assign data_1_two = 8'd3;   // 设置为 JGB528
    assign data_2_one = 8'd21;  // 极性寄存器
    assign data_2_two = 8'd0;   
    assign data_3_one = 8'd51;  // 控制转速的起点基寄存器
    
    assign SDA = oe ? sda_out : 1'hz;
    assign sda_in = SDA;
    
    reg iic_busy_reg, iic_finish_reg;
    wire iic_busy, iic_finish;
    wire iic_busy_pos = iic_busy && ~iic_busy_reg; 
    wire iic_finish_pos = iic_finish && ~iic_finish_reg; 

    // An urgent stop may arrive mid-transfer. Finish the current batch first,
    // then send the latest request; never reset its byte/cycle counter mid-packet.
    reg batch_active, pending;
    reg [7:0] batch_m1, batch_m2, batch_m3, batch_m4;
    wire start_batch = ~batch_active && (pending || new_cmd_flag);
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            batch_active <= 1'b0;
            pending <= 1'b0;
            batch_m1 <= 8'd0; batch_m2 <= 8'd0;
            batch_m3 <= 8'd0; batch_m4 <= 8'd0;
        end else begin
            if (new_cmd_flag) pending <= 1'b1;
            if (start_batch) begin
                batch_active <= 1'b1;
                pending <= 1'b0;
                batch_m1 <= motor1_spd; batch_m2 <= motor2_spd;
                batch_m3 <= motor3_spd; batch_m4 <= motor4_spd;
            end else if (iic_finish_pos && cnt_cycle == iic_cycle - 1'b1) begin
                batch_active <= 1'b0;
            end
        end
    end
    
    always@(posedge sys_clk or negedge rst_n) begin
        if(!rst_n) length_byte <= 4'd3;
        else if(cnt_cycle < 4'd2) length_byte <= 4'd3;
        else length_byte <= 4'd6; 
    end
    
    always@(posedge sys_clk or negedge rst_n) begin
        if(!rst_n) begin
            iic_busy_reg <= 1'b0; iic_finish_reg <= 1'b0;
        end else begin
            iic_busy_reg <= iic_busy; iic_finish_reg <= iic_finish;
        end
    end
    
    always @(posedge sys_clk or negedge rst_n) begin
        if(!rst_n) cnt_cycle <= 4'b0000;
        else if(start_batch) cnt_cycle <= 4'b0000;
        else if(iic_finish_pos) cnt_cycle <= cnt_cycle + 1;
    end
    
    always @(posedge sys_clk or negedge rst_n) begin
        if(!rst_n) en <= 1'b0;
        else if(start_batch) en <= 1'b1;
        else if(iic_busy_pos) en <= 1'b0;
        else if(iic_finish_pos && cnt_cycle < (iic_cycle-1)) en <= 1'b1;
    end
    
    always @(*) begin
        case(cnt_cycle)
            4'd0: begin data_one = data_1_one; data_two = data_1_two; 
                        data_three=0; data_four=0; data_five=0; end
            4'd1: begin data_one = data_2_one; data_two = data_2_two; 
                        data_three=0; data_four=0; data_five=0; end
            4'd2: begin
                data_one   = data_3_one;
                data_two   = batch_m1;   // 四轮数据在同一批次锁存，避免半包更新
                data_three = batch_m2; 
                data_four  = batch_m3; 
                data_five  = batch_m4; 
            end
            default: begin data_one=0; data_two=0; data_three=0; data_four=0; data_five=0; end
        endcase
    end
    
    // 底层不改变，保持原有波形驱动稳定
    iic_write iic_write_inst (
        .sys_clk(sys_clk),
        .rst_n(rst_n),
        .sda_in(sda_in),
        .iic_en(en),
        .length_byte(length_byte),
        .slave_address(slave_address),
        .data_one(data_one),
        .data_two(data_two),
        .data_three(data_three),
        .data_four(data_four),
        .data_five(data_five),
        .data_six(8'd0),     // 未用到必须给 0 以防报警
        .data_seven(8'd0),   // 同上
        .sda_out(sda_out),
        .iic_busy(iic_busy),
        .iic_finish(iic_finish),
        .oe(oe),
        .SCL(SCL)
    );
endmodule
