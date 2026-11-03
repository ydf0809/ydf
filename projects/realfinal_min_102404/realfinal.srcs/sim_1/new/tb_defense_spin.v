`timescale 1ns / 1ps

module tb_defense_spin;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg defense_en = 1'b0;
    reg target_valid = 1'b0;
    reg [10:0] target_cx = 11'd300;
    reg [15:0] yaw_pos = 16'd500;

    wire spin_active;
    wire signed [7:0] m1, m2, m3, m4;
    wire cmd_update;

    always #15 clk = ~clk;

    defense_spin #(
        .CLK_HZ(100_000),
        .IMG_W(600),
        .CENTER_X(300),
        .BOX_HALF_W(64),
        .EDGE_PX(30),
        .YAW_MIN(100),
        .YAW_MAX(850),
        .CONFIRM_MS(300),
        .MIN_SPIN_MS(1000),
        .MAX_SPIN_MS(2000),
        .CENTER_TOL_PX(60),
        .REFRESH_MS(100),
        .SPIN_SPEED(8'sd18),
        .RIGHT_SIGN(1)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .defense_en(defense_en),
        .target_valid(target_valid),
        .target_cx(target_cx),
        .yaw_pos(yaw_pos),
        .spin_active(spin_active),
        .m1(m1), .m2(m2), .m3(m3), .m4(m4),
        .cmd_update(cmd_update)
    );

    localparam integer T1MS = 100;

    integer spin_cycles;
    reg     spin_d;

    always @(posedge clk) begin
        spin_d <= spin_active;
        if (!spin_d && spin_active) begin
            spin_cycles <= 0;
            $display("TRACE spin start at %0t, yaw=%0d cx=%0d", $time, yaw_pos, target_cx);
        end else if (spin_d && spin_active) begin
            spin_cycles <= spin_cycles + 1;
        end else if (spin_d && !spin_active) begin
            $display("TRACE spin stop at %0t after %0d cycles", $time, spin_cycles);
        end
    end

    task wait_ms(input integer ms);
        integer i;
        begin
            for (i = 0; i < ms * T1MS; i = i + 1) @(posedge clk);
        end
    endtask

    task fail(input [511:0] msg);
        begin
            $display("FAIL: %0s", msg);
            $finish;
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        defense_en   = 1'b1;
        target_valid = 1'b1;
        yaw_pos      = 16'd500;
        target_cx    = 11'd535;
        wait_ms(600);
        if (spin_active) fail("spun although servo 6 was not at its limit");

        yaw_pos   = 16'd850;
        target_cx = 11'd300;
        wait_ms(600);
        if (spin_active) fail("spun although the box was centred");

        target_cx = 11'd535;
        wait (spin_active);
        if (m1 !== 8'sd18 || m2 !== -8'sd18 || m3 !== 8'sd18 || m4 !== -8'sd18)
            fail("right-border spin has the wrong motor signs");
        wait_ms(400);
        if (!spin_active) fail("spin stopped before the 1s minimum");
        target_cx = 11'd300;
        wait (!spin_active);
        if (spin_cycles < 100*1000 - 10)
            fail("spin stopped before the 1s minimum (cycle count)");
        $display("right spin stopped after %0d cycles (~%0d ms)",
                 spin_cycles, spin_cycles / 100);

        wait_ms(50);
        yaw_pos   = 16'd100;
        target_cx = 11'd63;
        wait (spin_active);
        if (m1 !== -8'sd18 || m2 !== 8'sd18 || m3 !== -8'sd18 || m4 !== 8'sd18)
            fail("left-border spin has the wrong motor signs");
        wait (!spin_active);
        if (spin_cycles < 200*1000 - 200 || spin_cycles > 200*1000 + 500)
            fail("spin did not run the full 2s window");
        $display("left spin ran %0d cycles (~%0d ms)", spin_cycles, spin_cycles / 100);

        wait_ms(50);
        target_cx = 11'd535;
        yaw_pos   = 16'd850;
        wait (spin_active);
        wait_ms(200);
        defense_en = 1'b0;
        @(posedge clk); @(posedge clk);
        if (spin_active) fail("spin did not stop when air-defence mode was left");

        $display("DEFENSE_SPIN_PASS");
        $finish;
    end

    initial begin
        repeat (20_000_000) @(posedge clk);
        $display("FAIL: timeout");
        $finish;
    end

endmodule
