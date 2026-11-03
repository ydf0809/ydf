`timescale 1ns / 1ps

module compat_color_track(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        cmos_vsync,
    input  wire        cmos_valid,
    input  wire [15:0] cmos_data,

    input  wire        lock_sw,

    output reg  [10:0] target_x,
    output reg  [10:0] target_y,
    output reg  [10:0] target_w,
    output reg  [10:0] target_h
);

    wire hsv_valid;
    wire [8:0] hsv_h;
    wire [7:0] hsv_s;
    wire [7:0] hsv_v;

    compat_rgb2hsv u_rgb2hsv(
        .clk(clk),         .rst_n(rst_n),
        .rgb_valid(cmos_valid), .rgb565_in(cmos_data),
        .hsv_valid(hsv_valid),  .hsv_h(hsv_h),
        .hsv_s(hsv_s),          .hsv_v(hsv_v)
    );

    // Match frame-boundary timing to the 18-stage HSV pipeline.
    reg [15:0] vsync_align;
    reg vsync_d1, vsync_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin vsync_align <= 0; vsync_d1 <= 0; vsync_d2 <= 0; end
        else begin
            vsync_align <= {vsync_align[14:0],cmos_vsync};
            vsync_d1 <= vsync_align[15]; vsync_d2 <= vsync_d1;
        end
    end
    wire vsync_pos = vsync_d1 & ~vsync_d2;

    reg [9:0] img_x, img_y;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            img_x <= 0; img_y <= 0;
        end else if(vsync_pos) begin
            img_x <= 0; img_y <= 0;
        end else if(hsv_valid) begin
            if (img_x == 10'd299) begin img_x <= 0; img_y <= img_y + 1'b1; end
            else img_x <= img_x + 1'b1;
        end
    end

    reg sw2_d0, sw2_d1;
    always @(posedge clk) begin sw2_d0 <= lock_sw; sw2_d1 <= sw2_d0; end
    wire lock_trigger = sw2_d0 & ~sw2_d1;

    reg [1:0] state;
    localparam IDLE = 0, WAIT_F = 1, LOCKING = 2, LOCKED = 3;

    reg signed [20:0] h_sum;
    reg [18:0] s_sum, v_sum;
    reg [8:0]  target_h_hsv;
    reg [7:0]  target_s, target_v;
    wire signed [10:0] h_signed = (hsv_h > 270) ? ({1'b0, hsv_h} - 11'd360) : {1'b0, hsv_h};

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= IDLE;
            h_sum <= 0; s_sum <= 0; v_sum <= 0;
            target_h_hsv <= 0; target_s <= 0; target_v <= 0;
        end else begin
            case(state)
                IDLE: if(lock_trigger) state <= WAIT_F;
                WAIT_F: begin
                    if(vsync_pos) begin state <= LOCKING; h_sum <= 0; s_sum <= 0; v_sum <= 0; end
                    if(!lock_sw) state <= IDLE;
                end
                LOCKING: begin
                    if(hsv_valid) begin
                        if (img_x >= 134 && img_x <= 165 && img_y >= 184 && img_y <= 215) begin
                            h_sum <= h_sum + h_signed;
                            s_sum <= s_sum + hsv_s;
                            v_sum <= v_sum + hsv_v;
                        end
                    end
                    if(vsync_pos) begin
                        state <= LOCKED;
                        target_h_hsv <= 9'd0;
                        target_s <= 8'd120;
                        target_v <= 8'd80;
                    end
                    if(!lock_sw) state <= IDLE;
                end
                LOCKED: if(!lock_sw) state <= IDLE;
            endcase
        end
    end

    wire [8:0] h_diff1 = (hsv_h >= target_h_hsv) ? (hsv_h - target_h_hsv) : (target_h_hsv - hsv_h);
    wire [8:0] h_diff  = (h_diff1 > 180) ? (360 - h_diff1) : h_diff1;

    wire is_target = hsv_valid && (state == LOCKED) &&
                     (h_diff <= 9'd30) &&
                     (hsv_s > 8'd50) &&
                     (hsv_v > 8'd40);

    reg [27:0] x_acc;
    reg [26:0] y_acc;
    reg [26:0] w_acc;
    reg [26:0] h_acc;
    reg [17:0] pixel_cnt;

    reg [27:0] x_latch, y_latch, w_latch, h_latch;
    reg [17:0] cnt_latch;

    reg [6:0] lost_timer;

    wire [10:0] roi_margin_w = (target_w >> 1) + 11'd100;
    wire [10:0] roi_margin_h = (target_h >> 1) + 11'd100;
    wire [10:0] roi_left   = (target_x > roi_margin_w) ? (target_x - roi_margin_w) : 11'd0;
    wire [10:0] roi_right  = target_x + roi_margin_w;
    wire [10:0] roi_top    = (target_y > roi_margin_h) ? (target_y - roi_margin_h) : 11'd0;
    wire [10:0] roi_bot    = target_y + roi_margin_h;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x_acc <= 0; y_acc <= 0; w_acc <= 0; h_acc <= 0; pixel_cnt <= 0;
            x_latch <= 0; y_latch <= 0; w_latch <= 0; h_latch <= 0; cnt_latch <= 0;
        end else if(vsync_pos) begin
            x_latch <= x_acc; y_latch <= y_acc;
            w_latch <= w_acc; h_latch <= h_acc;
            cnt_latch <= pixel_cnt;

            x_acc <= 0; y_acc <= 0; w_acc <= 0; h_acc <= 0; pixel_cnt <= 0;
        end else if(is_target) begin
            if (cnt_latch <= 18'd250 ||
               (img_x >= roi_left && img_x <= roi_right && img_y >= roi_top && img_y <= roi_bot)) begin

                x_acc <= x_acc + img_x;
                y_acc <= y_acc + img_y;
                pixel_cnt <= pixel_cnt + 1'b1;

                w_acc <= w_acc + ((img_x >= target_x) ? (img_x - target_x) : (target_x - img_x));
                h_acc <= h_acc + ((img_y >= target_y) ? (img_y - target_y) : (target_y - img_y));
            end
        end
    end

    reg [5:0]  div_step;
    reg [55:0] div_rq_x;
    reg [55:0] div_rq_y;
    reg [55:0] div_rq_w;
    reg [55:0] div_rq_h;
    reg [27:0] divisor;
    reg        div_done;

    wire [10:0] calc_w = {div_rq_w[8:0], 2'b00};
    wire [10:0] calc_h = {div_rq_h[8:0], 2'b00};

    wire [10:0] cx_raw = div_rq_x[10:0];
    wire [10:0] cy_raw = div_rq_y[10:0];
    wire [10:0] cw_raw = (calc_w < 11'd15) ? 11'd15 : calc_w;
    wire [10:0] ch_raw = (calc_h < 11'd15) ? 11'd15 : calc_h;
    wire [10:0] cx_c = (cx_raw > target_x + 11'd24) ? (target_x + 11'd24) :
                       ((cx_raw + 11'd24 < target_x) ? (target_x - 11'd24) : cx_raw);
    wire [10:0] cy_c = (cy_raw > target_y + 11'd24) ? (target_y + 11'd24) :
                       ((cy_raw + 11'd24 < target_y) ? (target_y - 11'd24) : cy_raw);
    wire [10:0] cw_c = (cw_raw > target_w + 11'd24) ? (target_w + 11'd24) :
                       ((cw_raw + 11'd24 < target_w) ? (target_w - 11'd24) : cw_raw);
    wire [10:0] ch_c = (ch_raw > target_h + 11'd24) ? (target_h + 11'd24) :
                       ((ch_raw + 11'd24 < target_h) ? (target_h - 11'd24) : ch_raw);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            target_x <= 10'd150;
            target_y <= 10'd200;
            target_w <= 10'd100;
            target_h <= 10'd100;
            div_step <= 0;
            div_done <= 0;
            lost_timer <= 0;
        end else if(vsync_pos) begin
            if (lock_sw == 1'b0) begin
                target_x <= 10'd150; target_y <= 10'd200;
                target_w <= 10'd100; target_h <= 10'd100;
                div_done <= 0; lost_timer <= 0;
            end else if (cnt_latch > 18'd250) begin
                lost_timer <= 0;
                div_rq_x <= {28'd0, x_latch};
                div_rq_y <= {28'd0, 1'b0, y_latch};
                div_rq_w <= {28'd0, 1'b0, w_latch};
                div_rq_h <= {28'd0, 1'b0, h_latch};
                divisor  <= {10'd0, cnt_latch};
                div_step <= 6'd28;
                div_done <= 0;
            end else begin

                if (lost_timer < 7'd15) begin
                    lost_timer <= lost_timer + 1'b1;
                    div_done <= 0;
                end else begin
                    target_x <= 10'd150; target_y <= 10'd200;
                    target_w <= 10'd100; target_h <= 10'd100;
                    div_done <= 0;
                end
            end
        end else if (div_step > 0 && lock_sw == 1'b1) begin
            if ({div_rq_x[54:28], div_rq_x[27]} >= divisor)
                div_rq_x <= { ({div_rq_x[54:28], div_rq_x[27]} - divisor[27:0]), div_rq_x[26:0], 1'b1 };
            else div_rq_x <= { div_rq_x[54:0], 1'b0 };

            if ({div_rq_y[54:28], div_rq_y[27]} >= divisor)
                div_rq_y <= { ({div_rq_y[54:28], div_rq_y[27]} - divisor[27:0]), div_rq_y[26:0], 1'b1 };
            else div_rq_y <= { div_rq_y[54:0], 1'b0 };

            if ({div_rq_w[54:28], div_rq_w[27]} >= divisor)
                div_rq_w <= { ({div_rq_w[54:28], div_rq_w[27]} - divisor[27:0]), div_rq_w[26:0], 1'b1 };
            else div_rq_w <= { div_rq_w[54:0], 1'b0 };

            if ({div_rq_h[54:28], div_rq_h[27]} >= divisor)
                div_rq_h <= { ({div_rq_h[54:28], div_rq_h[27]} - divisor[27:0]), div_rq_h[26:0], 1'b1 };
            else div_rq_h <= { div_rq_h[54:0], 1'b0 };

            div_step <= div_step - 1'b1;
            if (div_step == 1) div_done <= 1'b1;

        end else if (div_done) begin
            target_x <= cx_c;
            target_y <= cy_c;
            target_w <= (target_w * 3 + cw_c) >> 2;
            target_h <= (target_h * 3 + ch_c) >> 2;

            div_done <= 1'b0;
        end
    end
endmodule
