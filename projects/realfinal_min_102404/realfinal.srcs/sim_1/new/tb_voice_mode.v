//----------------------------------------------------------------------------------------
// File name:           tb_voice_mode
// Descriptions:        voice command -> working mode, on the lower board
//
// DUT chain: board_link (ECHO_EN=1) + link_demux + voice_mode_select
// Real 5-byte frames are bit-banged onto the link input, exactly like the upper board sends.
//
// Checked here (the DIP switch is gone: the mode comes from the link only):
//   1. no command received yet -> everything OFF (idle until told what to do)
//   2. frame AA 55 01 55 AA (TRACK)  -> tracking ON
//   3. frame AA 55 05 55 AA (CARGO)  -> arm ON, tracking OFF
//   4. frame AA 55 02 55 AA (FOLLOW) -> tracking OFF, vision follow ON
//   5. frame AA 55 03 55 AA (DEFENSE)-> arm tracking ON, chassis OFF
//   6. frame AA 55 04 55 AA (HOLD)   -> everything OFF
//   7. frame AA 55 01 55 AA again    -> tracking ON again
//   8. a tracking status frame (0x85, bit7=1) must NOT change the mode
//   9. board reset -> mode cleared, everything OFF again
//
// How to run: scripts\sim_voice_mode.bat
// CLK_FREQ / UART_BPS below are placeholders; the sim script substitutes the real values
// into a copy and compiles that, so nothing is passed on the command line.
//----------------------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_voice_mode;

//parameter define
//placeholders -- the simulation script rewrites these two lines
parameter CLK_FREQ = 33333333;
parameter UART_BPS = 115200;

localparam CLK_PERIOD = 1000000000 / CLK_FREQ;
localparam BIT_PERIOD = 1000000000 / UART_BPS;

//reg define
reg        clk      ;
reg        rst_n    ;
reg        frames   ;
integer    errors   ;

//wire define
wire [7:0] peer_cmd ;
wire       peer_valid;
wire       link_err ;
wire [4:0] track_pat;
wire       track_upd;
wire       cmd_valid;
wire       xunbi_en ;
wire       vision_en;
wire       defense_en;
wire       arm_en   ;

//*****************************************************
//**                    DUT
//*****************************************************
board_link #(
    .CLK_FREQ   (CLK_FREQ ),
    .UART_BPS   (UART_BPS ),
    .ECHO_EN    (1'b1     ))
    u_lower(
    .clk            (clk       ),
    .rst_n          (rst_n     ),
    .link_rx        (frames    ),
    .link_tx        (          ),
    .local_cmd      (8'd0      ),
    .local_send     (1'b0      ),
    .peer_cmd       (peer_cmd  ),
    .peer_valid     (peer_valid),
    .link_err       (link_err  )
    );

link_demux #(
    .CLK_FREQ   (CLK_FREQ),
    .TIMEOUT_MS (2        ))     // short watchdog so the bench stays fast
    u_demux(
    .clk            (clk       ),
    .rst_n          (rst_n     ),
    .peer_cmd       (peer_cmd  ),
    .peer_valid     (peer_valid),
    .bbox_busy      (1'b0      ),
    .track_pat      (track_pat ),
    .track_upd      (track_upd ),
    .cmd_valid      (cmd_valid )
    );

voice_mode_select u_mode(
    .clk            (clk       ),
    .rst_n          (rst_n     ),
    .cmd            (peer_cmd  ),
    .cmd_valid      (cmd_valid ),
    .xunbi_en       (xunbi_en  ),
    .vision_en      (vision_en ),
    .defense_en     (defense_en),
    .arm_en         (arm_en    )
    );

initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

//*****************************************************
//**      helpers
//*****************************************************
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
        #(5 * BIT_PERIOD);
    end
endtask

task check4;
    input         ex_x;
    input         ex_v;
    input         ex_d;
    input         ex_a;
    input [255:0] what;
    begin
        if((xunbi_en !== ex_x) || (vision_en !== ex_v) ||
           (defense_en !== ex_d) || (arm_en !== ex_a)) begin
            $display("[FAIL] %0s: xunbi=%b vision=%b defense=%b arm=%b, expected %b/%b/%b/%b",
                     what, xunbi_en, vision_en, defense_en, arm_en,
                     ex_x, ex_v, ex_d, ex_a);
            errors = errors + 1;
        end
        else
            $display("[ OK ] %0s: xunbi=%b vision=%b defense=%b arm=%b",
                     what, xunbi_en, vision_en, defense_en, arm_en);
    end
endtask

//*****************************************************
//**      main
//*****************************************************
initial begin
    errors = 0;
    rst_n  = 1'b0;
    frames = 1'b1;
    repeat(10) @(posedge clk);
    rst_n = 1'b1;
    repeat(10) @(posedge clk);

    $display("==================================================");
    $display(" tb_voice_mode: CLK_FREQ=%0d  UART_BPS=%0d", CLK_FREQ, UART_BPS);
    $display("   voice command picks the mode on the lower board");
    $display("==================================================");

    //--------------------------------------------------
    $display("--- 1) no command yet: everything OFF (idle) ---");
    check4(1'b0, 1'b0, 1'b0, 1'b0, "no command -> all off");

    //--------------------------------------------------
    $display("--- 2) say TRACK (01) ---");
    send_frame(8'hAA, 8'h55, 8'h01, 8'h55, 8'hAA);
    #(3 * BIT_PERIOD);
    check4(1'b1, 1'b0, 1'b0, 1'b0, "cmd=01 -> tracking on");

    //--------------------------------------------------
    $display("--- 3) say CARGO (05) ---");
    send_frame(8'hAA, 8'h55, 8'h05, 8'h55, 8'hAA);
    #(3 * BIT_PERIOD);
    check4(1'b0, 1'b0, 1'b0, 1'b1, "cmd=05 -> cargo arm on");

    //--------------------------------------------------
    $display("--- 4) say FOLLOW (02): tracking OFF, vision ON ---");
    send_frame(8'hAA, 8'h55, 8'h02, 8'h55, 8'hAA);
    #(3 * BIT_PERIOD);
    check4(1'b0, 1'b1, 1'b0, 1'b0, "cmd=02 -> vision follow on");

    //--------------------------------------------------
    $display("--- 5) say DEFENSE (03): arm tracking ON, chassis OFF ---");
    send_frame(8'hAA, 8'h55, 8'h03, 8'h55, 8'hAA);
    #(3 * BIT_PERIOD);
    check4(1'b0, 1'b0, 1'b1, 1'b0, "cmd=03 -> arm defense tracking");

    //--------------------------------------------------
    $display("--- 6) say HOLD (04) ---");
    send_frame(8'hAA, 8'h55, 8'h04, 8'h55, 8'hAA);
    #(3 * BIT_PERIOD);
    check4(1'b0, 1'b0, 1'b0, 1'b0, "cmd=04 -> all off");

    //--------------------------------------------------
    $display("--- 7) say TRACK (01) again ---");
    send_frame(8'hAA, 8'h55, 8'h01, 8'h55, 8'hAA);
    #(3 * BIT_PERIOD);
    check4(1'b1, 1'b0, 1'b0, 1'b0, "cmd=01 again -> tracking on");

    //--------------------------------------------------
    $display("--- 8) a tracking status frame (0x85) must not change the mode ---");
    send_frame(8'hAA, 8'h55, 8'h85, 8'h55, 8'hAA);
    #(3 * BIT_PERIOD);
    check4(1'b1, 1'b0, 1'b0, 1'b0, "tracking frame -> mode unchanged");
    if(track_pat !== 5'b00101) begin
        $display("[FAIL] track_pat=0b%05b, expected 0b00101", track_pat);
        errors = errors + 1;
    end
    else
        $display("[ OK ] the same frame updated track_pat to 0b00101");

    //--------------------------------------------------
    $display("--- 8b) link watchdog: no tracking frame -> line lost -> pattern 0 ---");
    #(5000000);                       // more than the 2 ms watchdog
    if(track_pat !== 5'd0) begin
        $display("[FAIL] track_pat=0b%05b after the link went quiet (expected 0b00000)", track_pat);
        errors = errors + 1;
    end
    else
        $display("[ OK ] watchdog forced track_pat to 0 (wheels will stop)");

    //--------------------------------------------------
    $display("--- 9) board reset: the mode is cleared ---");
    rst_n = 1'b0;
    repeat(10) @(posedge clk);
    rst_n = 1'b1;
    repeat(10) @(posedge clk);
    check4(1'b0, 1'b0, 1'b0, 1'b0, "after reset -> all off");

    $display("==================================================");
    if(errors == 0)
        $display(" RESULT: all passed (errors=0)");
    else
        $display(" RESULT: %0d checks failed", errors);
    $display("==================================================");
    $finish;
end

endmodule
