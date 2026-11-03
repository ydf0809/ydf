# 双板 FPGA 视觉识别与运动控制平台设计报告

工程预览；2026-11-03；依据指定 xiegithub 源包和本次运行。正式作品名称、应用背景、相关工作与创新论证待所有者补充，不据功能组合宣称领先。

## 1. 原理与功能框图

~~~mermaid
flowchart LR
    camera1[OV5640] --> rgb[彩色ROI与定位]
    rgb --> scnn[SCNN分类]
    scnn --> state[搜索锁定及复检]
    rgb --> state
    voice[UART语音] --> upper[上层控制]
    state --> upper
    state --> lcd1[上层LCD]
    upper <-->|UART模式及目标信息| lower[下层控制]
    camera2[OV7670] --> hsv[流水HSV与视觉]
    hsv --> lower
    lower --> lcd2[下层LCD]
    lower --> motor[底盘I2C]
    lower --> arm[机械臂UART]
    train[Python训练与转换] -.离线ROM.-> scnn
~~~

## 2. 软硬件划分与接口

两板均为 xc7z020clg400-1，top/super_top，以 PL RTL 为主；不声称使用 PS/HLS/PYNQ。相机、定位、推理、通信、显示与控制在 FPGA，训练/微调、转换及数值校验在 Python。双板原始划分的资源、成本与延迟取舍尚需补充。

系统约束 33.333 MHz；上层相机约束 25 MHz、SCCB 系统分频 32；下层相机约束 48 MHz。均是配置/约束值，未作仪器测量。引脚及 UART 115200/8N1 见 [board](../board/README.md)，以当前 XDC/引脚报告为准。

多位框跨域采用完整快照与握手；模式/复位需区分命令事件和状态值。I2C 停车等待当前事务原子完成后发完整新包。相应仿真不代替物理执行机构响应。

## 3. 模型、定位与权重

64×64×3 输入；Conv 3→8、OR pool、Conv 8→16、两次 OR pool、FC 1024→2，无 bias，3416 参数、50 步。RRGGBB 帧低字节先取形成 B/G/R 张量，0=not_drone、1=drone，平票取 0。权重 signed16 Q12、膜电位 26 位，回绕/算术移位/发放清零见 [model_spec](../training/scnn/model_spec.json)。

当前规范 COE/MEM、默认参数与实际登记的四个权重 ROM、一个参考帧 ROM 一致，见 [weight_alignment](weight_alignment.json)。历史替代 COE 单独保留。转换器能生成最终工程格式，新模型替换仍需审核、相关仿真和主 XPR 重建。

位置和身份分类职责不同。当前源码约每 1 秒复检，连续 5 个已完成的无人机计数≤15 结果可经该通道脱锁，另有丢失帧复核。历史 2 秒/10 脉冲属于旧版本，不作为当前参数。软件参考仅从全局复位的一帧起步，不声称连续帧或完整 RTL 形式等价。

## 4. 实施与优化证据

源包已包含 HSV 流水、相机同步、框 CDC、时钟及控制修正；本次开源整理不改变生产 RTL、引脚、时钟或阈值，只适配路径、可选增量依赖、入口和训练来源校验。

[资源汇总](resources.csv)：上层 LUT 23316、寄存器 12149、BRAM tile 109.5、DSP 0；下层 LUT 4573、寄存器 3136、BRAM tile 128、DSP 4。口径以 build/reports 实现报告为准。

| 项目 | 基线 | 当前证据 | 结论 |
| --- | --- | --- | --- |
| 同条件资源/频率优化 | 无完整可比版本 | 当前资源、约束、时序 | 不计算收益 |
| 准确率、误报/漏报 | 无固定数据集 | 功能参考与合成训练 | 不评价精度 |
| 延迟、吞吐、成功率、功耗 | 无实测定义/原始数据 | 尚缺 | 未验证 |

不能用 WNS 推算整机吞吐，不能把路径整理或重建写成算法优化。

## 5. 验证与复现

本次 26/26 回归、模型数值/合成流程/ROM 语法及部署检查通过；双板由仓库主 XPR 生成 bit。上层 WNS/WHS +6.916/+0.032 ns，下层 +3.591/+0.019 ns，DRC error/组合环/no_clock/未约束内部端点均 0。其余 I/O/CDC 等警告及工具诊断见 [验证状态](validation.md)。

[从零复现](reproduction.md) 给出环境、静态检查、训练、仿真、构建、异路径归档和上板顺序；迁移证据见 relocation.json。尚未烧录和实板验收，不能据仿真或 bit 代替硬件结果。

## 6. 协作与技能提炼

[19 条原文节选](collaboration/README.md) 包含真实提示词、模型可见回答和索引；[协作报告](ai_collaboration.md) 记录自我纠错及实际单智能体流程。技能从权重混用、实例覆盖、定位身份、CDC/I2C、构建误判提炼，见 [skill](../skill/README.md)。

不补造原始训练记录、性能数字或多智能体过程。缺项见 [owner_inputs](owner_inputs.md)，预览不等于完整参赛验收；GitHub 继续暂停。
