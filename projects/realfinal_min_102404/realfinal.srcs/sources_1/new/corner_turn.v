`timescale 1ns / 1ps

module corner_turn #(
    parameter integer      CLK_FREQ_HZ  = 33_333_333,
    parameter integer      FORWARD_MS   = 1000,
    parameter integer      SPIN_MS      = 700,
    parameter integer      MIN_SPIN_MS  = 250,
    parameter integer      TIMEOUT_MS   = 2000,
    parameter integer      COOLDOWN_MS  = 500,
    parameter integer      CONFIRM_MS   = 3,
    parameter signed [7:0] FORWARD_SPEED= 8'sd16,
    parameter signed [7:0] SPIN_SPEED   = 8'sd20,
    parameter              STOP_ON_LINE = 1
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              run_en,
    input  wire [4:0]        pat,
    input  wire              line_valid,
    input  wire signed [7:0] pid_left,
    input  wire signed [7:0] pid_right,
    output reg  signed [7:0] out_left,
    output reg  signed [7:0] out_right,
    output reg               busy
);

    localparam integer CYCLES_PER_MS = CLK_FREQ_HZ / 1000;

    localparam S_RUN  = 2'd0;
    localparam S_FWD  = 2'd1;
    localparam S_SPIN = 2'd2;
    localparam S_COOL = 2'd3;

    reg [1:0]  state;
    reg [15:0] ms_cnt;
    reg [15:0] t_ms;
    reg [2:0]  det_cnt;
    reg        dir_left;
    reg        outer_seen_off;

    wire left3  = pat[4] & pat[3] & pat[2] & ~pat[1] & ~pat[0];
    wire right3 = pat[0] & pat[1] & pat[2] & ~pat[3] & ~pat[4];
    wire pattern_valid = (pat != 5'b00000) && (pat != 5'b11111);
    wire turn_outer = dir_left ? pat[4] : pat[0];
    wire turn_outer_off = dir_left ? ~pat[4] : ~pat[0];

    wire tick = (ms_cnt >= CYCLES_PER_MS - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_RUN;
            ms_cnt   <= 16'd0;
            t_ms     <= 16'd0;
            det_cnt  <= 3'd0;
            dir_left <= 1'b0;
            outer_seen_off <= 1'b0;
        end else if (!run_en) begin
            state    <= S_RUN;
            ms_cnt   <= 16'd0;
            t_ms     <= 16'd0;
            det_cnt  <= 3'd0;
            outer_seen_off <= 1'b0;
        end else begin
            ms_cnt <= tick ? 16'd0 : ms_cnt + 1'b1;

            if (tick) begin
                t_ms <= t_ms + 1'b1;

                case (state)
                    S_RUN: begin
                        if (left3 || right3) begin
                            if (det_cnt >= CONFIRM_MS - 1) begin
                                state    <= S_FWD;
                                t_ms     <= 16'd0;
                                det_cnt  <= 3'd0;
                                dir_left <= left3;
                                outer_seen_off <= 1'b0;
                            end else begin
                                det_cnt <= det_cnt + 1'b1;
                            end
                        end else begin
                            det_cnt <= 3'd0;
                        end
                    end

                    S_FWD: begin
                        if (t_ms >= FORWARD_MS - 1) begin
                            state    <= S_SPIN;
                            t_ms     <= 16'd0;
                            outer_seen_off <= 1'b0;
                        end
                    end

                    S_SPIN: begin

                        if (turn_outer_off) outer_seen_off <= 1'b1;

                        if (STOP_ON_LINE) begin
                            if (outer_seen_off && (t_ms >= MIN_SPIN_MS - 1) &&
                                turn_outer && line_valid && pattern_valid) begin
                                state    <= S_COOL;
                                t_ms     <= 16'd0;
                            end

                            if (t_ms >= TIMEOUT_MS - 1) begin
                                state    <= S_COOL;
                                t_ms     <= 16'd0;
                            end
                        end else begin
                            if (t_ms >= SPIN_MS - 1) begin
                                state <= S_COOL;
                                t_ms  <= 16'd0;
                            end
                        end
                    end

                    S_COOL: begin
                        if (t_ms >= COOLDOWN_MS - 1) begin
                            state <= S_RUN;
                            t_ms  <= 16'd0;
                        end
                    end

                    default: state <= S_RUN;
                endcase
            end
        end
    end

    always @(*) begin
        case (state)
            S_FWD: begin
                out_left  = FORWARD_SPEED;
                out_right = FORWARD_SPEED;
            end
            S_SPIN: begin
                if (dir_left) begin
                    out_left  = -SPIN_SPEED;
                    out_right =  SPIN_SPEED;
                end else begin
                    out_left  =  SPIN_SPEED;
                    out_right = -SPIN_SPEED;
                end
            end
            default: begin
                out_left  = pid_left;
                out_right = pid_right;
            end
        endcase
    end

    always @(*) begin
        busy = (state == S_FWD) || (state == S_SPIN);
    end

endmodule
