`timescale 1ns / 1ps

module periodic_recheck_timer #(
    parameter integer INTERVAL_CYCLES = 33333333
) (
    input  wire clk,
    input  wire rst_n,
    input  wire tracking,
    output reg  request_toggle
);
    localparam integer COUNT_W = (INTERVAL_CYCLES > 1) ?
                                  $clog2(INTERVAL_CYCLES) : 1;
    localparam [COUNT_W-1:0] LAST_COUNT = INTERVAL_CYCLES - 1;
    reg [COUNT_W-1:0] count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= {COUNT_W{1'b0}};
            request_toggle <= 1'b0;
        end else if (!tracking) begin
            count <= {COUNT_W{1'b0}};
        end else if (count == LAST_COUNT) begin
            count <= {COUNT_W{1'b0}};
            request_toggle <= ~request_toggle;
        end else begin
            count <= count + 1'b1;
        end
    end
endmodule
