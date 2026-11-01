`timescale 1ns / 1ps

// Upper-board link scheduler.
//
// One UART frame carries one byte. This module serializes the three producers
// that share that link:
//   1. mode command (AA 55 cmd 55 AA),
//   2. a complete 11-frame bbox burst,
//   3. periodic five-sensor status (bit7=1).
//
// A bbox burst is kept contiguous on the wire. link_busy is the transmitter's
// real busy signal; no byte is requested until the previous UART frame is over.
module upper_link_send #(
    parameter integer CLK_FREQ        = 33_333_333,
    parameter integer TRACK_PERIOD_US = 1000
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        track_l2,
    input  wire        track_l1,
    input  wire        track_m,
    input  wire        track_r1,
    input  wire        track_r2,

    input  wire        mode_upd,
    input  wire [7:0]  mode_cmd,

    input  wire [9:0]  bbox_x,
    input  wire [9:0]  bbox_y,
    input  wire [9:0]  bbox_w,
    input  wire [9:0]  bbox_h,
    input  wire        bbox_valid,
    input  wire        bbox_tgl,

    input  wire        link_busy,

    output reg  [7:0]  local_cmd,
    output reg         local_send,
    output wire        bbox_busy
);

    localparam integer TRACK_TICKS = (CLK_FREQ / 1_000_000) * TRACK_PERIOD_US;

    reg [4:0] track_d0, track_d1;
    reg [15:0] track_cnt;

    (* ASYNC_REG = "TRUE" *) reg bbox_tgl_d0;
    (* ASYNC_REG = "TRUE" *) reg bbox_tgl_d1;
    wire bbox_tgl_edge = bbox_tgl_d0 ^ bbox_tgl_d1;

    reg [9:0] cap_x, cap_y, cap_w, cap_h;
    reg       cap_valid;
    reg       bbox_pending;

    reg [9:0] burst_x, burst_y, burst_w, burst_h;
    reg       burst_valid;
    reg [3:0] burst_idx;
    reg       burst_active;

    reg       cmd_pending;
    reg [4:0] cmd_pending_data;

    reg       send_wait;
    reg       seen_busy;

    assign bbox_busy = burst_active;

    function [7:0] make_bbox_byte;
        input [3:0] idx;
        input [9:0] x;
        input [9:0] y;
        input [9:0] w;
        input [9:0] h;
        input       valid;
        reg [7:0] d0, d1, d2, d3, d4, d5, d6, d7, d8;
        begin
            d0 = x[7:0];
            d1 = {6'b0, x[9:8]};
            d2 = y[7:0];
            d3 = {6'b0, y[9:8]};
            d4 = w[7:0];
            d5 = {6'b0, w[9:8]};
            d6 = h[7:0];
            d7 = {6'b0, h[9:8]};
            d8 = {6'b0, 1'b0, valid};

            case (idx)
                4'd0:  make_bbox_byte = 8'h40;
                4'd1:  make_bbox_byte = d0;
                4'd2:  make_bbox_byte = d1;
                4'd3:  make_bbox_byte = d2;
                4'd4:  make_bbox_byte = d3;
                4'd5:  make_bbox_byte = d4;
                4'd6:  make_bbox_byte = d5;
                4'd7:  make_bbox_byte = d6;
                4'd8:  make_bbox_byte = d7;
                4'd9:  make_bbox_byte = d8;
                4'd10: make_bbox_byte = d0 ^ d1 ^ d2 ^ d3 ^ d4 ^
                                               d5 ^ d6 ^ d7 ^ d8;
                default: make_bbox_byte = 8'h00;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            track_d0 <= 5'd0;
            track_d1 <= 5'd0;
            track_cnt <= 16'd0;

            bbox_tgl_d0 <= 1'b0;
            bbox_tgl_d1 <= 1'b0;
            cap_x <= 10'd0;
            cap_y <= 10'd0;
            cap_w <= 10'd0;
            cap_h <= 10'd0;
            cap_valid <= 1'b0;
            bbox_pending <= 1'b0;

            burst_x <= 10'd0;
            burst_y <= 10'd0;
            burst_w <= 10'd0;
            burst_h <= 10'd0;
            burst_valid <= 1'b0;
            burst_idx <= 4'd0;
            burst_active <= 1'b0;

            cmd_pending <= 1'b0;
            cmd_pending_data <= 5'd0;
            send_wait <= 1'b0;
            seen_busy <= 1'b0;
            local_cmd <= 8'd0;
            local_send <= 1'b0;
        end else begin
            local_send <= 1'b0;

            track_d0 <= {track_l2, track_l1, track_m, track_r1, track_r2};
            track_d1 <= track_d0;

            bbox_tgl_d0 <= bbox_tgl;
            bbox_tgl_d1 <= bbox_tgl_d0;

            if (mode_upd) begin
                cmd_pending <= 1'b1;
                cmd_pending_data <= mode_cmd[4:0];
            end

            if (bbox_tgl_edge) begin
                cap_x <= bbox_x;
                cap_y <= bbox_y;
                cap_w <= bbox_w;
                cap_h <= bbox_h;
                cap_valid <= bbox_valid;
                bbox_pending <= 1'b1;
            end

            if (track_cnt >= TRACK_TICKS - 1)
                track_cnt <= 16'd0;
            else
                track_cnt <= track_cnt + 1'b1;

            if (send_wait) begin
                if (link_busy)
                    seen_busy <= 1'b1;

                if (seen_busy && !link_busy) begin
                    send_wait <= 1'b0;
                    seen_busy <= 1'b0;

                    if (burst_active) begin
                        if (burst_idx == 4'd10)
                            burst_active <= 1'b0;
                        else
                            burst_idx <= burst_idx + 1'b1;
                    end
                end
            end else if (!link_busy) begin
                if (burst_active) begin
                    local_cmd  <= make_bbox_byte(burst_idx, burst_x, burst_y,
                                                 burst_w, burst_h, burst_valid);
                    local_send <= 1'b1;
                    send_wait  <= 1'b1;
                    seen_busy  <= 1'b0;
                end else if (cmd_pending) begin
                    local_cmd  <= {3'b0, cmd_pending_data};
                    local_send <= 1'b1;
                    cmd_pending <= 1'b0;
                    send_wait  <= 1'b1;
                    seen_busy  <= 1'b0;
                    track_cnt  <= 16'd0;
                end else if (bbox_pending) begin
                    burst_x <= cap_x;
                    burst_y <= cap_y;
                    burst_w <= cap_w;
                    burst_h <= cap_h;
                    burst_valid <= cap_valid;
                    burst_idx <= 4'd0;
                    burst_active <= 1'b1;
                    bbox_pending <= 1'b0;

                    local_cmd  <= make_bbox_byte(4'd0, cap_x, cap_y,
                                                 cap_w, cap_h, cap_valid);
                    local_send <= 1'b1;
                    send_wait  <= 1'b1;
                    seen_busy  <= 1'b0;
                end else if (track_cnt >= TRACK_TICKS - 1) begin
                    local_cmd  <= {1'b1, 2'b00, ~track_d1};
                    local_send <= 1'b1;
                    track_cnt  <= 16'd0;
                    send_wait  <= 1'b1;
                    seen_busy  <= 1'b0;
                end
            end
        end
    end

endmodule
