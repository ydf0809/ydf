`timescale 1ns / 1ps

module tb_arm_stop;

parameter CLK_FREQ = 33333333;
parameter UART_BPS = 115200;

localparam CLK_PERIOD = 1000000000 / CLK_FREQ;
localparam BIT_PERIOD = 1000000000 / UART_BPS;

reg        clk     ;
reg        rst_n   ;
reg        run_en  ;
reg        stop_i  ;
reg        home_i  ;
integer    errors  ;
integer    i       ;
integer    n0      ;
integer    m0      ;

reg [39:0] word    ;
reg [7:0]  rx_byte ;
reg        rx_done ;
reg        rx_err  ;
reg [15:0] servo_cnt;
reg [15:0] stop_cnt ;
reg [15:0] start_cnt;
reg [15:0] byte_cnt ;
reg        stop_pending;
reg        stop_chk_err;

wire       arm_uart;
wire       tcon    ;
wire       uart_done;
wire [7:0] uart_data;
wire       uart_err ;
wire [39:0] word_next;
wire       hit_servo;
wire       hit_stop ;
wire       hit_start;

assign word_next = {word[31:0], uart_data};

assign hit_servo = (word_next[39:32] == 8'h55) && (word_next[31:24] == 8'h55) &&
                   (word_next[15:8]  == 8'h07) && (word_next[7:0]   == 8'h07);

assign hit_stop  = (word_next[39:32] == 8'h55) && (word_next[31:24] == 8'h55) &&
                   (word_next[23:16] == 8'hFE) && (word_next[15:8]  == 8'h03) &&
                   (word_next[7:0]   == 8'h0C);

assign hit_start = (word_next[39:32] == 8'h55) && (word_next[31:24] == 8'h55) &&
                   (word_next[23:16] == 8'hFE) && (word_next[15:8]  == 8'h03) &&
                   (word_next[7:0]   == 8'h0B);

arm_pick_place_once_top #(
    .CLK_HZ         (CLK_FREQ),
    .STARTUP_WAIT_MS(1       ))
    u_arm(
    .sys_clk  (clk     ),
    .rst_n    (rst_n   ),
    .run_en   (run_en  ),
    .stop_i   (stop_i  ),
    .home_i   (home_i  ),
    .arm_uart (arm_uart),
    .tcon     (tcon    )
    );

uart_rx #(
    .CLK_FREQ (CLK_FREQ),
    .UART_BPS (UART_BPS))
    u_rx(
    .clk            (clk      ),
    .rst_n          (rst_n    ),
    .uart_rxd       (arm_uart ),
    .uart_rx_done   (uart_done),
    .uart_rx_data   (uart_data),
    .frame_err      (uart_err )
    );

initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        word         <= 40'd0;
        rx_byte      <= 8'd0;
        rx_done      <= 1'b0;
        rx_err       <= 1'b0;
        servo_cnt    <= 16'd0;
        stop_cnt     <= 16'd0;
        start_cnt    <= 16'd0;
        byte_cnt     <= 16'd0;
        stop_pending <= 1'b0;
        stop_chk_err <= 1'b0;
    end
    else begin
        rx_done <= uart_done;
        if(uart_err) rx_err <= 1'b1;
        if(uart_done) begin
            rx_byte  <= uart_data;
            byte_cnt <= byte_cnt + 1'b1;
            word     <= word_next;

            if(stop_pending) begin
                stop_pending <= 1'b0;
                if(uart_data !== 8'hF2) stop_chk_err <= 1'b1;
            end
            if(hit_stop) begin
                stop_cnt     <= stop_cnt + 1'b1;
                stop_pending <= 1'b1;
            end
            if(hit_servo)
                servo_cnt <= servo_cnt + 1'b1;
            if(hit_start)
                start_cnt <= start_cnt + 1'b1;
        end
    end
end

initial begin
    errors = 0;
    rst_n  = 1'b0;
    run_en = 1'b0;
    stop_i = 1'b0;
    home_i = 1'b0;
    repeat(10) @(posedge clk);
    rst_n = 1'b1;
    repeat(10) @(posedge clk);
    @(negedge clk); home_i = 1'b1;
    @(negedge clk); home_i = 1'b0;

    $display("==================================================");
    $display(" tb_arm_stop: CLK_FREQ=%0d  UART_BPS=%0d  STARTUP_WAIT_MS=1", CLK_FREQ, UART_BPS);
    $display("==================================================");

    $display("--- 1) top-level power-up home request ---");
    #(12000000);
    if((servo_cnt != 6) || (start_cnt != 1) || (stop_cnt != 0)) begin
        $display("[FAIL] power-up home: %0d pose / %0d start / %0d stop packets (expected 6/1/0)",
                 servo_cnt, start_cnt, stop_cnt);
        errors = errors + 1;
    end
    else
        $display("[ OK ] power-up home = 6 pose packets + 1 START");
    n0 = servo_cnt;
    #(3000000);
    if(servo_cnt != n0) begin
        $display("[FAIL] the arm kept moving after the power-up home");
        errors = errors + 1;
    end
    else
        $display("[ OK ] stays at the initial pose until told to run");

    $display("--- 2) run_en=1: pose packets start after the startup wait ---");
    @(posedge clk);
    run_en <= 1'b1;
    i = 0;
    while((servo_cnt == 0) && i < 3000000) begin #1; i = i + 1; end
    if(servo_cnt == 0) begin
        $display("[FAIL] no pose packet after enabling the arm");
        errors = errors + 1;
    end
    else
        $display("[ OK ] pose packets started (%0d seen)", servo_cnt);

    $display("--- 3) command 4: run_en drops + stop_i pulses ---");
    n0 = servo_cnt;
    @(posedge clk);
    run_en <= 1'b0;
    stop_i <= 1'b1;
    @(posedge clk);
    stop_i <= 1'b0;
    i = 0;
    while((stop_cnt == 0) && i < 3000000) begin #1; i = i + 1; end
    if(stop_cnt == 0) begin
        $display("[FAIL] no SERVO_MOVE_STOP packet was sent");
        errors = errors + 1;
    end
    else
        $display("[ OK ] SERVO_MOVE_STOP sent (55 55 FE 03 0C)");
    if(stop_chk_err !== 1'b0) begin
        $display("[FAIL] MOVE_STOP checksum is not 0xF2");
        errors = errors + 1;
    end
    else
        $display("[ OK ] MOVE_STOP checksum = 0xF2");
    #(4000000);
    if(stop_cnt != 1) begin
        $display("[FAIL] %0d stop packets sent, expected exactly 1", stop_cnt);
        errors = errors + 1;
    end
    else
        $display("[ OK ] exactly one stop packet was sent");
    if(servo_cnt > (n0 + 1)) begin
        $display("[FAIL] the arm kept sending pose packets after the stop (%0d -> %0d)",
                 n0, servo_cnt);
        errors = errors + 1;
    end
    else
        $display("[ OK ] no new pose packets after the stop (was %0d, now %0d)", n0, servo_cnt);

    $display("--- 4) enable again: the sequence restarts ---");
    n0 = servo_cnt;
    @(posedge clk);
    run_en <= 1'b1;
    i = 0;
    while((servo_cnt <= n0) && i < 3000000) begin #1; i = i + 1; end
    if(servo_cnt <= n0) begin
        $display("[FAIL] enabling again did not restart the sequence");
        errors = errors + 1;
    end
    else
        $display("[ OK ] enabling again restarted the sequence (pose packets: %0d)", servo_cnt);

    $display("--- 5) home request (commands 1/2/3): initial pose, then stay ---");
    @(posedge clk);
    run_en <= 1'b0;
    #(2000000);
    n0 = servo_cnt;
    m0 = start_cnt;
    @(posedge clk);
    home_i <= 1'b1;
    @(posedge clk);
    home_i <= 1'b0;
    i = 0;
    while(((servo_cnt < (n0 + 6)) || (start_cnt == m0)) && i < 6000000) begin #1; i = i + 1; end
    if((servo_cnt - n0) != 6) begin
        $display("[FAIL] home sent %0d pose packets, expected 6", servo_cnt - n0);
        errors = errors + 1;
    end
    else if((start_cnt - m0) != 1) begin
        $display("[FAIL] home sent %0d START packets, expected 1", start_cnt - m0);
        errors = errors + 1;
    end
    else
        $display("[ OK ] home = 6 pose packets + 1 broadcast START");
    #(3000000);
    if(servo_cnt != (n0 + 6)) begin
        $display("[FAIL] the arm kept moving after homing (%0d extra packets)",
                 servo_cnt - n0 - 6);
        errors = errors + 1;
    end
    else
        $display("[ OK ] arm stayed at the home pose (no more packets)");

    if(rx_err !== 1'b0) begin
        $display("[FAIL] the servo bus had a framing error");
        errors = errors + 1;
    end

    $display("==================================================");
    if(errors == 0)
        $display(" RESULT: all passed (errors=0)");
    else
        $display(" RESULT: %0d checks failed", errors);
    $display("==================================================");
    $finish;
end

endmodule
