`timescale 1ns/1ps
module tb_i2c_config_clock;
reg clk=0,rst_n=0;
always #15 clk=~clk;
wire dri_clk,sda;
integer ticks=0,last_tick=0,edges=0,errors=0;
i2c_dri #(.CLK_FREQ(33_333_333),.I2C_FREQ(250_000)) dut(
 .clk(clk),.rst_n(rst_n),.bit_ctrl(1'b1),.i2c_exec(1'b0),
 .i2c_rh_wl(1'b0),.i2c_addr(16'd0),.i2c_data_w(8'd0),.sda(sda),.dri_clk(dri_clk));
pullup(sda);
always @(posedge clk) if(rst_n) ticks=ticks+1;
always @(posedge dri_clk) if(rst_n) begin
 if(edges!=0 && ticks-last_tick!=32)begin errors=errors+1;$display("FAIL divided-clock period %0d",ticks-last_tick);end
 last_tick=ticks;edges=edges+1;
end
initial begin
 repeat(4)@(negedge clk);rst_n=1;repeat(400)@(negedge clk);
 if(edges<8)begin errors=errors+1;$display("FAIL missing clock edges");end
 if(errors==0)$display("I2C_CONFIG_CLOCK_TEST: PASS divide_by=32");else $display("I2C_CONFIG_CLOCK_TEST: FAIL");
 $finish;end
endmodule
