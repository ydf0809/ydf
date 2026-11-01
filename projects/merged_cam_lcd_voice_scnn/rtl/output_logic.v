`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/28 22:57:35
// Design Name: 
// Module Name: output_logic
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


module output_logic #(
    parameter P_NUM_OUTPUT_NEURONS = 10,  // 输出神经元的数量
    parameter P_T_MAX              = 100  // SNN总时间步数 (用于确定计数器位宽)
) (
    input wire                               clk,
    input wire                               rst_n,

    // 控制信号 (来自 control_unit.v)
    input wire                               i_accum_en,                 // 单周期脉冲，使能当前时间步的脉冲累加，由 control 和 i_lif_spikes_valid 共同协商得出的信号
    input wire                               i_decision_en,              // 单周期脉冲，使能最终决策逻辑，也即在所有时间步计算后准备找出最大值

    // 来自LIF神经元层的数据 (lif_neuron_layer.v)  
    input wire [P_NUM_OUTPUT_NEURONS-1:0]    i_lif_spike_vector,         // LIF层的脉冲输出向量

    // 输出结果
    output reg [$clog2(P_NUM_OUTPUT_NEURONS)-1:0] o_predicted_label,      // 预测的类别标签
    output reg [$clog2(P_T_MAX + 1)-1:0]       o_max_spike_count,      // 最终的预测结果对应的脉冲计数值
    output reg [P_NUM_OUTPUT_NEURONS*$clog2(P_T_MAX + 1)-1:0] o_all_spike_counts,
    output reg                                   o_prediction_valid      // 最终经过所有时间步的结果，指示 o_predicted_label 和 o_max_spike_count 是否有效 (单周期脉冲)
);

    // 内部常量定义
    // 脉冲计数器的位宽，需要能存下 P_T_MAX (因为一个神经元最多每步发一个脉冲)
    // 例如 P_T_MAX=100, $clog2(100+1)=7 (可以计数0到100)
    localparam LP_SPIKE_COUNTER_BITS = $clog2(P_T_MAX + 1); 
    // 预测标签的位宽
    localparam LP_LABEL_WIDTH        = $clog2(P_NUM_OUTPUT_NEURONS);

    // 内部寄存器
    reg [LP_SPIKE_COUNTER_BITS-1:0] spike_counters_reg [P_NUM_OUTPUT_NEURONS-1:0];// 内部寄存器，用于存储每个输出神经元的脉冲计数值
    reg [LP_SPIKE_COUNTER_BITS-1:0] max_count_val_internal; // 用于内部计算最大计数值
    reg [LP_LABEL_WIDTH-1:0]        max_index_val_internal; // 用于内部计算最大计数值对应的索引
    
    // --- 时序逻辑：脉冲累加和决策 ---
    always @(posedge clk or negedge rst_n) begin
        integer i_loop_local;
        integer j_findmax_local;

        if (!rst_n) begin
            for (i_loop_local = 0; i_loop_local < P_NUM_OUTPUT_NEURONS; i_loop_local = i_loop_local + 1) begin
                spike_counters_reg[i_loop_local] <= {LP_SPIKE_COUNTER_BITS{1'b0}};
            end
            o_predicted_label      <= {LP_LABEL_WIDTH{1'b0}};
            o_max_spike_count      <= {LP_SPIKE_COUNTER_BITS{1'b0}}; // 初始化新输出
            o_all_spike_counts     <= {P_NUM_OUTPUT_NEURONS*LP_SPIKE_COUNTER_BITS{1'b0}};
            o_prediction_valid     <= 1'b0;
            max_count_val_internal <= {LP_SPIKE_COUNTER_BITS{1'b0}}; // 初始化内部计算用reg
            max_index_val_internal <= {LP_LABEL_WIDTH{1'b0}};       // 初始化内部计算用reg
        end else begin
            o_prediction_valid <= 1'b0; // 默认为无效，只在决策完成的那个周期为高
            if (i_accum_en) begin
                // 当使能累加 并且 LIF层的脉冲数据有效时，更新所有计数器
                for (i_loop_local = 0; i_loop_local < P_NUM_OUTPUT_NEURONS; i_loop_local = i_loop_local + 1) begin
                    if (i_lif_spike_vector[i_loop_local] == 1'b1) begin // 如果对应神经元发放了脉冲
                        spike_counters_reg[i_loop_local] <= spike_counters_reg[i_loop_local] + 1;
                    end
                end
            end

            if (i_decision_en) begin // 当决策使能信号有效时
                // --- 寻找最大脉冲计数的神经元 ---
                max_count_val_internal = spike_counters_reg[0];       // 初始化最大值为第一个神经元的计数值
                max_index_val_internal = {LP_LABEL_WIDTH{1'b0}};      // 初始化最大值索引为0
                for (j_findmax_local = 1; j_findmax_local < P_NUM_OUTPUT_NEURONS; j_findmax_local = j_findmax_local + 1) begin
                    if (spike_counters_reg[j_findmax_local] > max_count_val_internal) begin
                        max_count_val_internal = spike_counters_reg[j_findmax_local];
                        max_index_val_internal = j_findmax_local; // Verilog允许将范围内的整数赋给位向量
                    end
                end
                // --- 寻找最大值结束 ---
                o_predicted_label      <= max_index_val_internal; // 输出最大值神经元的索引作为预测标签
                o_max_spike_count      <= max_count_val_internal; // 输出最大脉冲计数值
                for (i_loop_local = 0; i_loop_local < P_NUM_OUTPUT_NEURONS; i_loop_local = i_loop_local + 1) begin
                    o_all_spike_counts[i_loop_local*LP_SPIKE_COUNTER_BITS +: LP_SPIKE_COUNTER_BITS]
                        <= spike_counters_reg[i_loop_local];
                end
                o_prediction_valid     <= 1'b1;                   // 指示预测结果有效
                // 在决策输出后，立即重置所有脉冲计数器为零
                for (i_loop_local = 0; i_loop_local < P_NUM_OUTPUT_NEURONS; i_loop_local = i_loop_local + 1) begin
                    spike_counters_reg[i_loop_local] <= {LP_SPIKE_COUNTER_BITS{1'b0}};
                end
            end
        end
    end

endmodule
