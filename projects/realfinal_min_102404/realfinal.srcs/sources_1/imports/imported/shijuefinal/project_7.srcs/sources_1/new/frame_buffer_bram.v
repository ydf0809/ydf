// Camera-write/system-read frame buffer; page ownership is exchanged outside the RAM.
`timescale 1ns / 1ps

module frame_buffer_bram(
    input  wire        clka,
    input  wire        wea,
    input  wire [17:0] addra,
    input  wire [15:0] dina,

    input  wire        clkb,
    input  wire [17:0] addrb,
    output reg  [15:0] doutb
);

    (* ram_style = "block" *) reg [15:0] ram [0:262143];

    always @(posedge clka) begin
        if (wea) begin
            ram[addra] <= dina;
        end
    end

    always @(posedge clkb) begin
        doutb <= ram[addrb];
    end

endmodule
