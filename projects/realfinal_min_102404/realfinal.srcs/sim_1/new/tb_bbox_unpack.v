`timescale 1ns / 1ps

module tb_bbox_unpack;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #15 clk = ~clk;

    reg [7:0] peer_cmd = 8'd0;
    reg       peer_valid = 1'b0;

    wire       bbox_valid;
    wire [9:0] bbox_x;
    wire [9:0] bbox_y;
    wire [9:0] bbox_w;
    wire [9:0] bbox_h;
    wire       bbox_label;
    wire       bbox_tgl;
    wire       bbox_busy;

    integer errors = 0;

    bbox_unpack #(
        .CLK_FREQ (33_333_333)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .peer_cmd        (peer_cmd),
        .peer_valid      (peer_valid),
        .bbox_valid      (bbox_valid),
        .bbox_x          (bbox_x),
        .bbox_y          (bbox_y),
        .bbox_w          (bbox_w),
        .bbox_h          (bbox_h),
        .bbox_label      (bbox_label),
        .bbox_frame_tgl  (bbox_tgl),
        .bbox_rx_busy    (bbox_busy)
    );

    task send_byte;
        input [7:0] value;
        begin
            @(negedge clk);
            peer_cmd = value;
            peer_valid = 1'b1;
            @(negedge clk);
            peer_valid = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        send_byte(8'h40);
        send_byte(8'h0B);
        send_byte(8'h02);
        send_byte(8'h85);
        send_byte(8'h01);
        send_byte(8'h32);
        send_byte(8'h00);
        send_byte(8'h3C);
        send_byte(8'h00);
        send_byte(8'h01);
        send_byte(8'h82);

        repeat (3) @(posedge clk);
        if (bbox_x !== 10'd523 || bbox_y !== 10'd389 ||
            bbox_w !== 10'd50  || bbox_h !== 10'd60  ||
            bbox_valid !== 1'b1) begin
            $display("[FAIL] unpacked x=%0d y=%0d w=%0d h=%0d valid=%b",
                     bbox_x, bbox_y, bbox_w, bbox_h, bbox_valid);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("RESULT: all passed (errors=0)");
        else
            $display("RESULT: %0d checks failed", errors);
        $finish;
    end

endmodule
