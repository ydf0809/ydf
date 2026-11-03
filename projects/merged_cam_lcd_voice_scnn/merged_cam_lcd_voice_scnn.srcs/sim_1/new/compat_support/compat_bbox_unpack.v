`timescale 1ns / 1ps

module compat_bbox_unpack #(
    parameter integer CLK_FREQ = 33_333_333
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  peer_cmd,
    input  wire        peer_valid,

    output reg         bbox_valid,
    output reg  [9:0]  bbox_x,
    output reg  [9:0]  bbox_y,
    output reg  [9:0]  bbox_w,
    output reg  [9:0]  bbox_h,
    output reg         bbox_label,
    output reg         bbox_frame_tgl,
    output wire        bbox_rx_busy
);

    localparam [7:0]  CMD_START = 8'h40;
    localparam integer AGE_MAX  = CLK_FREQ / 10;
    localparam integer BUSY_MAX = CLK_FREQ / 100;

    reg [7:0] buf0, buf1, buf2, buf3, buf4;
    reg [7:0] buf5, buf6, buf7, buf8;
    reg [3:0] idx;
    reg       busy;
    reg [31:0] age_cnt;
    reg [31:0] busy_cnt;

    wire [7:0] checksum =
        buf0 ^ buf1 ^ buf2 ^ buf3 ^ buf4 ^
        buf5 ^ buf6 ^ buf7 ^ buf8;

    assign bbox_rx_busy = busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buf0 <= 8'd0; buf1 <= 8'd0; buf2 <= 8'd0; buf3 <= 8'd0;
            buf4 <= 8'd0; buf5 <= 8'd0; buf6 <= 8'd0; buf7 <= 8'd0;
            buf8 <= 8'd0;
            idx        <= 4'd0;
            busy       <= 1'b0;
            age_cnt    <= 32'd0;
            busy_cnt   <= 32'd0;
            bbox_valid <= 1'b0;
            bbox_x     <= 10'd0;
            bbox_y     <= 10'd0;
            bbox_w     <= 10'd0;
            bbox_h     <= 10'd0;
            bbox_label <= 1'b0;
            bbox_frame_tgl <= 1'b0;
        end else begin

            if (age_cnt < AGE_MAX)
                age_cnt <= age_cnt + 1'b1;
            else
                bbox_valid <= 1'b0;

            if (busy) begin
                if (busy_cnt < BUSY_MAX)
                    busy_cnt <= busy_cnt + 1'b1;
                else begin
                    busy     <= 1'b0;
                    busy_cnt <= 32'd0;
                end
            end

            if (peer_valid) begin
                busy_cnt <= 32'd0;

                if (!busy && (peer_cmd == CMD_START)) begin
                    idx  <= 4'd0;
                    busy <= 1'b1;
                end else if (busy) begin
                    case (idx)
                        4'd0: buf0 <= peer_cmd;
                        4'd1: buf1 <= peer_cmd;
                        4'd2: buf2 <= peer_cmd;
                        4'd3: buf3 <= peer_cmd;
                        4'd4: buf4 <= peer_cmd;
                        4'd5: buf5 <= peer_cmd;
                        4'd6: buf6 <= peer_cmd;
                        4'd7: buf7 <= peer_cmd;
                        4'd8: buf8 <= peer_cmd;
                        default: begin

                            busy <= 1'b0;
                            if (peer_cmd == checksum) begin
                                bbox_x     <= {buf1[1:0], buf0};
                                bbox_y     <= {buf3[1:0], buf2};
                                bbox_w     <= {buf5[1:0], buf4};
                                bbox_h     <= {buf7[1:0], buf6};
                                bbox_valid <= buf8[0];
                                bbox_label <= buf8[1];
                                bbox_frame_tgl <= ~bbox_frame_tgl;
                                age_cnt    <= 32'd0;
                            end else begin
                                bbox_valid <= 1'b0;
                            end
                        end
                    endcase

                    if (idx != 4'd9)
                        idx <= idx + 1'b1;
                end
            end
        end
    end

endmodule
