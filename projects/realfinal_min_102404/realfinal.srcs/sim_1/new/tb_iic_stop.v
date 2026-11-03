`timescale 1ns / 1ps
module tb_iic_stop;
    reg clk = 0;
    always #15 clk = ~clk;
    reg rst_n = 0;
    reg req = 0;
    reg [7:0] m1 = 18, m2 = -18, m3 = -18, m4 = 18;
    tri1 sda;
    wire scl;
    integer errors = 0;
    integer stop_packets = 0;
    integer motion_packets = 0;
    integer torn_packets = 0;
    reg receiving = 0;
    integer bit_index = 0;
    integer byte_index = 0;
    reg [7:0] shift = 0;
    reg [7:0] reg_addr = 0;
    reg [31:0] motor_bytes = 0;

    iic_w_top dut (.sys_clk(clk), .rst_n(rst_n), .SDA(sda), .SCL(scl),
        .motor1_spd(m1), .motor2_spd(m2), .motor3_spd(m3), .motor4_spd(m4),
        .cmd_update_req(req));
    // ACK every byte; reconstruct the transmitted bytes from the actual bus.
    assign sda = (dut.iic_write_inst.state == 3'd3) ? 1'b0 : 1'bz;
    always @(negedge sda) if (scl === 1'b1 && !receiving) begin
        receiving = 1; bit_index = 0; byte_index = 0;
    end
    always @(posedge sda) if (scl === 1'b1) receiving = 0;
    always @(posedge scl) if (receiving) begin
        if (bit_index < 8) begin
            shift = {shift[6:0], sda};
            bit_index = bit_index + 1;
        end else begin
            bit_index = 0;
            if (byte_index == 1) reg_addr = shift;
            if (reg_addr == 8'd51 && byte_index >= 2 && byte_index <= 5) begin
                motor_bytes = {motor_bytes[23:0], shift};
                if (byte_index == 5) begin
                    if (motor_bytes == 32'h00000000) stop_packets = stop_packets + 1;
                    else if (motor_bytes == 32'h12eeee12) motion_packets = motion_packets + 1;
                    else begin
                        torn_packets = torn_packets + 1;
                        $display("[FAIL] torn motor packet %08h", motor_bytes);
                    end
                end
            end
            byte_index = byte_index + 1;
        end
    end

    task pulse;
        begin
            @(negedge clk); req = 1;
            @(negedge clk); req = 0;
        end
    endtask
    task stop;
        begin m1 = 0; m2 = 0; m3 = 0; m4 = 0; pulse; end
    endtask
    task reset_motion;
        begin
            @(negedge clk); rst_n = 0; req = 0;
            repeat (5) @(negedge clk);
            m1 = 18; m2 = -18; m3 = -18; m4 = 18;
            stop_packets = 0; motion_packets = 0; torn_packets = 0;
            receiving = 0; rst_n = 1;
            pulse;
        end
    endtask
    task check_stop;
        input [8*80-1:0] label;
        begin
            repeat (200000) @(posedge clk);
            if (stop_packets < 1 || torn_packets != 0) begin
                $display("[FAIL] %0s: stop=%0d torn=%0d motion=%0d", label, stop_packets, torn_packets, motion_packets);
                errors = errors + 1;
            end else $display("[ OK ] %0s: stop=%0d motion=%0d", label, stop_packets, motion_packets);
        end
    endtask
    initial begin
        $display("== tb_iic_stop start ==");
        reset_motion;
        repeat (200000) @(posedge clk);
        if (motion_packets != 1 || torn_packets != 0) begin
            $display("[FAIL] uninterrupted control packet: motion=%0d torn=%0d", motion_packets, torn_packets);
            errors = errors + 1;
        end else $display("[ OK ] uninterrupted motion packet decoded on I2C bus");
        reset_motion;
        wait (dut.iic_busy === 1'b1);
        repeat (100) @(posedge clk);
        stop;
        check_stop("stop arriving during configuration reaches motor register");
        reset_motion;
        wait (dut.cnt_cycle == 2 && dut.iic_busy === 1'b1);
        repeat (100) @(posedge clk);
        stop;
        check_stop("stop during motor packet queues an intact stop packet");
        if (errors == 0) $display("== tb_iic_stop PASS ==");
        else $display("== tb_iic_stop FAIL: %0d error(s) ==", errors);
        $finish;
    end
    initial begin #30_000_000; $display("[FAIL] tb_iic_stop watchdog timeout"); $finish; end
endmodule
