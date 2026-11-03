# 当前验证状态

2026-11-03；源包 xiegithub；工程预览。

## 1. RTL 仿真

Vivado/XSim 2026.1，26/26：上层 11/11、下层 15/15。输入及日志哈希见 [summary](../sim/results/summary.json)。首次 3 项辅助模块漏编的展开失败保留，修正入口重跑，不改生产断言。旧提交 745a0bd 的 15/16 不再是当前结论；当前 tb_arm_stop 通过。

[检查器自测](checker_tests.json) 11/11：覆盖成功、`FAIL`、`FATAL`、`ERROR`、非零失败计数、缺少完成标记、非零退出码，以及 XPR 文件存在、缺失与越界引用。

## 2. 主 XPR 构建

| 板 | WNS ns | WHS ns | DRC error | loops/no_clock/未约束内部端点 |
| --- | ---: | ---: | ---: | --- |
| 上层 | 6.916 | 0.032 | 0 | 均 0 |
| 下层 | 3.591 | 0.019 | 0 | 均 0 |

两板综合、布局布线及 write_bitstream 实际完成，输入哈希未变，发布 bit 匹配各自主 run。资源见 [resources](resources.csv)，完整证据见 [上层](../build/reports/upper/manifest.json)、[下层](../build/reports/lower/manifest.json)。

当前发布 SHA-256：

- 上层 top.bit：3822d7b6b398c6304d12f5ec6bcb4a163b91a73ea6a1a0e284a8d547b2f05dcc
- 下层 super_top.bit：8911d7eee5fcab0bfe1b4b313eb99dffd1d2b3782bfea487405700b4d01266c6

上层 18 输入/37 输出、下层 14 输入/35 输出仍缺 I/O delay，另有时钟路由、复位、CDC、RAM 警告；方法学无 Critical Warning 不等于全板签核。

两板出现 ERROR: [Common 17-354] Could not open 'C' for writing. 之后工具继续完成且门限通过。诊断及上下文在各板 tool_diagnostics.txt/console.txt；不宣称日志无 ERROR，未核实其全部影响。当前为明确带此诊断的预览候选。

## 3. 训练与部署

[数值记录](../training/scnn/verification/verification.json)：规范 COE/MEM、3416 参数往返、4 MEM 字节、异常输入、独立整数 50 步及移动目录通过。现用参数参考帧 [0,50]、黑帧 [0,0]，历史替代结果另记。

[合成训练](../training/scnn/verification/smoke_test.json)：2 样本、3 步，三个张量梯度/更新/导出通过。[5 ROM 语法](../training/scnn/verification/rom_compile.json)、[部署数值](weight_alignment.json) 通过。

无正式数据集，不报告准确率/泛化；未证明完整 RTL 等价、连续帧或物理硬件。

## 4. 来源与复现

source_manifest.json 记录来源及适配，source_integrity.json 记录原源包核对。Git 索引树 `940bb17628caed3c7adb9e753de8b9b3fb03904d` 导出 ZIP 后解压到其他盘符的带空格路径，归档 SHA-256 为 `ed9c1ef332a0d2c6347876957bf8a05f8cbd8c570cb904063d4c674248e9ea1f`。异路径仓库检查 310 文件、仿真 26/26、双板主 XPR 构建及交付检查均通过，见 [relocation](relocation.json)、[详细仿真](relocation_simulation.json) 和 [异路径仓库检查](repository_check_relocation.json)。

异路径重建的 bit 文件头与主工程构建不相同，因此按各自主 run 分别记录 SHA-256；不把“文件不同”误写为功能失败，也不把异路径 bit 混入 `board/bitstreams/`。当前证据由 [delivery_check](delivery_check.json) 核对。

## 5. 物理状态

本次未接硬件、烧录或上板验收。相机、语音、电机、机械臂、供电与动作成功率按 board/measurements.md 采集；不能从仿真或 bit 推出实板通过。
