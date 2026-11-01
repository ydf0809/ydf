`timescale 1ns / 1ps
// Two luminance banks are reused for translation estimation and residual
// motion.  RGB data is never thresholded or sent through this module to SCNN.
// After the final crop pixel: sparse SAD search (all integer translations in +/-16 preview
// pixels), then one raster residual scan.  No third frame RAM is needed.
// Translation only: rotation/parallax/large jumps deliberately fall back to
// overlapping RGB window search instead of trusting a noisy motion proposal.
module motion_detector #(
    parameter integer W=300, H=200, BLK=10,
    parameter [7:0] PIXEL_THRESHOLD=20,
    parameter [6:0] BLOCK_MIN=4,
    parameter [7:0] DARK_THRESHOLD=80,
    parameter integer GLOBAL_MOTION_LIMIT=20000,
    parameter integer HOLD_FRAMES=0,
    parameter integer CLUSTER_RADIUS=2,
    parameter integer JUMP_DISTANCE=32,
    parameter integer CENTER_DEADBAND=2
)(
    input wire clk, rst_n, frame_sync, pix_we,
    input wire [8:0] pix_x,
    input wire [7:0] pix_y,
    input wire [15:0] pix_rgb565,
    input wire track_enable,
    input wire [9:0] track_x0,
    input wire [8:0] track_y0,
    output reg box_valid, track_found, box_update,
    output reg [8:0] box_x0, box_x1,
    output reg [7:0] box_y0, box_y1,
    output reg [13:0] motion_count,
    output reg [6:0] dbg_best,
    output reg [15:0] dbg_total
);
    localparam SAMPLES=W*H, NBX=W/BLK, NBY=H/BLK, NB=NBX*NBY;
    localparam IDLE=0, SAD_READ=1, SAD_EVAL=2, DIFF=3, DRAIN=4,
               BEST=5, CLUSTER=6, DIVIDE=7, FINISH=8, CLEAR=9;
    reg [3:0] state;
    (* ram_style="block" *) reg [7:0] frame0[0:SAMPLES-1];
    (* ram_style="block" *) reg [7:0] frame1[0:SAMPLES-1];
    reg write_bank, job_bank, frame_complete, have_prev;
    reg [7:0] q0,q1;
    reg [15:0] read_current,read_previous;
    reg [23:0] sum_cur,sum_prev;
    reg signed [8:0] brightness_shift;
    wire [7:0] r={pix_rgb565[15:11],pix_rgb565[15:13]};
    wire [7:0] g={pix_rgb565[10:5],pix_rgb565[10:9]};
    wire [7:0] b={pix_rgb565[4:0],pix_rgb565[4:2]};
    wire [10:0] luma_sum={2'b0,r,1'b0}+({3'b0,g}<<2)+{3'b0,g}+{3'b0,b};
    wire [7:0] luma=luma_sum[10:3];
    wire [15:0] write_address=pix_y*W+pix_x;
    wire [7:0] current_q=job_bank?q1:q0;
    wire [7:0] previous_q=job_bank?q0:q1;
    wire signed [9:0] corrected=$signed({2'b0,current_q})-
        $signed({2'b0,previous_q})-$signed(brightness_shift);
    wire [9:0] abs_diff=corrected[9]?-corrected:corrected;
    wire [7:0] clipped_diff=(abs_diff>63)?8'd63:abs_diff[7:0];

    reg [5:0] shift_col,shift_row;
    reg [6:0] sample_index;
    reg signed [6:0] best_dx,best_dy;
    reg signed [6:0] global_dx,global_dy;
    reg compensation_valid,processing_overrun;
    reg [15:0] sad,best_sad;
    reg [7:0] sample_min,sample_max;
    integer sx,sy,tx,ty,offset_x,offset_y,distance_now,distance_best;
    wire [16:0] sad_next={1'b0,sad}+clipped_diff;
    wire sad_better=(sad_next<best_sad) ||
        ((sad_next==best_sad) && (distance_now<distance_best));

    reg [8:0] scan_x,pipe_x;
    reg [7:0] scan_y,pipe_y;
    reg pipe_valid,pipe_overlap;
    reg [7:0] block_count[0:NB-1];
    reg [15:0] residual_total;
    reg [9:0] block_index;
    reg [5:0] block_col,block_row,best_col,best_row;
    reg [7:0] best_count;
    reg [13:0] cluster_weight;
    reg [22:0] cluster_x,cluster_y,num_x,num_y,quot_x,quot_y;
    reg [14:0] rem_x,rem_y;
    reg [4:0] div_bit;
    reg [13:0] denominator;
    reg previous_candidate;
    reg [8:0] previous_cx;
    reg [7:0] previous_cy;
    wire [9:0] pipe_block=(pipe_y/BLK)*NBX+(pipe_x/BLK);
    wire [7:0] residual_weight=(current_q<DARK_THRESHOLD)?8'd2:8'd1;
    wire [7:0] cluster_threshold=(best_count/2>BLOCK_MIN)?best_count/2:BLOCK_MIN;
    wire [5:0] col_delta=(block_col>best_col)?block_col-best_col:best_col-block_col;
    wire [5:0] row_delta=(block_row>best_row)?block_row-best_row:best_row-block_row;
    wire [14:0] rem_x_next={rem_x[13:0],num_x[22]};
    wire [14:0] rem_y_next={rem_y[13:0],num_y[22]};
    integer k,cx,cy,dx,dy,bx,by;

    // Local position uses contrast against this frame's four ROI corners.
    // Both dark-on-bright and bright-on-dark silhouettes are supported.
    // Identity still requires recurring positive RGB network results.
    reg track_lat;
    reg [8:0] track_x;
    reg [7:0] track_y;
    wire [8:0] rel_x=pix_x-track_x;
    wire [7:0] rel_y=pix_y-track_y;
    wire local_in_roi=track_lat && track_enable && pix_x>=track_x &&
        pix_y>=track_y && rel_x<64 && rel_y<64;
    wire local_inner=local_in_roi && rel_x>=8 && rel_x<56 && rel_y>=8 && rel_y<56;
    wire local_corner=local_in_roi && (rel_x<8 || rel_x>=56) && (rel_y<8 || rel_y>=56);
    wire [2:0] bin_x=rel_x[5:3]-1'b1,bin_y=rel_y[5:3]-1'b1;
    wire [5:0] local_bin=bin_y*6+bin_x;
    localparam LOCAL_MIN_PEAK=256, LOCAL_MIN_SUPPORT=128, LOCAL_MAX_ACTIVE=18;
    reg [13:0] local_sum[0:35];
    reg [15:0] local_bg_sum;
    reg [8:0] local_bg_count;
    reg [11:0] local_pixels;
    reg [7:0] local_bg;
    reg [2:0] local_state,local_col,local_row,local_peak_col,local_peak_row;
    reg [5:0] local_index,local_active;
    reg [13:0] local_peak,local_far_peak;
    reg [3:0] local_peak_distance;
    reg local_peak_bright,local_capture_ok,local_usable,local_ready,local_match;
    reg [19:0] local_weight,local_den;
    reg [25:0] local_num_x,local_num_y,local_quot_x,local_quot_y;
    reg [20:0] local_rem_x,local_rem_y;
    reg [4:0] local_div_bit;
    reg [8:0] local_cx;
    reg [7:0] local_cy;
    wire [14:0] local_bg_word={1'b0,local_bg,6'b0};
    // Register the signed difference before magnitude/peak selection. This
    // prevents carry-chain sharing from creating a combinational timing loop.
    reg signed [14:0] local_delta;
    wire local_bright=!local_delta[14];
    wire [14:0] local_energy=local_delta[14] ? -local_delta : local_delta;
    wire [13:0] local_support=((local_peak>>2)>LOCAL_MIN_SUPPORT) ?
        (local_peak>>2):LOCAL_MIN_SUPPORT;
    wire [3:0] local_col2={local_col,1'b0},local_row2={local_row,1'b0};
    // The centre of six bins is 2.5, not bin 2. Equal plateaus are rejected below.
    wire [3:0] local_distance=((local_col2>5)?local_col2-5:5-local_col2)+
        ((local_row2>5)?local_row2-5:5-local_row2);
    wire [2:0] local_dx=(local_col>local_peak_col)?local_col-local_peak_col:local_peak_col-local_col;
    wire [2:0] local_dy=(local_row>local_peak_row)?local_row-local_peak_row:local_peak_row-local_row;
    wire [5:0] local_coord_x=6'd12+{local_col,3'b0};
    wire [5:0] local_coord_y=6'd12+{local_row,3'b0};
    wire [20:0] local_rx_next={local_rem_x[19:0],local_num_x[25]};
    wire [20:0] local_ry_next={local_rem_y[19:0],local_num_y[25]};
    integer local_k;

    // 36 cell sums plus one sequential centroid divider; no extra frame RAM.
    // This job finishes within 173 clocks after the ROI's last pixel. It runs
    // independently of the existing global-motion job and its RAM ports.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            local_bg_sum<=0;local_bg_count<=0;local_pixels<=0;local_bg<=0;
            local_state<=0;local_col<=0;local_row<=0;local_index<=0;
            local_peak_col<=0;local_peak_row<=0;local_peak<=0;local_far_peak<=0;
            local_peak_distance<=15;local_peak_bright<=0;local_active<=0;
            local_capture_ok<=0;local_usable<=0;local_ready<=0;local_match<=0;
            local_weight<=0;local_den<=0;local_num_x<=0;local_num_y<=0;
            local_quot_x<=0;local_quot_y<=0;local_rem_x<=0;local_rem_y<=0;
            local_div_bit<=0;local_cx<=0;local_cy<=0;local_delta<=0;
            for(local_k=0;local_k<36;local_k=local_k+1)local_sum[local_k]<=0;
        end else if(frame_sync) begin
            local_bg_sum<=0;local_bg_count<=0;local_pixels<=0;
            local_state<=0;local_ready<=0;local_match<=0;
            for(local_k=0;local_k<36;local_k=local_k+1)local_sum[local_k]<=0;
        end else begin
            if(pix_we && local_inner) begin
                local_sum[local_bin]<=local_sum[local_bin]+{6'b0,luma};
                local_pixels<=local_pixels+1'b1;
            end
            if(pix_we && local_corner) begin
                local_bg_sum<=local_bg_sum+{8'b0,luma};
                local_bg_count<=local_bg_count+1'b1;
            end
            case(local_state)
                0: if(pix_we && local_in_roi && rel_x==63 && rel_y==63) begin
                    // Include the coincident final corner pixel in this frame's mean.
                    local_bg<=(local_bg_sum+{8'b0,luma})>>8;
                    local_capture_ok<=local_bg_count==255 && local_pixels==2304;
                    local_index<=0;local_col<=0;local_row<=0;
                    local_peak<=0;local_peak_distance<=15;local_state<=1;
                end
                1: begin
                    local_delta<=$signed({1'b0,local_sum[local_index]})-$signed(local_bg_word);
                    local_state<=6;
                end
                6: begin
                    local_state<=1;
                    if(local_energy>local_peak ||
                       (local_energy==local_peak && local_distance<local_peak_distance)) begin
                        local_peak<=local_energy;local_peak_col<=local_col;local_peak_row<=local_row;
                        local_peak_distance<=local_distance;local_peak_bright<=local_bright;
                    end
                    if(local_index==35) begin
                        local_index<=0;local_col<=0;local_row<=0;local_state<=2;
                        local_active<=0;local_far_peak<=0;local_weight<=0;
                        local_num_x<=0;local_num_y<=0;
                    end else begin
                        local_index<=local_index+1'b1;
                        if(local_col==5)begin local_col<=0;local_row<=local_row+1'b1;end
                        else local_col<=local_col+1'b1;
                    end
                end
                2: begin
                    local_delta<=$signed({1'b0,local_sum[local_index]})-$signed(local_bg_word);
                    local_state<=7;
                end
                7: begin
                    local_state<=2;
                    if(local_energy>=local_support) begin
                        local_active<=local_active+1'b1;
                        if(local_dx<=2 && local_dy<=2 && local_bright==local_peak_bright) begin
                            local_weight<=local_weight+local_energy;
                            local_num_x<=local_num_x+local_energy*local_coord_x;
                            local_num_y<=local_num_y+local_energy*local_coord_y;
                        end else if(local_energy>local_far_peak)local_far_peak<=local_energy;
                    end
                    if(local_index==35)local_state<=3;
                    else begin
                        local_index<=local_index+1'b1;
                        if(local_col==5)begin local_col<=0;local_row<=local_row+1'b1;end
                        else local_col<=local_col+1'b1;
                    end
                end
                3: begin
                    // A broad background or an equally strong distant region
                    // is uncertainty, not a new target position or velocity.
                    local_usable<=local_capture_ok && local_peak>=LOCAL_MIN_PEAK &&
                        local_active<=LOCAL_MAX_ACTIVE && local_weight!=0 &&
                        local_far_peak<(local_peak-(local_peak>>3));
                    local_den<=local_weight;local_rem_x<=0;local_rem_y<=0;
                    local_quot_x<=0;local_quot_y<=0;local_div_bit<=0;local_state<=4;
                end
                4: begin
                    local_num_x<={local_num_x[24:0],1'b0};
                    local_num_y<={local_num_y[24:0],1'b0};
                    if(local_rx_next>={1'b0,local_den})begin
                        local_rem_x<=local_rx_next-local_den;local_quot_x<={local_quot_x[24:0],1'b1};
                    end else begin local_rem_x<=local_rx_next;local_quot_x<={local_quot_x[24:0],1'b0};end
                    if(local_ry_next>={1'b0,local_den})begin
                        local_rem_y<=local_ry_next-local_den;local_quot_y<={local_quot_y[24:0],1'b1};
                    end else begin local_rem_y<=local_ry_next;local_quot_y<={local_quot_y[24:0],1'b0};end
                    if(local_div_bit==25)local_state<=5;
                    else local_div_bit<=local_div_bit+1'b1;
                end
                5: begin
                    local_ready<=1;local_match<=local_usable;
                    if(local_usable)begin
                        local_cx<=track_x+local_quot_x[8:0];local_cy<=track_y+local_quot_y[7:0];
                    end
                    local_state<=0;
                end
                default:local_state<=0;
            endcase
        end
    end

    // Separate simple dual-port banks: capture write and synchronous read.
    always @(posedge clk) begin
        if(pix_we && !write_bank) frame0[write_address]<=luma;
        if(pix_we && write_bank) frame1[write_address]<=luma;
        q0<=frame0[job_bank?read_previous:read_current];
        q1<=frame1[job_bank?read_current:read_previous];
    end
    always @* begin
        offset_x=$signed({1'b0,shift_col})-16;
        offset_y=$signed({1'b0,shift_row})-16;
        distance_now=((offset_x<0)?-offset_x:offset_x)+((offset_y<0)?-offset_y:offset_y);
        distance_best=((best_dx<0)?-best_dx:best_dx)+((best_dy<0)?-best_dy:best_dy);
        sx=40+(sample_index%12)*20;
        sy=30+(sample_index/12)*20;
        read_current=0; read_previous=0;
        tx=0;ty=0;
        if(state==SAD_READ || state==SAD_EVAL) begin
            read_current=sy*W+sx;
            read_previous=(sy-offset_y)*W+(sx-offset_x);
        end else if(state==DIFF) begin
            tx=$signed({1'b0,scan_x})-$signed(global_dx);
            ty=$signed({1'b0,scan_y})-$signed(global_dy);
            read_current=scan_y*W+scan_x;
            if(tx>=0 && tx<W && ty>=0 && ty<H) read_previous=ty*W+tx;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;write_bank<=0;job_bank<=0;frame_complete<=0;have_prev<=0;
            sum_cur<=0;sum_prev<=0;brightness_shift<=0;
            shift_col<=0;shift_row<=0;sample_index<=0;
            best_dx<=0;best_dy<=0;global_dx<=0;global_dy<=0;
            compensation_valid<=0;processing_overrun<=0;
            sad<=0;best_sad<=16'hffff;sample_min<=255;sample_max<=0;
            scan_x<=0;scan_y<=0;pipe_x<=0;pipe_y<=0;pipe_valid<=0;pipe_overlap<=0;
            block_index<=0;block_col<=0;block_row<=0;best_col<=0;best_row<=0;
            best_count<=0;residual_total<=0;cluster_weight<=0;cluster_x<=0;cluster_y<=0;
            num_x<=0;num_y<=0;quot_x<=0;quot_y<=0;rem_x<=0;rem_y<=0;div_bit<=0;denominator<=0;
            previous_candidate<=0;previous_cx<=0;previous_cy<=0;
            box_valid<=0;track_found<=0;box_update<=0;
            box_x0<=0;box_x1<=0;box_y0<=0;box_y1<=0;motion_count<=0;dbg_best<=0;dbg_total<=0;
            track_lat<=0;track_x<=0;track_y<=0;
            // Counters are a small register array, not a reset frame RAM.
            for(k=0;k<NB;k=k+1) block_count[k]<=0;
        end else begin
            box_update<=0;
            pipe_valid<=0;
            if(pix_we) sum_cur<=sum_cur+{16'b0,luma};
            if(frame_sync && frame_complete) begin
                write_bank<=~write_bank;frame_complete<=0;
            end
            if(frame_sync) begin
                track_lat<=track_enable;
                track_x<=track_x0>>1;track_y<=track_y0>>1;
                track_found<=track_lat && track_enable && local_ready && local_match;
                if(track_lat && track_enable && local_ready && local_match) begin
                    cx=local_cx;cy=local_cy;
                    bx=cx-32;by=cy-32;
                    if(bx<0)bx=0;if(bx>W-64)bx=W-64;
                    if(by<0)by=0;if(by>H-64)by=H-64;
                    box_x0<=bx;box_x1<=bx+63;box_y0<=by;box_y1<=by+63;
                    box_valid<=1;
                end
                if(track_lat && !track_enable) begin
                    box_valid<=0;previous_candidate<=0;
                end
            end
            // The completed frame is processed before the next crop begins.
            // If a changed camera timing removes that blanking budget, abort
            // proposals rather than comparing a partly overwritten frame.
            if(pix_we && state!=IDLE) begin
                state<=IDLE;processing_overrun<=1;compensation_valid<=0;
                previous_candidate<=0;if(!track_enable)box_valid<=0;
            end else case(state)
                IDLE: if(pix_we && pix_x==W-1 && pix_y==H-1) begin
                    job_bank<=write_bank;frame_complete<=1;
                    sum_prev<=sum_cur+{16'b0,luma};sum_cur<=0;
                    brightness_shift<=($signed({1'b0,sum_cur})+$signed({17'b0,luma})-$signed({1'b0,sum_prev}))>>>16;
                    have_prev<=1;processing_overrun<=0;
                    if(have_prev) begin
                        state<=CLEAR;block_index<=0;shift_col<=0;shift_row<=0;sample_index<=0;
                        sad<=0;best_sad<=16'hffff;best_dx<=0;best_dy<=0;
                        sample_min<=255;sample_max<=0;residual_total<=0;
                    end
                end
                CLEAR: begin
                    block_count[block_index]<=0;
                    if(block_index==NB-1)begin state<=SAD_READ;block_index<=0;end
                    else block_index<=block_index+1'b1;
                end
                SAD_READ: state<=SAD_EVAL;
                SAD_EVAL: begin
                    if(current_q<sample_min)sample_min<=current_q;
                    if(current_q>sample_max)sample_max<=current_q;
                    if(sample_index==95) begin
                        if(sad_better)begin
                            best_sad<=sad_next;best_dx<=offset_x;best_dy<=offset_y;
                        end
                        sample_index<=0;sad<=0;
                        if(shift_col==32 && shift_row==32) begin
                            compensation_valid<=sample_max-sample_min>=32 &&
                                (sad_better?sad_next:best_sad)<96*24;
                            global_dx<=(sample_max-sample_min>=32 && (sad_better?sad_next:best_sad)<96*24)?(sad_better?offset_x:best_dx):0;
                            global_dy<=(sample_max-sample_min>=32 && (sad_better?sad_next:best_sad)<96*24)?(sad_better?offset_y:best_dy):0;
                            scan_x<=0;scan_y<=0;state<=DIFF;
                        end else begin
                            if(shift_col==32)begin shift_col<=0;shift_row<=shift_row+1'b1;end
                            else shift_col<=shift_col+1'b1;
                            state<=SAD_READ;
                        end
                    end else begin
                        sad<=sad_next;sample_index<=sample_index+1'b1;state<=SAD_READ;
                    end
                end
                DIFF: begin
                    pipe_valid<=1;pipe_x<=scan_x;pipe_y<=scan_y;
                    pipe_overlap<=tx>=0 && tx<W && ty>=0 && ty<H;
                    if(scan_x==W-1)begin
                        scan_x<=0;
                        if(scan_y==H-1)state<=DRAIN;else scan_y<=scan_y+1'b1;
                    end else scan_x<=scan_x+1'b1;
                end
                DRAIN: begin
                    state<=BEST;block_index<=0;block_col<=0;block_row<=0;best_count<=0;
                end
                BEST: begin
                    if(block_count[block_index]>best_count)begin
                        best_count<=block_count[block_index];best_col<=block_col;best_row<=block_row;
                    end
                    if(block_index==NB-1)begin
                        state<=CLUSTER;block_index<=0;block_col<=0;block_row<=0;
                        cluster_weight<=0;cluster_x<=0;cluster_y<=0;
                    end else begin
                        block_index<=block_index+1'b1;
                        if(block_col==NBX-1)begin block_col<=0;block_row<=block_row+1'b1;end
                        else block_col<=block_col+1'b1;
                    end
                end
                CLUSTER: begin
                    if(block_count[block_index]>=cluster_threshold && col_delta<=CLUSTER_RADIUS && row_delta<=CLUSTER_RADIUS)begin
                        cluster_weight<=cluster_weight+block_count[block_index];
                        cluster_x<=cluster_x+block_count[block_index]*(block_col*BLK+BLK/2);
                        cluster_y<=cluster_y+block_count[block_index]*(block_row*BLK+BLK/2);
                    end
                    block_count[block_index]<=0;
                    if(block_index==NB-1)begin
                        state<=DIVIDE;div_bit<=0;
                    end else begin
                        block_index<=block_index+1'b1;
                        if(block_col==NBX-1)begin block_col<=0;block_row<=block_row+1'b1;end
                        else block_col<=block_col+1'b1;
                    end
                end
                DIVIDE: begin
                    if(div_bit==0)begin
                        denominator<=cluster_weight;num_x<=cluster_x;num_y<=cluster_y;
                        rem_x<=0;rem_y<=0;quot_x<=0;quot_y<=0;div_bit<=1;
                    end else begin
                        num_x<={num_x[21:0],1'b0};num_y<={num_y[21:0],1'b0};
                        if(rem_x_next>={1'b0,denominator})begin
                            rem_x<=rem_x_next-denominator;quot_x<={quot_x[21:0],1'b1};
                        end else begin rem_x<=rem_x_next;quot_x<={quot_x[21:0],1'b0};end
                        if(rem_y_next>={1'b0,denominator})begin
                            rem_y<=rem_y_next-denominator;quot_y<={quot_y[21:0],1'b1};
                        end else begin rem_y<=rem_y_next;quot_y<={quot_y[21:0],1'b0};end
                        if(div_bit==23)state<=FINISH;else div_bit<=div_bit+1'b1;
                    end
                end
                FINISH: begin
                    dbg_best<=(best_count>127)?127:best_count;dbg_total<=residual_total;
                    cx=quot_x;cy=quot_y;
                    dx=cx-previous_cx;dy=cy-previous_cy;
                    if(dx<0)dx=-dx;if(dy<0)dy=-dy;
                    if(!track_enable) begin
                        box_update<=1;
                        box_valid<=cluster_weight!=0 && best_count>=BLOCK_MIN &&
                            residual_total<GLOBAL_MOTION_LIMIT && previous_candidate && dx+dy<=64;
                        if(cluster_weight!=0 && best_count>=BLOCK_MIN && residual_total<GLOBAL_MOTION_LIMIT)begin
                            previous_candidate<=1;previous_cx<=cx;previous_cy<=cy;
                            bx=cx-32;by=cy-32;
                            if(bx<0)bx=0;if(bx>W-64)bx=W-64;
                            if(by<0)by=0;if(by>H-64)by=H-64;
                            box_x0<=bx;box_x1<=bx+63;box_y0<=by;box_y1<=by+63;
                            motion_count<={6'b0,best_count};
                        end else previous_candidate<=0;
                    end
                    state<=IDLE;
                end
                default:state<=IDLE;
            endcase
            if(pipe_valid && pipe_overlap && abs_diff>PIXEL_THRESHOLD && state!=IDLE)begin
                if(block_count[pipe_block]<255-residual_weight)
                    block_count[pipe_block]<=block_count[pipe_block]+residual_weight;
                if(residual_total<65535-residual_weight)residual_total<=residual_total+residual_weight;
            end
        end
    end
endmodule
