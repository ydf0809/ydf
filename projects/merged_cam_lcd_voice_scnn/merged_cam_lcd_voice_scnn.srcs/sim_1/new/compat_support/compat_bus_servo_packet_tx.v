module compat_bus_servo_packet_tx #(
    parameter integer CLK_HZ = 33300000,
    parameter integer BAUD   = 115200
)(
    input  wire       sys_clk,
    input  wire       rst_n,
    input  wire       send_req,
    input  wire [7:0] servo_id,
    input  wire [7:0] frame_len,
    input  wire [7:0] cmd,
    input  wire [2:0] param_count,
    input  wire [7:0] param1,
    input  wire [7:0] param2,
    input  wire [7:0] param3,
    input  wire [7:0] param4,
    output wire       txd,
    output wire       tx_oe,
    output reg        busy,
    output reg        done
);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_FIRE = 2'd1;
    localparam [1:0] S_WAIT = 2'd2;
    localparam [1:0] S_DONE = 2'd3;

    reg [1:0] state;

    reg [4:0] byte_index;
    reg [4:0] total_bytes;

    reg [7:0] id_r;
    reg [7:0] len_r;
    reg [7:0] cmd_r;
    reg [2:0] param_count_r;
    reg [7:0] p1_r;
    reg [7:0] p2_r;
    reg [7:0] p3_r;
    reg [7:0] p4_r;
    reg [7:0] checksum_r;

    reg       uart_start;
    reg [7:0] current_byte;

    wire uart_busy;
    wire uart_done;

    function [7:0] calc_checksum;
        input [7:0] id_i;
        input [7:0] len_i;
        input [7:0] cmd_i;
        input [2:0] pcount_i;
        input [7:0] p1_i;
        input [7:0] p2_i;
        input [7:0] p3_i;
        input [7:0] p4_i;
        reg [10:0] sum;
        begin
            sum = {3'd0, id_i} + {3'd0, len_i} + {3'd0, cmd_i};
            case (pcount_i)
                3'd0: sum = sum;
                3'd1: sum = sum + {3'd0, p1_i};
                3'd2: sum = sum + {3'd0, p1_i} + {3'd0, p2_i};
                3'd3: sum = sum + {3'd0, p1_i} + {3'd0, p2_i} + {3'd0, p3_i};
                default: sum = sum + {3'd0, p1_i} + {3'd0, p2_i} + {3'd0, p3_i} + {3'd0, p4_i};
            endcase
            calc_checksum = ~sum[7:0];
        end
    endfunction

    assign tx_oe = busy;

    always @(*) begin
        if (byte_index == total_bytes - 1'b1) begin
            current_byte = checksum_r;
        end else begin
            case (byte_index)
                5'd0: current_byte = 8'h55;
                5'd1: current_byte = 8'h55;
                5'd2: current_byte = id_r;
                5'd3: current_byte = len_r;
                5'd4: current_byte = cmd_r;
                5'd5: current_byte = p1_r;
                5'd6: current_byte = p2_r;
                5'd7: current_byte = p3_r;
                5'd8: current_byte = p4_r;
                default: current_byte = 8'h00;
            endcase
        end
    end

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            byte_index    <= 5'd0;
            total_bytes   <= 5'd0;
            id_r          <= 8'd0;
            len_r         <= 8'd0;
            cmd_r         <= 8'd0;
            param_count_r <= 3'd0;
            p1_r          <= 8'd0;
            p2_r          <= 8'd0;
            p3_r          <= 8'd0;
            p4_r          <= 8'd0;
            checksum_r    <= 8'd0;
            uart_start    <= 1'b0;
            busy          <= 1'b0;
            done          <= 1'b0;
        end else begin
            uart_start <= 1'b0;
            done       <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (send_req) begin
                        id_r          <= servo_id;
                        len_r         <= frame_len;
                        cmd_r         <= cmd;
                        param_count_r <= param_count;
                        p1_r          <= param1;
                        p2_r          <= param2;
                        p3_r          <= param3;
                        p4_r          <= param4;
                        checksum_r    <= calc_checksum(servo_id, frame_len, cmd, param_count, param1, param2, param3, param4);
                        byte_index    <= 5'd0;
                        total_bytes   <= frame_len + 5'd3;
                        busy          <= 1'b1;
                        state         <= S_FIRE;
                    end
                end

                S_FIRE: begin
                    uart_start <= 1'b1;
                    state      <= S_WAIT;
                end

                S_WAIT: begin
                    if (uart_done) begin
                        if (byte_index == total_bytes - 1'b1) begin
                            state <= S_DONE;
                        end else begin
                            byte_index <= byte_index + 1'b1;
                            state      <= S_FIRE;
                        end
                    end
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    compat_bus_servo_uart_tx #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD)
    ) u_bus_servo_uart_tx (
        .sys_clk(sys_clk),
        .rst_n(rst_n),
        .start(uart_start),
        .data_in(current_byte),
        .txd(txd),
        .busy(uart_busy),
        .done(uart_done)
    );

endmodule