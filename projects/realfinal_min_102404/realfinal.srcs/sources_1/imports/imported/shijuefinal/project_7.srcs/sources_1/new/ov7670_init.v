// OV7670 VGA RGB565 register table; each entry is {register_address, value}.
`timescale 1ns / 1ps

module ov7670_init(
    input  wire clk,
    input  wire rst_n,

    output wire sio_c,
    inout  wire sio_d,
    output reg  init_done
);

    wire i2c_busy;
    reg  i2c_req;
    reg  [7:0] reg_addr;
    reg  [7:0] reg_data;

    reg [15:0] rom [0:78];
    initial begin

        rom[0]  = {8'h12, 8'h80};
        rom[1]  = {8'hFF, 8'hFF};
        rom[2]  = {8'h12, 8'h04};
        rom[3]  = {8'h11, 8'h00};
        rom[4]  = {8'h3E, 8'h00};
        rom[5]  = {8'h0C, 8'h00};
        rom[6]  = {8'h8C, 8'h00};
        rom[7]  = {8'h40, 8'hD0};
        rom[8]  = {8'h1E, 8'h30};

        rom[9]  = {8'h3D, 8'h80};
        rom[10] = {8'h4F, 8'h80};
        rom[11] = {8'h50, 8'h80};
        rom[12] = {8'h51, 8'h00};
        rom[13] = {8'h52, 8'h22};
        rom[14] = {8'h53, 8'h5E};
        rom[15] = {8'h54, 8'h80};
        rom[16] = {8'h58, 8'h9E};
        rom[17] = {8'hB0, 8'h84};

        rom[18] = {8'h13, 8'hE7};
        rom[19] = {8'h14, 8'h18};
        rom[20] = {8'h00, 8'h00};
        rom[21] = {8'h04, 8'h00};
        rom[22] = {8'h10, 8'h00};

        rom[23] = {8'h3B, 8'h0A};
        rom[24] = {8'h9D, 8'h4C};
        rom[25] = {8'h9E, 8'h3F};

        rom[26] = {8'h0E, 8'h61};
        rom[27] = {8'h0F, 8'h4B};
        rom[28] = {8'h16, 8'h02};
        rom[29] = {8'h21, 8'h02};
        rom[30] = {8'h22, 8'h91};
        rom[31] = {8'h29, 8'h07};
        rom[32] = {8'h33, 8'h0B};
        rom[33] = {8'h35, 8'h0B};
        rom[34] = {8'h37, 8'h1D};
        rom[35] = {8'h38, 8'h71};
        rom[36] = {8'h39, 8'h2A};
        rom[37] = {8'h3C, 8'h78};
        rom[38] = {8'h4D, 8'h40};
        rom[39] = {8'h4E, 8'h20};
        rom[40] = {8'h69, 8'h00};

        rom[41] = {8'h70, 8'h3A};
        rom[42] = {8'h71, 8'h35};
        rom[43] = {8'h72, 8'h11};
        rom[44] = {8'h73, 8'hF0};

        rom[45] = {8'hA2, 8'h02};
        rom[46] = {8'h6B, 8'h4A};
        rom[47] = {8'h74, 8'h10};
        rom[48] = {8'h8D, 8'h4F};
        rom[49] = {8'h8E, 8'h00};
        rom[50] = {8'h8F, 8'h00};
        rom[51] = {8'h90, 8'h00};
        rom[52] = {8'h91, 8'h00};
        rom[53] = {8'h96, 8'h00};
        rom[54] = {8'h9A, 8'h00};
        rom[55] = {8'hB1, 8'h0C};
        rom[56] = {8'hB2, 8'h0E};
        rom[57] = {8'hB3, 8'h82};
        rom[58] = {8'hB8, 8'h0A};

        rom[59] = {8'h7A, 8'h20};
        rom[60] = {8'h7B, 8'h10};
        rom[61] = {8'h7C, 8'h1E};
        rom[62] = {8'h7D, 8'h35};
        rom[63] = {8'h7E, 8'h5A};
        rom[64] = {8'h7F, 8'h69};
        rom[65] = {8'h80, 8'h76};
        rom[66] = {8'h81, 8'h80};
        rom[67] = {8'h82, 8'h88};
        rom[68] = {8'h83, 8'h8F};
        rom[69] = {8'h84, 8'h96};
        rom[70] = {8'h85, 8'hA3};
        rom[71] = {8'h86, 8'hAF};
        rom[72] = {8'h87, 8'hC4};
        rom[73] = {8'h88, 8'hD7};
        rom[74] = {8'h89, 8'hE8};

        rom[75] = {8'h15, 8'h00};
        rom[76] = {8'h42, 8'h00};

        rom[77] = {8'hFF, 8'hFF};
        rom[78] = {8'hFE, 8'hFE};
    end

    reg [6:0] idx;
    reg [23:0] delay_cnt;

    sccb_master u_sccb(
        .clk      (clk),
        .rst_n    (rst_n),
        .req      (i2c_req),
        .dev_addr (8'h42),
        .reg_addr (reg_addr),
        .reg_data (reg_data),
        .busy     (i2c_busy),
        .sio_c    (sio_c),
        .sio_d    (sio_d)
    );

    reg [2:0] state;
    localparam S_PWR_UP_DELAY = 3'd0;
    localparam S_IDLE         = 3'd1;
    localparam S_DELAY        = 3'd2;
    localparam S_I2C_REQ      = 3'd3;
    localparam S_I2C_WAIT     = 3'd4;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            idx       <= 5'd0;
            i2c_req   <= 1'b0;
            delay_cnt <= 24'd0;
            init_done <= 1'b0;
            state     <= S_PWR_UP_DELAY;
        end else begin
            case(state)
                S_PWR_UP_DELAY: begin

                    if (delay_cnt < 24'd1_500_000) begin
                        delay_cnt <= delay_cnt + 1'b1;
                    end else begin
                        delay_cnt <= 24'd0;
                        state     <= S_IDLE;
                    end
                end

                S_IDLE: begin
                    if (!init_done && !i2c_busy && !i2c_req) begin
                         if (rom[idx] == 16'hFFFF) begin
                             state <= S_DELAY;
                         end else if (rom[idx] == 16'hFEFE) begin
                             init_done <= 1'b1;
                         end else begin
                             reg_addr <= rom[idx][15:8];
                             reg_data <= rom[idx][7:0];
                             state    <= S_I2C_REQ;
                         end
                    end
                end

                S_DELAY: begin
                    if (delay_cnt < 24'd2_000_000) begin
                        delay_cnt <= delay_cnt + 1'b1;
                    end else begin
                        delay_cnt <= 24'd0;
                        idx       <= idx + 1'b1;
                        state     <= S_IDLE;
                    end
                end

                S_I2C_REQ: begin
                    i2c_req <= 1'b1;
                    if (i2c_req && i2c_busy) begin
                        i2c_req <= 1'b0;
                        state   <= S_I2C_WAIT;
                    end
                end

                S_I2C_WAIT: begin
                    if (!i2c_busy) begin
                        idx   <= idx + 1'b1;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_PWR_UP_DELAY;
            endcase
        end
    end
endmodule
