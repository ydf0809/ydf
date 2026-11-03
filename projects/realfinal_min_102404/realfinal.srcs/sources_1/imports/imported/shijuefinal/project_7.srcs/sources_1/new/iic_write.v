module iic_write(
	sys_clk,
	rst_n,
	sda_in,
	iic_en,
	length_byte,
	slave_address,
	data_one,
	data_two,
	sda_out,
	iic_busy,
	iic_finish,
	oe,
	SCL,
	data_three,
	data_four,
	data_five,
	data_six,
	data_seven);

	input sys_clk;
	input rst_n;
	input sda_in;
	input iic_en;
	input [3:0] length_byte;
	input [6:0] slave_address;
	input [7:0] data_one;
	input [7:0] data_two;
	output sda_out;
	output iic_busy;
	output iic_finish;
	output oe;
	output SCL;
	input [7:0] data_three;
	input [7:0] data_four;
	input [7:0] data_five;
	input [7:0] data_six;
	input [7:0] data_seven;

	wire sys_clk;
	wire rst_n;
	wire sda_in;
	wire iic_en;
	wire [3:0] length_byte;
	wire [6:0] slave_address;
	wire [7:0] data_one;
	wire [7:0] data_two;
	reg sda_out;
	reg iic_busy;
	reg iic_finish;
	reg oe;
	reg SCL;
	wire [7:0] data_three;
	wire [7:0] data_four;
	wire [7:0] data_five;
	wire [7:0] data_six;
	wire [7:0] data_seven;

	parameter IDLE=3'd0;
	parameter START=3'd1;
	parameter WRITE_DATA=3'd2;
	parameter S_ACK=3'd3;
	parameter STOP=3'd4;
	parameter FINISH=3'd5;

	parameter SYS_CLK=33_333_333;
	parameter SCL_CLK=100_000;

	parameter  GO=4'd1,
						BACK=4'd2;

	parameter Mid_High=83,
	           Neg_SCL=167,
	           Mid_Low=250,
	           Pos_SCL=334;

	reg [9:0] cnt_sys_clk;
	wire mid_high;
	wire neg_scl;
	wire mid_low;
	wire pos_scl;
	assign   mid_high=(cnt_sys_clk== Mid_High) ;
	assign   neg_scl= (cnt_sys_clk==Neg_SCL)    ;
	assign   mid_low= (cnt_sys_clk==Mid_Low)    ;
	assign   pos_scl= (cnt_sys_clk==Pos_SCL)    ;

	reg iic_en_reg1;
	reg iic_en_reg2;
	wire iic_en_pos;

	assign iic_en_pos=iic_en_reg1&&~iic_en_reg2;

	always@(posedge sys_clk or negedge rst_n)begin
	    if(!rst_n)begin
	        iic_en_reg1<=1'b0;
	        iic_en_reg2<=1'b0;
	    end
	    else begin
	        iic_en_reg1<=iic_en;
	        iic_en_reg2<=iic_en_reg1;
	    end
	end

	reg iic_busy_reg;
	wire iic_busy_neg;

	assign iic_busy_neg=~iic_busy&&iic_busy_reg;

	always@ (posedge sys_clk or negedge rst_n)begin
	    if(!rst_n)
	        iic_busy_reg<=1'b0;
	    else
	        iic_busy_reg<=iic_busy;
	end

	reg iic_start;
	always @(posedge sys_clk or negedge rst_n)begin
	    if(!rst_n)
	        iic_start<=1'b0;
	    else if(iic_en_pos)
	        iic_start<=1'b1;
	    else if(iic_busy_neg)
	        iic_start<=1'b0;
	    else
	        iic_start<=1'b0;
	end

	reg SCL_en;
	always@(posedge sys_clk or negedge rst_n)begin
	    if(!rst_n)
	        cnt_sys_clk<=10'b00_0000_0000;
	    else if(SCL_en)
	        if(cnt_sys_clk==Pos_SCL)
	            cnt_sys_clk<=10'b00_0000_0000;
	        else
	            cnt_sys_clk<=cnt_sys_clk+1;
	    else
	        cnt_sys_clk<=10'b00_0000_0000;
	end
	always @(posedge sys_clk or negedge rst_n)begin
	    if(!rst_n)
	       SCL<=1'b1;
	   else if(SCL_en)
	       if(neg_scl)
	           SCL<=1'b0;
	       else if(pos_scl)
	           SCL<=1'b1;
	       else
	           SCL<=SCL;
	   else
	       SCL<=1'b1;
	end

	reg [3:0] cnt_data;
	reg [3:0] cnt_byte;
	reg [2:0] state;
	reg [2:0] next_state;

	reg sack_flag;

	always @(posedge sys_clk or negedge rst_n)begin
	    if(!rst_n)
	        state<=3'b000;
	    else
	        state<=next_state;
	end

	always@(*)begin
	    if(!rst_n)
	        next_state=3'b000;
	    else
	        case(state)
	                IDLE:begin
	                    if(iic_start)
	                        next_state=START;
	                    else
	                        next_state=IDLE;
	                end
	                START:begin
	                    if(mid_low)
	                        next_state=WRITE_DATA;
	                    else
	                        next_state=START;
	                end
	                WRITE_DATA:begin
	                    if(cnt_data==4'd8&&pos_scl)
	                        next_state=S_ACK;
	                    else
	                        next_state=WRITE_DATA;
	                end
	                S_ACK:begin
	                    if(mid_low)
	                        if(cnt_byte<length_byte&&sack_flag)
	                            next_state=WRITE_DATA;
	                        else
	                            next_state=STOP;
	                    else
	                        next_state=S_ACK;
	                end
	                STOP:begin
	                    if(mid_high)
	                        next_state=FINISH;
	                    else
	                        next_state=STOP;
	                end
	                FINISH:begin
	                    if(iic_finish)
	                        next_state=IDLE;
	                    else
	                        next_state=FINISH;
	                end
	                default:    next_state=IDLE;
	            endcase
	end
	parameter CNT_DELAY=2000;
	reg [7:0] word_out_reg;
	reg finish_delay;
	reg [15:0] cnt_delay;
	always @(posedge sys_clk or negedge rst_n)begin
	    if(!rst_n)begin
	        iic_busy<=1'b0;
	        iic_finish<=1'b0;
	        cnt_data<=4'b0000;
	        cnt_byte<=4'b0000;
	        SCL_en<=1'b0;
	        word_out_reg<=8'b0000_0000;
	        sda_out<=1'b1;
	        oe<=1'b0;
	        sack_flag<=1'b0;
	        finish_delay<=1'b0;
	    end
	    else
	        case(state)
	            IDLE:begin
	                iic_busy<=1'b0;
	                iic_finish<=1'b0;
	                cnt_data<=4'b0000;
	                cnt_byte<=4'b0000;
	                SCL_en<=1'b0;
	                word_out_reg<=8'b0000_0000;
	                sda_out<=1'b1;
	                oe<=1'b0;
	                sack_flag<=1'b0;
	                finish_delay<=1'b0;
	            end
	            START:begin
	                oe<=1'b1;
	                SCL_en<=1'b1;
	                word_out_reg<={slave_address,1'b0};
	                iic_busy<=1'b1;
	                if(mid_high)
	                    sda_out<=1'b0;
	            end
	            WRITE_DATA:begin
	                sack_flag<=1'b0;
	                oe<=1'b1;
	                if(cnt_data<8)
	                    sda_out<=word_out_reg[7-cnt_data];
	                else begin
	                    sda_out<=sda_out;
	                    if(pos_scl)
	                        cnt_byte<=cnt_byte+1;
	                end
	                if(mid_low)
	                    cnt_data<=cnt_data+1;
	                else
	                    cnt_data<=cnt_data;
	            end
	            S_ACK:begin
	                oe<=1'b0;
	                cnt_data<=4'b0000;
	                case(cnt_byte)
	                    4'd1:    word_out_reg<=data_one;
	                    4'd2:    word_out_reg<=data_two;
	                    4'd3:    word_out_reg<=data_three;
	                    4'd4:    word_out_reg<=data_four;
	                    4'd5:    word_out_reg<=data_five;
						4'd6:	word_out_reg<=data_six;
						4'd7:	word_out_reg<=data_seven;
	                default:     word_out_reg<=8'b0000_0000;
	                endcase
	                if(mid_high)
	                    sack_flag<=~sda_in;
	                if(mid_low)
	                    sda_out<=1'b0;
	            end
	            STOP:begin
	                oe<=1'b1;
	                if(mid_high)begin
	                    sda_out<=1'b1;
	                    SCL_en<=1'b0;
	                    finish_delay<=1'b1;
	                    iic_busy<=1'b0;
						cnt_byte <= 4'd0;
	                end
	            end
	            FINISH:begin
	                if(cnt_delay>=CNT_DELAY)begin
	                    finish_delay<=1'b0;
	                    iic_finish<=1'b1;

	                end
	            end
	            default:    ;
	        endcase
	end

	always@(posedge sys_clk or negedge rst_n)begin
	    if(!rst_n)
	        cnt_delay<=16'd0;
	    else if(finish_delay)
	        cnt_delay<=cnt_delay+1;
	    else
	        cnt_delay<=16'd0;
	end

endmodule
