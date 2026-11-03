`timescale 1ns / 1ps

module tb_board_link;

parameter CLK_FREQ = 33333333;
parameter UART_BPS = 115200;

localparam CLK_PERIOD = 1000000000 / CLK_FREQ;
localparam BIT_PERIOD = 1000000000 / UART_BPS;
localparam TRK_MS     = CLK_FREQ / 1000;

reg        clk      ;
reg        rst_n    ;
reg [4:0]  tb_track ;
reg [7:0]  tb_cmd   ;
reg        tb_upd   ;
reg        inj_en   ;
reg        inj_level;
integer    errors   ;
integer    i        ;
integer    u0, l0, mc0, mt0, m2c0, m2t0, d0;

reg [7:0]  up_pcmd  ; reg [15:0] up_pcnt  ;
reg [7:0]  lo_pcmd  ; reg [15:0] lo_pcnt  ;
reg [7:0]  m1_cmd   ; reg [15:0] m1_cmd_cnt;
reg [4:0]  m1_trk   ; reg [15:0] m1_trk_cnt;
reg [7:0]  m2_cmd   ; reg [15:0] m2_cmd_cnt;
reg [4:0]  m2_trk   ; reg [15:0] m2_trk_cnt;
reg [4:0]  dmx_pat  ; reg [15:0] dmx_upd_cnt; reg [15:0] dmx_cmd_cnt;

wire [7:0] up_cmd_b  ;
wire       up_send_b ;
wire       up_to_lo  ;
wire       lo_raw    ;
wire       lo_to_up  ;
wire [7:0] up_peer   ; wire up_valid  ; wire up_linkerr ;
wire [7:0] lo_peer   ; wire lo_valid  ; wire lo_linkerr ;
wire [7:0] m1_word   ; wire m1_done   ; wire m1_ferr ; wire [7:0] m1_id ; wire m1_valid ; wire m1_derr;
wire [7:0] m2_word   ; wire m2_done   ; wire m2_ferr ; wire [7:0] m2_id ; wire m2_valid ; wire m2_derr;
wire [4:0] dmx_pat_w ; wire dmx_upd_w ; wire dmx_cmd_w ;

track_send #(
    .CLK_FREQ       (CLK_FREQ   ),
    .SEND_PERIOD_US (1000       ))
    u_track_send(
    .clk            (clk        ),
    .rst_n          (rst_n      ),
    .track_l2       (tb_track[4]),
    .track_l1       (tb_track[3]),
    .track_m        (tb_track[2]),
    .track_r1       (tb_track[1]),
    .track_r2       (tb_track[0]),
    .mode_upd       (tb_upd     ),
    .mode_cmd       (tb_cmd     ),
    .local_cmd      (up_cmd_b   ),
    .local_send     (up_send_b  )
    );

board_link #(
    .CLK_FREQ   (CLK_FREQ ),
    .UART_BPS   (UART_BPS ),
    .ECHO_EN    (1'b0     ))
    u_upper(
    .clk            (clk      ),
    .rst_n          (rst_n    ),
    .link_rx        (lo_to_up ),
    .link_tx        (up_to_lo ),
    .local_cmd      (up_cmd_b ),
    .local_send     (up_send_b),
    .peer_cmd       (up_peer  ),
    .peer_valid     (up_valid ),
    .link_err       (up_linkerr)
    );

board_link #(
    .CLK_FREQ   (CLK_FREQ ),
    .UART_BPS   (UART_BPS ),
    .ECHO_EN    (1'b1     ))
    u_lower(
    .clk            (clk      ),
    .rst_n          (rst_n    ),
    .link_rx        (up_to_lo ),
    .link_tx        (lo_raw   ),
    .local_cmd      (8'd0     ),
    .local_send     (1'b0     ),
    .peer_cmd       (lo_peer  ),
    .peer_valid     (lo_valid ),
    .link_err       (lo_linkerr)
    );

link_demux u_demux(
    .clk            (clk      ),
    .rst_n          (rst_n    ),
    .peer_cmd       (lo_peer  ),
    .peer_valid     (lo_valid ),
    .bbox_busy      (1'b0     ),
    .track_pat      (dmx_pat_w),
    .track_upd      (dmx_upd_w),
    .cmd_valid      (dmx_cmd_w)
    );

uart_rx #(
    .CLK_FREQ   (CLK_FREQ ),
    .UART_BPS   (UART_BPS ))
    u_mon1_rx(
    .clk            (clk      ),
    .rst_n          (rst_n    ),
    .uart_rxd       (up_to_lo ),
    .uart_rx_done   (m1_done  ),
    .uart_rx_data   (m1_word  ),
    .frame_err      (m1_ferr  )
    );

asr_frame_decode u_mon1_decode(
    .clk            (clk      ),
    .rst_n          (rst_n    ),
    .uart_rx_data   (m1_word  ),
    .uart_rx_done   (m1_done  ),
    .cmd_id         (m1_id    ),
    .cmd_valid      (m1_valid ),
    .frame_err      (m1_derr  )
    );

uart_rx #(
    .CLK_FREQ   (CLK_FREQ ),
    .UART_BPS   (UART_BPS ))
    u_mon2_rx(
    .clk            (clk      ),
    .rst_n          (rst_n    ),
    .uart_rxd       (lo_raw   ),
    .uart_rx_done   (m2_done  ),
    .uart_rx_data   (m2_word  ),
    .frame_err      (m2_ferr  )
    );

asr_frame_decode u_mon2_decode(
    .clk            (clk      ),
    .rst_n          (rst_n    ),
    .uart_rx_data   (m2_word  ),
    .uart_rx_done   (m2_done  ),
    .cmd_id         (m2_id    ),
    .cmd_valid      (m2_valid ),
    .frame_err      (m2_derr  )
    );

assign lo_to_up = inj_en ? inj_level : lo_raw;

initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        up_pcmd <= 8'd0; up_pcnt <= 16'd0;
        lo_pcmd <= 8'd0; lo_pcnt <= 16'd0;
        m1_cmd  <= 8'd0; m1_cmd_cnt <= 16'd0; m1_trk <= 5'd0; m1_trk_cnt <= 16'd0;
        m2_cmd  <= 8'd0; m2_cmd_cnt <= 16'd0; m2_trk <= 5'd0; m2_trk_cnt <= 16'd0;
        dmx_pat <= 5'd0; dmx_upd_cnt <= 16'd0; dmx_cmd_cnt <= 16'd0;
    end
    else begin
        if(up_valid) begin up_pcnt <= up_pcnt + 1'b1; up_pcmd <= up_peer; end
        if(lo_valid) begin lo_pcnt <= lo_pcnt + 1'b1; lo_pcmd <= lo_peer; end
        if(m1_valid) begin
            if(m1_id[7]) begin m1_trk_cnt <= m1_trk_cnt + 1'b1; m1_trk <= m1_id[4:0]; end
            else         begin m1_cmd_cnt <= m1_cmd_cnt + 1'b1; m1_cmd <= m1_id;      end
        end
        if(m2_valid) begin
            if(m2_id[7]) begin m2_trk_cnt <= m2_trk_cnt + 1'b1; m2_trk <= m2_id[4:0]; end
            else         begin m2_cmd_cnt <= m2_cmd_cnt + 1'b1; m2_cmd <= m2_id;      end
        end
        if(dmx_upd_w) begin dmx_upd_cnt <= dmx_upd_cnt + 1'b1; dmx_pat <= dmx_pat_w; end
        if(dmx_cmd_w) dmx_cmd_cnt <= dmx_cmd_cnt + 1'b1;
    end
end

task send_cmd;
    input [7:0] c;
    begin
        @(posedge clk);
        tb_cmd <= c;
        tb_upd <= 1'b1;
        @(posedge clk);
        tb_upd <= 1'b0;
        tb_cmd <= 8'd0;
    end
endtask

task mark;
    begin
        u0  = up_pcnt;    l0  = lo_pcnt;
        mc0 = m1_cmd_cnt; mt0 = m1_trk_cnt;
        m2c0= m2_cmd_cnt; m2t0= m2_trk_cnt;
        d0  = dmx_upd_cnt;
    end
endtask

task wait_up;
    input [7:0] exp;
    begin
        i = 0;
        while((up_pcnt == u0) && i < 400 * BIT_PERIOD) begin #1; i = i + 1; end
        if(up_pcnt == u0) begin
            $display("[FAIL] timeout: upper never decoded the echo");
            errors = errors + 1;
        end
        else if(up_pcmd !== exp) begin
            $display("[FAIL] upper decoded 0x%02h, expected 0x%02h", up_pcmd, exp);
            errors = errors + 1;
        end
        else
            $display("[ OK ] upper decoded the echo, byte=0x%02h", up_pcmd);
    end
endtask

task wait_lo;
    input [7:0] exp;
    begin
        i = 0;
        while((lo_pcnt == l0) && i < 400 * BIT_PERIOD) begin #1; i = i + 1; end
        if(lo_pcnt == l0) begin
            $display("[FAIL] timeout: lower never decoded the frame");
            errors = errors + 1;
        end
        else if(lo_pcmd !== exp) begin
            $display("[FAIL] lower decoded 0x%02h, expected 0x%02h", lo_pcmd, exp);
            errors = errors + 1;
        end
        else
            $display("[ OK ] lower decoded the frame, byte=0x%02h", lo_pcmd);
    end
endtask

task wait_mon;
    input [7:0] exp;
    begin
        i = 0;
        while((m1_cmd_cnt == mc0) && i < 400 * BIT_PERIOD) begin #1; i = i + 1; end
        if(m1_cmd_cnt == mc0) begin
            $display("[FAIL] timeout: no command frame appeared on the wire");
            errors = errors + 1;
        end
        else if(m1_cmd !== exp) begin
            $display("[FAIL] wire carried cmd=0x%02h, expected 0x%02h", m1_cmd, exp);
            errors = errors + 1;
        end
        else
            $display("[ OK ] wire carried AA 55 %02h 55 AA", m1_cmd);
    end
endtask

task set_track_wait;
    input [4:0] pat;
    begin
        @(posedge clk);
        tb_track <= pat;
        i = 0;
        while((dmx_pat !== pat) && i < 400 * BIT_PERIOD) begin #1; i = i + 1; end
        if(dmx_pat !== pat) begin
            $display("[FAIL] lower's track_pat=0b%05b, expected 0b%05b", dmx_pat, pat);
            errors = errors + 1;
        end
        else
            $display("[ OK ] five sensors 0b%05b reached the lower board", pat);
    end
endtask

task send_byte;
    input [7:0] data;
    integer     b;
    begin
        inj_level = 1'b0;
        #(BIT_PERIOD);
        for(b = 0; b < 8; b = b + 1) begin
            inj_level = data[b];
            #(BIT_PERIOD);
        end
        inj_level = 1'b1;
        #(BIT_PERIOD);
    end
endtask

initial begin
    errors   = 0;
    rst_n    = 1'b0;
    tb_cmd   = 8'd0;
    tb_upd   = 1'b0;
    tb_track = 5'd0;
    inj_en   = 1'b0;
    inj_level= 1'b1;
    u0 = 0; l0 = 0; mc0 = 0; mt0 = 0; m2c0 = 0; m2t0 = 0; d0 = 0;
    repeat(10) @(posedge clk);
    rst_n = 1'b1;
    repeat(10) @(posedge clk);

    $display("==================================================");
    $display(" tb_board_link: CLK_FREQ=%0d  UART_BPS=%0d", CLK_FREQ, UART_BPS);
    $display("   upper(ECHO_EN=0) <--cross--> lower(ECHO_EN=1)");
    $display("   byte: bit7=0 command / bit7=1 five line sensors");
    $display("==================================================");

    $display("--- 1) upper sends command 1 ---");
    mark; send_cmd(8'd1);
    wait_mon(8'd1);
    wait_lo (8'd1);
    wait_up (8'd1);
    if(up_linkerr !== 1'b0) begin
        $display("[FAIL] upper link_err went high on a clean frame");
        errors = errors + 1;
    end
    else
        $display("[ OK ] upper link_err stayed low");

    $display("--- 2) upper sends command 5 (CARGO) ---");
    mark; send_cmd(8'd5);
    wait_mon(8'd5);
    wait_lo (8'd5);
    wait_up (8'd5);

    $display("--- 3) two commands back to back while still sending ---");
    mark;
    send_cmd(8'd1);
    send_cmd(8'd4);
    i = 0;
    while(((m1_cmd_cnt < (mc0 + 2)) || (up_pcnt < (u0 + 2))) && i < 400 * BIT_PERIOD) begin
        #1;
        i = i + 1;
    end
    if((m1_cmd_cnt - mc0) != 2) begin
        $display("[FAIL] wire carried %0d command frames, expected 2", m1_cmd_cnt - mc0);
        errors = errors + 1;
    end
    else if(m1_cmd !== 8'd4) begin
        $display("[FAIL] last command frame on the wire was 0x%02h, expected 0x04", m1_cmd);
        errors = errors + 1;
    end
    else
        $display("[ OK ] both commands went out, last one 0x04");
    if(((dmx_cmd_cnt - 0) < 2) || (lo_pcmd !== 8'd4)) begin
        $display("[FAIL] lower got %0d commands, last byte=0x%02h", dmx_cmd_cnt, lo_pcmd);
        errors = errors + 1;
    end
    else
        $display("[ OK ] lower saw both commands, last one 0x04");
    if(((up_pcnt - u0) != 2) || (up_pcmd !== 8'd4)) begin
        $display("[FAIL] upper got %0d echoes, last byte=0x%02h", up_pcnt - u0, up_pcmd);
        errors = errors + 1;
    end
    else
        $display("[ OK ] upper got both echoes, last one 0x04");

    $display("--- 4) tracking: five sensors forwarded to the lower board ---");
    mark;
    set_track_wait(5'b10000);
    set_track_wait(5'b00100);
    set_track_wait(5'b00011);
    set_track_wait(5'b10101);
    if((m1_trk_cnt - mt0) == 0) begin
        $display("[FAIL] no tracking frame appeared on the wire");
        errors = errors + 1;
    end
    else
        $display("[ OK ] wire carried %0d tracking frames", m1_trk_cnt - mt0);
    if(m1_trk !== 5'b10101) begin
        $display("[FAIL] last tracking frame on the wire = 0b%05b, expected 0b10101", m1_trk);
        errors = errors + 1;
    end
    else
        $display("[ OK ] last tracking frame on the wire = 0b10101");
    if(dmx_upd_cnt == d0) begin
        $display("[FAIL] the lower board never saw a tracking update");
        errors = errors + 1;
    end
    else
        $display("[ OK ] lower board saw %0d tracking updates", dmx_upd_cnt - d0);

    $display("--- 5) a command frame must not disturb the held pattern ---");
    mark;
    send_cmd(8'd2);
    i = 0;
    while((m1_cmd_cnt == mc0) && i < 400 * BIT_PERIOD) begin #1; i = i + 1; end
    #(3 * TRK_MS * CLK_PERIOD);
    if(dmx_pat !== 5'b10101) begin
        $display("[FAIL] track_pat changed to 0b%05b after a command frame", dmx_pat);
        errors = errors + 1;
    end
    else
        $display("[ OK ] track_pat stayed 0b10101 through a command frame");

    $display("--- 6) only commands are echoed, tracking frames are not ---");
    if(m2_trk_cnt != 0) begin
        $display("[FAIL] the lower board echoed %0d tracking frames", m2_trk_cnt);
        errors = errors + 1;
    end
    else
        $display("[ OK ] no tracking frame was echoed back");
    if(up_pcnt == u0) begin
        $display("[FAIL] the upper board saw no echoes at all");
        errors = errors + 1;
    end
    else
        $display("[ OK ] lower echoed %0d command frames", m2_cmd_cnt);

    $display("--- 7) broken frame injected into the upper board's RX line ---");
    inj_en    = 1'b1;
    inj_level = 1'b1;
    #(20 * BIT_PERIOD);
    send_byte(8'hAA);
    send_byte(8'h55);
    send_byte(8'h03);
    send_byte(8'h55);
    send_byte(8'h00);
    #(10 * BIT_PERIOD);
    if(up_linkerr !== 1'b1) begin
        $display("[FAIL] upper link_err did not latch on a broken frame");
        errors = errors + 1;
    end
    else
        $display("[ OK ] upper link_err latched high on the broken frame");
    if(lo_linkerr !== 1'b0) begin
        $display("[FAIL] lower link_err latched too (errors must not leak over)");
        errors = errors + 1;
    end
    else
        $display("[ OK ] lower link_err stayed low");
    inj_en = 1'b0;
    #(20 * BIT_PERIOD);

    $display("--- 8) recovery: a good command after the error ---");
    mark; send_cmd(8'd2);
    wait_mon(8'd2);
    wait_lo (8'd2);
    wait_up (8'd2);

    $display("--- 9) the lower board never talks on its own ---");
    m2c0 = m2_cmd_cnt; m2t0 = m2_trk_cnt;
    #(20 * TRK_MS * CLK_PERIOD);
    if((m2_cmd_cnt != m2c0) || (m2_trk_cnt != m2t0)) begin
        $display("[FAIL] lower board sent %0d extra frames on its own",
                 (m2_cmd_cnt - m2c0) + (m2_trk_cnt - m2t0));
        errors = errors + 1;
    end
    else
        $display("[ OK ] lower TX stayed quiet (%0d tracking frames still flowing up)",
                 m1_trk_cnt);

    $display("==================================================");
    if(errors == 0)
        $display(" RESULT: all passed (errors=0)");
    else
        $display(" RESULT: %0d checks failed", errors);
    $display("==================================================");
    $finish;
end

endmodule
