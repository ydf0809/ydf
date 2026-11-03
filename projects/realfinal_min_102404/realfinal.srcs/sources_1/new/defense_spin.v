// Confirm yaw-limit/edge conditions before bounded chassis rotation; timeout forces stop.
module defense_spin #(
    parameter integer CLK_HZ        = 33_333_333,
    parameter integer IMG_W         = 600,
    parameter integer CENTER_X      = 300,
    parameter integer BOX_HALF_W    = 64,
    parameter integer EDGE_PX       = 30,
    parameter integer YAW_MIN       = 100,
    parameter integer YAW_MAX       = 850,
    parameter integer CONFIRM_MS    = 300,
    parameter integer MIN_SPIN_MS   = 1000,
    parameter integer MAX_SPIN_MS   = 2000,
    parameter integer CENTER_TOL_PX = 60,
    parameter integer REFRESH_MS    = 100,
    parameter signed  [7:0] SPIN_SPEED = 8'sd18,
    parameter integer RIGHT_SIGN    = 1
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        defense_en,
    input  wire        target_valid,
    input  wire [10:0] target_cx,
    input  wire [15:0] yaw_pos,

    output reg         spin_active,
    output reg  signed [7:0] m1,
    output reg  signed [7:0] m2,
    output reg  signed [7:0] m3,
    output reg  signed [7:0] m4,
    output reg         cmd_update
);

localparam [10:0] CX_RIGHT_MIN = IMG_W - 1 - BOX_HALF_W - EDGE_PX;
localparam [10:0] CX_LEFT_MAX  = BOX_HALF_W + EDGE_PX;
localparam [10:0] CX_CENTER_LO = CENTER_X - CENTER_TOL_PX;
localparam [10:0] CX_CENTER_HI = CENTER_X + CENTER_TOL_PX;

localparam integer MS_TICKS      = CLK_HZ / 1000;
localparam integer CONFIRM_TICKS = MS_TICKS * CONFIRM_MS;
localparam integer MIN_TICKS     = MS_TICKS * MIN_SPIN_MS;
localparam integer MAX_TICKS     = MS_TICKS * MAX_SPIN_MS;
localparam integer REFRESH_TICKS = MS_TICKS * REFRESH_MS;

localparam S_IDLE = 1'b0;
localparam S_SPIN = 1'b1;

wire at_right = target_valid && (yaw_pos >= YAW_MAX) && (target_cx >= CX_RIGHT_MIN);
wire at_left  = target_valid && (yaw_pos <= YAW_MIN) && (target_cx <= CX_LEFT_MAX);
wire want     = defense_en && (at_right || at_left);

wire centered = target_valid && (target_cx > CX_CENTER_LO) && (target_cx < CX_CENTER_HI);

reg        state;
reg        dir_right;
reg [31:0] confirm_cnt;
reg [31:0] spin_cnt;
reg [31:0] refresh_cnt;

wire dir_cond_now = dir_right ? at_right : at_left;
wire dir_lost     = target_valid && !dir_cond_now;
wire early_stop   = (spin_cnt >= MIN_TICKS - 1) && (centered || dir_lost);
wire time_out     = (spin_cnt >= MAX_TICKS - 1);

wire turn_right_now = (RIGHT_SIGN > 0) ? at_right : ~at_right;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= S_IDLE;
        dir_right   <= 1'b0;
        confirm_cnt <= 32'd0;
        spin_cnt    <= 32'd0;
        refresh_cnt <= 32'd0;
        spin_active <= 1'b0;
        cmd_update  <= 1'b0;
        m1 <= 8'sd0; m2 <= 8'sd0; m3 <= 8'sd0; m4 <= 8'sd0;
    end else begin
        cmd_update <= 1'b0;

        case (state)
            S_IDLE: begin
                if (want) begin
                    if (confirm_cnt >= CONFIRM_TICKS - 1) begin
                        dir_right   <= at_right;
                        spin_cnt    <= 32'd0;
                        refresh_cnt <= 32'd0;
                        confirm_cnt <= 32'd0;
                        spin_active <= 1'b1;
                        cmd_update  <= 1'b1;
                        m1 <=  turn_right_now ?  SPIN_SPEED : -SPIN_SPEED;
                        m2 <=  turn_right_now ? -SPIN_SPEED :  SPIN_SPEED;
                        m3 <=  turn_right_now ?  SPIN_SPEED : -SPIN_SPEED;
                        m4 <=  turn_right_now ? -SPIN_SPEED :  SPIN_SPEED;
                        state <= S_SPIN;
                    end else begin
                        confirm_cnt <= confirm_cnt + 1'b1;
                    end
                end else begin
                    confirm_cnt <= 32'd0;
                end
            end

            S_SPIN: begin
                spin_cnt <= spin_cnt + 1'b1;

                if (refresh_cnt >= REFRESH_TICKS - 1) begin
                    refresh_cnt <= 32'd0;
                    cmd_update  <= 1'b1;
                end else begin
                    refresh_cnt <= refresh_cnt + 1'b1;
                end

                if (!defense_en || time_out || early_stop) begin
                    spin_active <= 1'b0;
                    spin_cnt    <= 32'd0;
                    confirm_cnt <= 32'd0;
                    m1 <= 8'sd0; m2 <= 8'sd0; m3 <= 8'sd0; m4 <= 8'sd0;
                    state <= S_IDLE;
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
