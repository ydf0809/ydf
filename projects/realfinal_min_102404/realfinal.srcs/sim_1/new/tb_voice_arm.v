`timescale 1ns / 1ps

module tb_voice_arm;

parameter CLK_FREQ = 33333333;
parameter UART_BPS = 115200;

localparam CLK_PERIOD  = 1000000000 / CLK_FREQ;
localparam BIT_PERIOD  = 1000000000 / UART_BPS;
localparam RST_HOLD_CLK = CLK_FREQ / 1000;

reg        clk       ;
reg        rst_n     ;
reg        frames    ;
integer    errors    ;
integer    i         ;
integer    f0        ;

reg [31:0] low_clk   ;
reg [31:0] last_low  ;
reg [15:0] fall_cnt  ;
reg [15:0] rise_cnt  ;
reg [15:0] mon_cnt   ;
reg [7:0]  mon_cmd   ;

wire       echo_line ;
wire [7:0] peer_cmd  ;
wire       peer_valid;
wire       link_err  ;
wire       arm_req   ;
wire       arm_rst_n ;
wire [4:0] track_pat ;
wire       track_upd ;
wire       link_cmd_v;
wire [7:0] mon_word  ;
wire       mon_done  ;
wire       mon_ferr  ;
wire [7:0] mon_id    ;
wire       mon_valid ;
wire       mon_derr  ;

board_link #(
    .CLK_FREQ   (CLK_FREQ ),
    .UART_BPS   (UART_BPS ),
    .ECHO_EN    (1'b1     ))
    u_lower(
    .clk            (clk       ),
    .rst_n          (rst_n     ),
    .link_rx        (frames    ),
    .link_tx        (echo_line ),
    .local_cmd      (8'd0      ),
    .local_send     (1'b0      ),
    .peer_cmd       (peer_cmd  ),
    .peer_valid     (peer_valid),
    .link_err       (link_err  )
    );

link_demux u_demux(
    .clk            (clk       ),
    .rst_n          (rst_n     ),
    .peer_cmd       (peer_cmd  ),
    .peer_valid     (peer_valid),
    .bbox_busy      (1'b0      ),
    .track_pat      (track_pat ),
    .track_upd      (track_upd ),
    .cmd_valid      (link_cmd_v)
    );

arm_voice_trigger #(
    .CLK_FREQ       (CLK_FREQ    ),
    .ARM_CMD        (8'd5        ),
    .RST_HOLD_MS    (1           ))
    u_trigger(
    .clk            (clk       ),
    .rst_n          (rst_n     ),
    .cmd            (peer_cmd  ),
    .cmd_valid      (link_cmd_v),
    .arm_req        (arm_req   ),
    .arm_rst_n      (arm_rst_n )
    );

uart_rx #(
    .CLK_FREQ   (CLK_FREQ ),
    .UART_BPS   (UART_BPS ))
    u_mon_rx(
    .clk            (clk       ),
    .rst_n          (rst_n     ),
    .uart_rxd       (echo_line ),
    .uart_rx_done   (mon_done  ),
    .uart_rx_data   (mon_word  ),
    .frame_err      (mon_ferr  )
    );

asr_frame_decode u_mon_decode(
    .clk            (clk       ),
    .rst_n          (rst_n     ),
    .uart_rx_data   (mon_word  ),
    .uart_rx_done   (mon_done  ),
    .cmd_id         (mon_id    ),
    .cmd_valid      (mon_valid ),
    .frame_err      (mon_derr  )
    );

initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

reg arm_rst_n_d;
wire rst_fall = arm_rst_n_d & ~arm_rst_n;
wire rst_rise = ~arm_rst_n_d & arm_rst_n;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        arm_rst_n_d <= 1'b1;
        low_clk     <= 32'd0;
        last_low    <= 32'd0;
        fall_cnt    <= 16'd0;
        rise_cnt    <= 16'd0;
        mon_cnt     <= 16'd0;
        mon_cmd     <= 8'd0;
    end
    else begin
        arm_rst_n_d <= arm_rst_n;
        if(rst_fall) begin
            fall_cnt <= fall_cnt + 1'b1;
            low_clk  <= 32'd1;
        end
        else if(!arm_rst_n)
            low_clk <= low_clk + 1'b1;
        if(rst_rise) begin
            rise_cnt <= rise_cnt + 1'b1;
            last_low <= low_clk;
        end
        if(mon_valid) begin
            mon_cnt <= mon_cnt + 1'b1;
            mon_cmd <= mon_id;
        end
    end
end

task send_byte;
    input [7:0] data;
    integer     b;
    begin
        frames = 1'b0;
        #(BIT_PERIOD);
        for(b = 0; b < 8; b = b + 1) begin
            frames = data[b];
            #(BIT_PERIOD);
        end
        frames = 1'b1;
        #(BIT_PERIOD);
    end
endtask

task send_frame;
    input [7:0] b0, b1, b2, b3, b4;
    begin
        send_byte(b0); send_byte(b1); send_byte(b2); send_byte(b3); send_byte(b4);
    end
endtask

task wait_pulse;
    input integer bits;
    begin
        i = 0;
        while((fall_cnt == f0) && (i < bits * BIT_PERIOD)) begin #1; i = i + 1; end
        if(fall_cnt == f0) begin
            $display("[FAIL] timeout: no arm reset pulse appeared");
            errors = errors + 1;
        end
        else begin

            i = 0;
            while((rise_cnt < fall_cnt) && (i < 200 * BIT_PERIOD)) begin #1; i = i + 1; end
            if(last_low < RST_HOLD_CLK - 4 || last_low > RST_HOLD_CLK + 4) begin
                $display("[FAIL] reset pulse was %0d clocks, expected about %0d",
                         last_low, RST_HOLD_CLK);
                errors = errors + 1;
            end
            else
                $display("[ OK ] arm reset pulse: %0d clocks (~%0d expected)", last_low, RST_HOLD_CLK);
        end
    end
endtask

initial begin
    errors = 0;
    rst_n  = 1'b0;
    frames = 1'b1;
    f0     = 0;
    repeat(10) @(posedge clk);
    rst_n = 1'b1;
    repeat(10) @(posedge clk);

    $display("==================================================");
    $display(" tb_voice_arm: CLK_FREQ=%0d  UART_BPS=%0d", CLK_FREQ, UART_BPS);
    $display("   voice CARGO (cmd=5) must start the arm action");
    $display("==================================================");

    $display("--- 1) reset state ---");
    if(arm_req !== 1'b0 || arm_rst_n !== 1'b1) begin
        $display("[FAIL] after reset: arm_req=%b arm_rst_n=%b (expected 0 / 1)",
                 arm_req, arm_rst_n);
        errors = errors + 1;
    end
    else
        $display("[ OK ] after reset: arm_req=0, arm_rst_n=1 (arm held, not running)");

    $display("--- 2) upper board says CARGO: AA 55 05 55 AA ---");
    f0 = fall_cnt;
    send_frame(8'hAA, 8'h55, 8'h05, 8'h55, 8'hAA);
    wait_pulse(300);
    if(arm_req !== 1'b1) begin
        $display("[FAIL] arm_req did not go high after cmd=5");
        errors = errors + 1;
    end
    else
        $display("[ OK ] arm_req high: the arm action was started");
    if(arm_rst_n !== 1'b1) begin
        $display("[FAIL] arm_rst_n still low, the arm would never start");
        errors = errors + 1;
    end
    else
        $display("[ OK ] arm_rst_n released again (the arm is free to run)");
    i = 0;
    while((mon_cnt == 0) && i < 300 * BIT_PERIOD) begin #1; i = i + 1; end
    if(mon_cnt == 0 || mon_cmd !== 8'h05) begin
        $display("[FAIL] echo back to the upper board missing or wrong (got %0d frames, cmd=0x%02h)",
                 mon_cnt, mon_cmd);
        errors = errors + 1;
    end
    else
        $display("[ OK ] echoed AA 55 05 55 AA back to the upper board");

    $display("--- 3) a different command (02 FOLLOW) must not touch the arm ---");
    f0 = fall_cnt;
    send_frame(8'hAA, 8'h55, 8'h02, 8'h55, 8'hAA);
    #(120 * BIT_PERIOD);
    if(fall_cnt != f0) begin
        $display("[FAIL] cmd=2 produced %0d extra reset pulse(s)", fall_cnt - f0);
        errors = errors + 1;
    end
    else
        $display("[ OK ] cmd=2 produced no reset pulse");

    $display("--- 4) a broken frame must not touch the arm ---");
    f0 = fall_cnt;
    send_frame(8'hAA, 8'h55, 8'h05, 8'h55, 8'h00);
    #(120 * BIT_PERIOD);
    if(fall_cnt != f0) begin
        $display("[FAIL] a broken frame produced a reset pulse");
        errors = errors + 1;
    end
    else
        $display("[ OK ] broken frame ignored (no reset pulse)");

    $display("--- 5) saying CARGO again must run the action again ---");
    f0 = fall_cnt;
    send_frame(8'hAA, 8'h55, 8'h05, 8'h55, 8'hAA);
    wait_pulse(300);
    if((fall_cnt - f0) != 1) begin
        $display("[FAIL] expected exactly 1 new reset pulse, got %0d", fall_cnt - f0);
        errors = errors + 1;
    end
    else
        $display("[ OK ] second CARGO produced one more reset pulse");

    $display("--- 7) a tracking status frame (0x85) must not start the arm ---");
    f0 = fall_cnt;
    send_frame(8'hAA, 8'h55, 8'h85, 8'h55, 8'hAA);
    #(150 * BIT_PERIOD);
    if(fall_cnt != f0) begin
        $display("[FAIL] a tracking frame produced an arm reset pulse");
        errors = errors + 1;
    end
    else
        $display("[ OK ] tracking frame ignored by the arm trigger");
    if(track_pat !== 5'b00101) begin
        $display("[FAIL] track_pat=0b%05b, expected 0b00101", track_pat);
        errors = errors + 1;
    end
    else
        $display("[ OK ] link_demux latched the five sensors = 0b00101");

    $display("==================================================");
    if(errors == 0)
        $display(" RESULT: all passed (errors=0)");
    else
        $display(" RESULT: %0d checks failed", errors);
    $display("==================================================");
    $finish;
end

endmodule
