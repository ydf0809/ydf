`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/28 22:55:16
// Design Name: 
// Module Name: neuron_processing_unit
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


module neuron_processing_unit #(
    parameter P_NUM_INPUT_PIXELS       = 784,
    parameter P_WEIGHT_BIT_WIDTH       = 16,
    parameter P_NEURON_VALUE_TOTAL_BITS = 26,
    parameter P_NEURON_VALUE_FRAC_BITS  = 12,

    parameter P_BRAM_DATA_WIDTH        = 64,
    parameter P_BRAM_ADDR_WIDTH        = 8,
    parameter P_BRAM_EFFECTIVE_DEPTH   = 196
) (
    input wire                                          clk,
    input wire                                          rst_n,
    input wire                                          i_calc_start,
    input wire  [P_NUM_INPUT_PIXELS-1:0]                i_input_spike_vector,
    input wire signed [P_BRAM_DATA_WIDTH-1:0]           i_bram_dout_raw,      // 从外部BRAM读取的数据输入端，BRAM原始数据输出

    output reg [P_BRAM_ADDR_WIDTH-1:0]                  o_bram_addr_to_issue, // 控制外部BRAM的输出端口，当前要发送给BRAM的地址
    output reg                                          o_bram_ena,           // 控制外部BRAM的输出端口，BRAM使能信号
    output reg signed [P_NEURON_VALUE_TOTAL_BITS-1:0]    o_output_current_I,
    output reg                                          o_current_valid_out
);

    // ------------------- 内部常量和状态定义 (根据参数计算) -------------------
    localparam WEIGHTS_NUMS_PER_WORD = P_BRAM_DATA_WIDTH / P_WEIGHT_BIT_WIDTH;
    localparam ADDR_MAX_VAL           = P_BRAM_EFFECTIVE_DEPTH - 1;
    localparam BRAM_READ_LATENCY      = 2;
    // 计数器需能表示到 P_BRAM_EFFECTIVE_DEPTH(含), 故用 clog2(DEPTH+1)。
    // 当 DEPTH 为 2 的幂时(如 256), clog2(DEPTH)=8 只能数到 255, 会卡死; clog2(DEPTH+1)=9 才正确。
    // 对非 2 的幂(如 196) 与原 P_BRAM_ADDR_WIDTH 一致, 不改变原有行为。
    localparam LP_CNT_WIDTH           = $clog2(P_BRAM_EFFECTIVE_DEPTH + 1);
    localparam NUM_INPUT_PIXELS_BITS  = $clog2(P_NUM_INPUT_PIXELS);

    localparam STATE_BITS           = 2;
    localparam S_IDLE_VAL           = 2'b00;  // 00: 空闲状态，等待开始信号
    localparam S_PROCESSING_VAL     = 2'b01;  // 01: 流水线处理中 (包括填充和稳定运行)
    localparam S_FLUSHING_VAL       = 2'b10;  // 10: 停止发起新的BRAM读取，等待流水线中剩余 2 个数据处理完毕
    localparam S_DONE_VAL           = 2'b11;  // 11: 所有数据处理完毕，输出结果 (此状态实际只持续一个周期用于置位valid信号)

    reg [STATE_BITS-1:0] current_state_reg, next_state_reg;

    // 内部寄存器
    reg [P_NUM_INPUT_PIXELS-1:0]                   latched_spike_vector_reg; // 接收并锁存住 i_input_spike_vector
    reg signed [P_NEURON_VALUE_TOTAL_BITS-1:0]      accumulator_reg;          // 累加器，不断计算权重之和

    // 流水线寄存器，用于对齐延迟的BRAM数据和对应的原始地址（用于索引脉冲），定义为二维数组
    // 深度为BRAM_READ_LATENCY级，也即从时钟上升沿发送BRAM地址请求到得到数据需要两个时钟周期
    reg [P_BRAM_ADDR_WIDTH-1:0]                    addr_pipeline_reg  [BRAM_READ_LATENCY-1:0]; // 作为流水寄存器锁存要发给BRAM的地址 o_bram_addr_to_issue, addr_pipeline_reg[0]是第一级 (直接来自BRAM)，addr_pipeline_reg[1]是最后一级
    reg                                            valid_pipeline_reg [BRAM_READ_LATENCY-1:0]; // 作为流水寄存器锁存BRAM的数据使能信号 o_bram_ena, 值为1时说明进行了BRAM读取请求并使其与对应的地址在流水线中同步前进，但是注意该请求对应的数据在两个时钟之后。检测到这个值为0时意味着已经全部请求已经完了

    // processed_data_count_reg 会比 issued_addr_count_reg 少 2, 因为数据滞后于请求两个时钟
    reg [LP_CNT_WIDTH-1:0]                  issued_addr_count_reg;
    reg [LP_CNT_WIDTH-1:0]                  processed_data_count_reg;

    // 数据处理
    wire signed [P_NEURON_VALUE_TOTAL_BITS-1:0] terms_comb [WEIGHTS_NUMS_PER_WORD-1:0]; // 存储条件化和符号扩展后的权重
    wire signed [P_NEURON_VALUE_TOTAL_BITS-1:0] sum_of_N_active_weights_comb;           // 一个权重包和对应的输入脉冲的加和

    integer k_idx; 
    genvar j_gen, l_gen, m_gen;

    // ------------------- 时序逻辑：状态机和寄存器更新 -------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state_reg        <= S_IDLE_VAL;
            latched_spike_vector_reg <= {P_NUM_INPUT_PIXELS{1'b0}};
            accumulator_reg          <= {P_NEURON_VALUE_TOTAL_BITS{1'b0}};
            o_bram_addr_to_issue     <= {P_BRAM_ADDR_WIDTH{1'b0}}; // 初始化输出端口
            issued_addr_count_reg    <= {P_BRAM_ADDR_WIDTH{1'b0}};
            processed_data_count_reg <= {P_BRAM_ADDR_WIDTH{1'b0}};
            o_output_current_I       <= {P_NEURON_VALUE_TOTAL_BITS{1'b0}};
            o_current_valid_out      <= 1'b0;
            for (k_idx = 0; k_idx < BRAM_READ_LATENCY; k_idx = k_idx + 1) begin
                addr_pipeline_reg[k_idx]  <= {P_BRAM_ADDR_WIDTH{1'b0}};
                valid_pipeline_reg[k_idx] <= 1'b0;
            end
        end else begin
            current_state_reg   <= next_state_reg;
            o_current_valid_out <= 1'b0; // 默认为无效，只在DONE状态的一个周期有效

            // --- 根据当前状态更新主要寄存器 ---
            // 下面的表达与 if (current_state_reg == S_IDLE_VAL && i_calc_start) 语句作用一样
            if (current_state_reg == S_IDLE_VAL && next_state_reg == S_PROCESSING_VAL) begin
                latched_spike_vector_reg <= i_input_spike_vector;
                accumulator_reg          <= {P_NEURON_VALUE_TOTAL_BITS{1'b0}};
                o_bram_addr_to_issue     <= {P_BRAM_ADDR_WIDTH{1'b0}};
                issued_addr_count_reg    <= {P_BRAM_ADDR_WIDTH{1'b0}};
                processed_data_count_reg <= {P_BRAM_ADDR_WIDTH{1'b0}};
            
                for (k_idx = 0; k_idx < BRAM_READ_LATENCY; k_idx = k_idx + 1) begin
                    valid_pipeline_reg[k_idx] <= 1'b0;
                end
            end

            // --- 流水线移位逻辑 ---
            // 这个移位总是在进行，除非被特定条件控制 (例如，只在S_PROCESSING或S_FLUSHING状态)
            if (current_state_reg == S_PROCESSING_VAL || current_state_reg == S_FLUSHING_VAL) begin
                // 数据流水线移位
                for (k_idx = BRAM_READ_LATENCY - 1; k_idx > 0; k_idx = k_idx - 1) begin
                    addr_pipeline_reg[k_idx]  <= addr_pipeline_reg[k_idx-1];
                    valid_pipeline_reg[k_idx] <= valid_pipeline_reg[k_idx-1];
                end
                valid_pipeline_reg[0] <= o_bram_ena;            // o_bram_ena 是当前周期的使能信号(由组合逻辑FSM确定)
                addr_pipeline_reg[0]  <= o_bram_addr_to_issue;  // 如果BRAM被使能读取，则进入流水线的数据是有效的
            end
            if ((current_state_reg == S_PROCESSING_VAL || current_state_reg == S_FLUSHING_VAL) && valid_pipeline_reg[BRAM_READ_LATENCY-1]) begin
                accumulator_reg          <= accumulator_reg + sum_of_N_active_weights_comb;
                processed_data_count_reg <= processed_data_count_reg + 1;
            end

            if (current_state_reg == S_PROCESSING_VAL && o_bram_ena) begin
                issued_addr_count_reg  <= issued_addr_count_reg + 1;
                if (o_bram_addr_to_issue < ADDR_MAX_VAL) begin
                    o_bram_addr_to_issue <= o_bram_addr_to_issue + 1; 
                end
            end
            
            if (current_state_reg == S_DONE_VAL) begin  // 如果计算完成
                o_output_current_I  <= accumulator_reg; // 输出最终的累加和
                o_current_valid_out <= 1'b1;            // 指示输出有效
            end
        end
    end

    // ------------------- 组合逻辑：状态转移控制 和 当前周期的部分和计算 -------------------
    // 1 个地址对应 ----- 1 个权重包输入 -----> 解包出 4 个权重 -----> 对应的输入脉冲也要打包出 4 个进行对应
    wire signed [P_WEIGHT_BIT_WIDTH-1:0]       w_from_bram        [WEIGHTS_NUMS_PER_WORD-1:0];
    wire                                       s_for_aligned_addr [WEIGHTS_NUMS_PER_WORD-1:0]; 
    
    generate 
        for (j_gen = 0; j_gen < WEIGHTS_NUMS_PER_WORD; j_gen = j_gen + 1) begin : gen_unpack_weights
            assign w_from_bram[j_gen] = i_bram_dout_raw[(j_gen+1)*P_WEIGHT_BIT_WIDTH-1 : j_gen*P_WEIGHT_BIT_WIDTH];  // 从输入端口读取
        end
    endgenerate

    generate 
        for (l_gen = 0; l_gen < WEIGHTS_NUMS_PER_WORD; l_gen = l_gen + 1) begin : gen_select_spikes
            // logical_offset_in_group 用来实现每一组包内的数据对应
            localparam logical_offset_in_group_g = (WEIGHTS_NUMS_PER_WORD - 1) - l_gen;
            wire [P_BRAM_ADDR_WIDTH-1:0] current_word_addr_from_pipe_w; 
            assign current_word_addr_from_pipe_w = addr_pipeline_reg[BRAM_READ_LATENCY-1]; // 当前处理的BRAM字地址，每一个地址含4个权重，也即需要4个输入脉冲
            // global_raster_idx_of_spike 用于记录对应于 s_pipe_out[l_gen] 的脉冲在784个总输入中的绝对光栅扫描索引
            wire [NUM_INPUT_PIXELS_BITS-1:0] global_raster_idx_of_spike_w; 
            assign global_raster_idx_of_spike_w    = (current_word_addr_from_pipe_w * WEIGHTS_NUMS_PER_WORD) + logical_offset_in_group_g;
            assign s_for_aligned_addr[l_gen] = latched_spike_vector_reg[P_NUM_INPUT_PIXELS - 1 - global_raster_idx_of_spike_w]; 
        end
    endgenerate

    generate
        for (m_gen = 0; m_gen < WEIGHTS_NUMS_PER_WORD; m_gen = m_gen + 1) begin : gen_terms_for_sum
            assign terms_comb[m_gen] = s_for_aligned_addr[m_gen] ? // 如果对应脉冲有效
                                {{(P_NEURON_VALUE_TOTAL_BITS - P_WEIGHT_BIT_WIDTH){w_from_bram[m_gen][P_WEIGHT_BIT_WIDTH-1]}}, w_from_bram[m_gen]} :  // 符号扩展
                                {P_NEURON_VALUE_TOTAL_BITS{1'b0}}; // 否则为0
        end
    endgenerate
    
    assign sum_of_N_active_weights_comb = terms_comb[0] + terms_comb[1] + terms_comb[2] + terms_comb[3];

    // 状态转移逻辑 和 BRAM使能控制 (组合逻辑 always 块，带显式敏感列表)
    always @(current_state_reg or i_calc_start or issued_addr_count_reg or processed_data_count_reg) begin
        next_state_reg = current_state_reg; // 默认保持当前状态
        o_bram_ena     = 1'b0;              // 控制外部BRAM的使能，默认为低
        case (current_state_reg)
            S_IDLE_VAL: begin
                if (i_calc_start) begin
                    next_state_reg = S_PROCESSING_VAL;
                end
            end
            S_PROCESSING_VAL: begin
                // 持续发出BRAM读取请求，直到所有地址都已发出
                // issued_addr_count_reg 从0开始计数，当它达到 P_BRAM_EFFECTIVE_DEPTH 时，表示已经发出了 P_BRAM_EFFECTIVE_DEPTH 个地址
                if (issued_addr_count_reg < P_BRAM_EFFECTIVE_DEPTH) begin
                    o_bram_ena     = 1'b1;              // 使能BRAM读取
                    next_state_reg = S_PROCESSING_VAL;  // 保持在处理状态
                end else begin // 所有地址都已发出 (即 issued_addr_count_reg == P_BRAM_EFFECTIVE_DEPTH)
                    o_bram_ena     = 1'b0;
                    next_state_reg = S_FLUSHING_VAL; 
                end
            end
            S_FLUSHING_VAL: begin
                o_bram_ena = 1'b0;  // 不再发起新的BRAM读取
                // processed_data_count_reg 从0开始计数，当它达到 P_BRAM_EFFECTIVE_DEPTH 时，表示所有发出的数据都已被处理
                if (processed_data_count_reg == P_BRAM_EFFECTIVE_DEPTH) begin
                    next_state_reg = S_DONE_VAL;    // 所有数据处理完毕
                end else begin
                    next_state_reg = S_FLUSHING_VAL; // 继续等待流水线中剩余数据处理完毕
                end
            end
            S_DONE_VAL: begin
                next_state_reg = S_IDLE_VAL; // 完成，返回空闲状态
            end
            default: next_state_reg = S_IDLE_VAL;
        endcase
    end

endmodule

