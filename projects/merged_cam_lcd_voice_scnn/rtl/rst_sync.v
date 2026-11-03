// Asynchronous reset assertion and synchronous release in the destination clock domain.
module rst_sync #(
    parameter BTN_ACTIVE_LOW = 1
)(
    input       sys_clk     ,
    input       btn_n       ,

    output      rst_n
);

wire btn_rst;

reg rst_meta;
reg rst_sync_r;

assign btn_rst = BTN_ACTIVE_LOW ? (~btn_n) : btn_n;

always @(posedge sys_clk or posedge btn_rst) begin
    if(btn_rst) begin
        rst_meta   <= 1'b1;
        rst_sync_r <= 1'b1;
    end
    else begin
        rst_meta   <= 1'b0;
        rst_sync_r <= rst_meta;
    end
end

assign rst_n = ~rst_sync_r;

endmodule
