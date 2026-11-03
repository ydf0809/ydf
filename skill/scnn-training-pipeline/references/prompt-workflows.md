# Prompt Workflows

These templates guide a language model without delegating evidence to it. Replace angle-bracket placeholders, attach only the minimum source and logs, and require local verification after the answer.

## Shared rules

Put these constraints at the end of every prompt:

```text
工作边界：
1. 先区分事实、推断和待验证项；不要把模型回答当作编译或实板证据。
2. 先读源码、配置、日志与工具输出，再提出修改。
3. 涉及 RTL、权重、引脚、时钟、阈值或接口时，说明影响范围和回滚条件。
4. 保留首次失败日志；修复后给出命令、退出码、PASS/FAIL 标记和输入哈希。
5. 没有数据集、时序报告或实板记录时，明确写“未验证”，不要补造指标。
```

## 1. Plan before modification

```text
你正在审查 FPGA SCNN 工程：<project-root>。
目标：<desired behavior>。
只读文件：<model_spec.json, RTL entry, training scripts, current logs>。

先输出：
- 当前实现事实与源码位置；
- 需要改变的接口、权重、tensor/ROM 映射和构建输入；
- 最小实现方案；
- 每一步的验证方法与停止条件；
- 未验证的假设和回滚点。

此轮不要改文件。等待确认后再实施。
```

## 2. Tensor and RTL mapping review

```text
比较 <model_spec.json>、<training checkpoint/JSON> 与 <RTL files>。
检查输入 channel order、卷积 lane order、FC word order、flatten order、
Q4.12/Q13.12 位宽、LIF 更新、OR pooling、timestep 和 class tie-break。

用表格列出“软件位置—RTL位置—位段/顺序—证据—风险”。
给出可执行的独立哨兵输入，至少覆盖正负权重、通道边界和 FC 高低 16 位。
不要仅凭数值看起来接近就宣布等价。
```

## 3. Weight migration

```text
候选权重来源：<COE/MEM/JSON/checkpoint paths>。
当前 XPR 实际编译的 ROM：<path>。
要求：
- 分别解析 header、字宽、深度、signedness 和实际数据；
- 比较 COE、MEM、生成 ROM、XPR 登记 ROM；
- 说明历史参考与当前部署参数的区别；
- 给出参数数量、字数和 SHA-256；
- 若不一致，输出第一处差异及最小复现命令。
不要通过“同名文件”或只改外部 COE 推断硬件已更新。
```

## 4. Failure diagnosis

```text
失败阶段：<compile/elaborate/simulate/synth/route/bit/program/train/eval>。
输入与命令：<command>
首次失败日志：<log path>
最后一次已知 PASS：<evidence path>

请按“触发条件—首个异常—受影响模块—最小复现—候选修复—验证命令—剩余风险”
输出。不要扩写成全工程重审；不要删除原始失败记录；不要用最终 PASS 覆盖首次失败。
```

## 5. Self-correction trace

```text
请把本次纠错整理成以下结构，不输出隐藏推理：
1. 初始判断；
2. 反证/观察；
3. 新证据；
4. 修正动作；
5. 复跑结果；
6. 仍然不能证明的部分；
7. 可复用教训。
只引用可见回答、命令、日志、哈希或用户消息。
```

## 6. Release gate

```text
对 <repository-root> 做发布前只读审计：
- 主 XPR/top/part；
- RTL/XDC/XCI/权重输入哈希；
- ROM 与 COE/MEM 一致性；
- 仿真 PASS 标记；
- 综合/实现/timing/DRC/clock coverage；
- bit 是否来自当前主 run；
- skill、协作记录、正式报告和复现文档；
- 未执行项与已知告警。

输出 PASS/PARTIAL/BLOCKED 矩阵。没有证据的项不得写成 PASS；
发现源文件变化时优先停止使用旧 bit，并给出重建命令。
```

## Converting a reply into evidence

A model reply becomes evidence only after one of these is present:

- a reproducible command and captured output;
- a checked source reference with a stable relative path;
- a hash comparison;
- a test PASS marker and log hash;
- a rendered artifact or explicitly marked owner-supplied fact.

Keep the prompt, visible reply, correction and final verification log together in the collaboration record.
