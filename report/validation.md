# 当前验证状态

2026-11-04；源包 xiegithub；工程预览。

## 1. RTL 仿真

Vivado/XSim 2026.1，23/23：上层 10/10、下层 13/13。最终源包测试为上层 10 项、下层 12 项；仓库为 HSV 流水线时序修复增加了 `tb_rgb2hsv_pipeline`。输入及日志哈希见 [summary](../sim/results/summary.json)。首次兼容测试依赖失败仍保留，当前 `tb_arm_stop` 与 65536 样本 HSV 对照均通过。

[检查器自测](checker_tests.json) 11/11：覆盖成功、`FAIL`、`FATAL`、`ERROR`、非零失败计数、缺少完成标记、非零退出码，以及 XPR 文件存在、缺失与越界引用。

## 2. 主 XPR 构建

| 板 | WNS ns | WHS ns | DRC error | loops/no_clock/未约束内部端点 |
| --- | ---: | ---: | ---: | --- |
| 上层 | 5.815 | 0.017 | 0 | 均 0 |
| 下层 | 4.295 | 0.063 | 0 | 均 0 |

两板综合、布局布线及 write_bitstream 实际完成，输入哈希未变，发布 bit 匹配各自主 run。资源见 [resources](resources.csv)，完整证据见 [上层](../build/reports/upper/manifest.json)、[下层](../build/reports/lower/manifest.json)。

当前发布 SHA-256：

- 上层 top.bit：fa947a84887b1c5122325621bc08ea997ad6d7d87d38158eff5c40ea39677918
- 下层 super_top.bit：888f1b1bde28812eac15d66b3261173b01b25e737db220c3aca8278693f5977f

上层 18 输入/37 输出、下层 14 输入/35 输出仍缺 I/O delay，另有时钟路由、复位、CDC、RAM 警告；方法学无 Critical Warning 不等于全板签核。

两板出现 ERROR: [Common 17-354] Could not open 'C' for writing. 之后工具继续完成且门限通过。诊断及上下文在各板 tool_diagnostics.txt/console.txt；不宣称日志无 ERROR，未核实其全部影响。当前为明确带此诊断的预览候选。

## 3. 训练与部署

[数值记录](../training/scnn/verification/verification.json)：规范 COE/MEM、3416 参数往返、4 MEM 字节、异常输入、独立整数 50 步及移动目录通过。现用参数参考帧 [0,50]、黑帧 [0,0]，历史替代结果另记。

[合成训练](../training/scnn/verification/smoke_test.json)：2 样本、3 步，三个张量梯度/更新/导出通过。[5 ROM 语法](../training/scnn/verification/rom_compile.json)、[部署数值](weight_alignment.json) 通过。

无正式数据集，不报告准确率/泛化；未证明完整 RTL 等价、连续帧或物理硬件。

## 4. 来源与复现

source_manifest.json 记录来源及适配，source_integrity.json 记录原源包核对。Git 索引树导出 ZIP 后解压到其他盘符的带空格路径，归档哈希、受检文件数、仿真 23/23、双板主 XPR 构建和交付检查结果见 [relocation](relocation.json)、[详细仿真](relocation_simulation.json) 和 [异路径仓库检查](repository_check_relocation.json)。

异路径重建的 bit 文件头与主工程构建不相同，因此按各自主 run 分别记录 SHA-256；不把“文件不同”误写为功能失败，也不把异路径 bit 混入 `board/bitstreams/`。当前证据由 [delivery_check](delivery_check.json) 核对。

## 5. 物理状态

本次未接硬件、烧录或上板验收。相机、语音、电机、机械臂、供电与动作成功率按 board/measurements.md 采集；不能从仿真或 bit 推出实板通过。

## 6. 作者正式报告

作者提供的 [最终设计报告 PDF](design_report/design_report_v7.pdf) 已按原文件逐字节纳入仓库，共 47 页，PDF SHA-256 为 `dab7a8c09a288848f57c2bc8de6bce1b83b0b4cde04376c84f16d9fad4491b82`。PDF 无表单、JavaScript、批注，47 页均已渲染检查，无空白页或可见版面破损。报告正文仍引用 26/26 测试、6.916/3.591 ns 和原始发布 bit 哈希；仓库当前重建证据为 23/23、5.815/4.295 ns 和 `board/bitstreams/` 所列哈希。两类数据已分别在 [formal_report_source.json](design_report/formal_report_source.json) 中登记，不能互换。

## 7. SCNN 训练部署技能

[scnn-training-pipeline](../skill/scnn-training-pipeline/SKILL.md) 已通过 skill 结构校验和参考工程检查。`--run` 实际执行了 `training/scnn/verify.py` 与 `train.py --smoke-test`：规范参数和参考参数均与独立 50 步整数模型一致，2 个合成样本的梯度、更新和检查点导出通过。记录见 [skill_validation.json](skill_validation.json)。

该检查没有正式数据集，也没有改动 FPGA 工程或重建 bit，因此只证明训练工具、参数转换和定点数值链可运行，不证明识别准确率或实板行为。
