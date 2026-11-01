`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/28 22:56:32
// Design Name: 
// Module Name: lif_neuron_cell
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module lif_neuron_cell #(
    // 这些参数将在模块被例化时由上一级模块（lif_neuron_layer.v）提供，并应与驱动此模块的电流源的格式匹配。
    parameter P_NEURON_VALUE_TOTAL_BITS      = 26,  // LIF神经元膜电位v和输入电流I的总位宽
    parameter P_NEURON_VALUE_FRAC_BITS = 12   // LIF神经元膜电位v和输入电流I的小数部分位宽
) (
    input wire                                    clk,                    // 时钟信号 (移除了i_前缀)
    input wire                                    rst_n,                  // 异步低电平复位信号 (移除了i_前缀)
    input wire                                    i_clear,                // 同步清空膜电位
    input wire                                    i_enable_neuron,        // 此神经元单元的使能信号
    input wire signed [P_NEURON_VALUE_TOTAL_BITS-1:0]  i_input_current_I,      // 输入电流 I[t] (定点数表示)

    output reg                                    o_spike_out,            // 输出脉冲 (0 或 1)，单周期脉冲行为
    output reg                                    o_spike_valid           // 指示 spike_out 是否有效的信号
);  

    // --- 内部固定参数 (根据输入参数计算) ---
    // 阈值电压 V_THRESHOLD = 1.0
    // 这段代码的目的是安全且正确地将浮点数阈值1.0转换为一个适合硬件使用的定点数表示
    // 以 Q(P_NEURON_VALUE_TOTAL_BITS - P_NEURON_VALUE_FRAC_BITS).(P_NEURON_VALUE_FRAC_BITS) 格式表示，即与输入电流的格式保持一致从而可以进行判断
    localparam signed [P_NEURON_VALUE_TOTAL_BITS-1:0] LP_V_THRESHOLD_FIXED = 
        (P_NEURON_VALUE_FRAC_BITS >= 0 && P_NEURON_VALUE_FRAC_BITS < P_NEURON_VALUE_TOTAL_BITS) ? 
        (1'b1 << P_NEURON_VALUE_FRAC_BITS) : 
        P_NEURON_VALUE_TOTAL_BITS'(1);

    // 复位电压 V_RESET = 0.0
    localparam signed [P_NEURON_VALUE_TOTAL_BITS-1:0] LP_V_RESET_FIXED     = {P_NEURON_VALUE_TOTAL_BITS{1'b0}};
    
    // 时间常数 TAU = 2.0 (硬编码，因为除以2是简单的右移)

    // 内部寄存器，用于存储膜电位 'v'
    reg signed [P_NEURON_VALUE_TOTAL_BITS-1:0] membrane_potential_v_reg;

    // 用于计算的中间信号 (组合逻辑)
    wire signed [P_NEURON_VALUE_TOTAL_BITS-1:0] diff_I_v_comb;             
    wire signed [P_NEURON_VALUE_TOTAL_BITS-1:0] delta_v_component_comb;    
    wire signed [P_NEURON_VALUE_TOTAL_BITS-1:0] v_candidate_potential_comb; 

    // --- 组合逻辑：更新膜电位的计算 ---
    assign diff_I_v_comb = i_input_current_I - membrane_potential_v_reg;
    assign delta_v_component_comb = diff_I_v_comb >>> 1; 
    assign v_candidate_potential_comb = membrane_potential_v_reg + delta_v_component_comb;

    // --- 时序逻辑：脉冲产生和电位复位/更新 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin 
            membrane_potential_v_reg   <= LP_V_RESET_FIXED;    
            o_spike_out                <= 1'b0;               
            o_spike_valid              <= 1'b0;               
        end else begin
            o_spike_valid <= 1'b0; 

            if (i_clear) begin
                membrane_potential_v_reg <= LP_V_RESET_FIXED;
                o_spike_out              <= 1'b0;
            end else if (i_enable_neuron) begin
                o_spike_valid <= 1'b1; 

                if (v_candidate_potential_comb >= LP_V_THRESHOLD_FIXED) begin 
                    o_spike_out                <= 1'b1; 
                    membrane_potential_v_reg   <= LP_V_RESET_FIXED;    
                end else begin 
                    o_spike_out   <= 1'b0; 
                    membrane_potential_v_reg   <= v_candidate_potential_comb; 
                end
            end
        end
    end

    // 移除了调试端口 o_membrane_potential_v_debug 及其 assign 语句

endmodule
