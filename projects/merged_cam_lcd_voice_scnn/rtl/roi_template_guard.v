`timescale 1ns/1ps
// Immutable 64x64 luminance template, staged only from a positive RGB result.
// RGB pixels sent to SCNN are unchanged. Both RAMs have synchronous read ports.
module roi_template_guard #(
    parameter [20:0] SAD_LIMIT = 21'd180000
)(
    input wire clk, rst_n, capture_start, capture_we, capture_done,
    input wire [11:0] capture_addr,
    input wire [23:0] capture_rgb,
    input wire label_valid, label_positive, tracking,
    output reg template_valid, match_ok,
    output wire commit_busy
);
    (* ram_style="block" *) reg [7:0] crop_mem [0:4095];
    (* ram_style="block" *) reg [7:0] template_mem [0:4095];
    reg [7:0] crop_read_q, template_read_q, luma_d;
    reg we_d, done_d, tracking_d;
    reg copy_active, copy_write_valid;
    reg [11:0] copy_index, copy_write_addr;
    reg [12:0] pixel_count;
    reg [20:0] sad;
    wire [7:0] r=capture_rgb[23:16], g=capture_rgb[15:8], b=capture_rgb[7:0];
    wire [10:0] luma_sum={2'b0,r,1'b0}+({3'b0,g}<<2)+{3'b0,g}+{3'b0,b};
    wire [7:0] luma=luma_sum[10:3];
    wire [8:0] abs_diff=(luma_d>=template_read_q) ?
                       luma_d-template_read_q : template_read_q-luma_d;
    wire [20:0] sad_next=sad+((we_d && template_valid)?abs_diff:9'd0);
    assign commit_busy=copy_active || copy_write_valid;

    // No reset on either RAM. The locked template never shares the SCNN
    // ping-pong bank selector, so later crops cannot overwrite its pixels.
    always @(posedge clk) begin
        if(capture_we) begin
            crop_mem[capture_addr]<=luma;
            template_read_q<=template_mem[capture_addr];
        end
        if(copy_active) crop_read_q<=crop_mem[copy_index];
        if(copy_write_valid) template_mem[copy_write_addr]<=crop_read_q;
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            template_valid<=0; match_ok<=0; tracking_d<=0;
            copy_active<=0; copy_write_valid<=0;
            copy_index<=0; copy_write_addr<=0;
            pixel_count<=0; sad<=0; we_d<=0; done_d<=0; luma_d<=0;
        end else begin
            tracking_d<=tracking;
            we_d<=capture_we; done_d<=capture_done; luma_d<=luma;
            if(capture_start) begin pixel_count<=0; sad<=0; end
            if(capture_we) pixel_count<=pixel_count+1'b1;
            if(we_d && template_valid) sad<=sad_next;
            // Only add a delayed pixel when its valid flag is asserted. This
            // handles both coincident and separated last-pixel/done pulses.
            if(done_d)
                match_ok<=template_valid && pixel_count==4096 && sad_next<=SAD_LIMIT;

            copy_write_valid<=copy_active;
            copy_write_addr<=copy_index;
            if(copy_active) begin
                if(copy_index==4095) copy_active<=0;
                else copy_index<=copy_index+1'b1;
            end
            if(copy_write_valid && copy_write_addr==4095) begin
                template_valid<=1; match_ok<=1;
            end
            // The label belongs to the held crop RAM. If the fifth VERIFY
            // result is negative, the last positive template remains intact.
            if(label_valid && label_positive && !tracking &&
               !commit_busy && pixel_count==4096) begin
                copy_active<=1; copy_index<=0;
            end
            if(tracking_d && !tracking) begin
                template_valid<=0; match_ok<=0;
                copy_active<=0; copy_write_valid<=0;
            end
        end
    end
endmodule
