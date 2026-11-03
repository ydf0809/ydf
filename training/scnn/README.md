# 无人机目标识别脉冲卷积神经网络（SCNN）

文档日期：2026 年 11 月 3 日。本目录以指定源包 jiaoben 为输入，运行与交付均在仓库副本进行。

## 1. 项目概述

本项目面向 FPGA 平台的无人机目标识别任务，提供脉冲卷积神经网络模型、训练与微调程序、定点参数转换工具及数值一致性验证程序。模型以 64×64 三通道彩色感兴趣区域（ROI）为输入，采用概率脉冲编码、卷积特征提取、泄漏积分发放（LIF）神经元及脉冲计数判决，实现无人机与非无人机二分类。

网络包含两层卷积、三次池化及一层全连接分类器，共 3416 个可训练参数。软件模型的网络结构、张量排列和定点运算规则与 FPGA 推理接口保持一致。目标位置及 ROI 由上层图像处理模块提供，本模型负责区域内容分类。

训练程序支持随机初始化训练和基于预置模型参数的微调，部署工具支持生成 COE、MEM 及内嵌权重的 Verilog ROM。数据集评测结果与软件功能验证结果分别记录，正式训练状态见本文第 6 节。

## 2. 项目文件

| 文件 | 用途 |
|---|---|
| [convert_weights.py](convert_weights.py) | COE/MEM 解包、双格式一致性检查、JSON/训练检查点导出权重及 Verilog ROM |
| [model.py](model.py) | 无人机识别 SCNN，包含定点前向与替代梯度反向传播 |
| [train.py](train.py) | 模型训练、预置参数微调、检查点与训练记录保存 |
| [verify.py](verify.py) | 源文件哈希、往返转换、独立整数模型、异常输入、移动目录验证 |
| [model_spec.json](model_spec.json) | 网络结构、通道定义、数据位宽及 LIF 运算配置 |
| [recovered_weights.json](recovered_weights.json) | 量化模型参数及对应张量形状 |
| [source_manifest.json](source_manifest.json) | 配套源权重与参考帧 SHA-256 |
| `weights/0..7/` | 配套 COE/MEM 模型参数文件，作为只读校验输入 |
| `assets/reference_frame.mem` | 功能验证参考输入，不计入训练或验证数据集 |
| `generated/` | 转换输出、检查结果和测试产物 |

程序运行和功能验证所需的模型参数及参考输入均位于本目录内。路径参数相对于脚本目录解释，整体移动项目后可继续执行。Python 解释器及第三方软件包属于运行环境，依赖版本记录于 [requirements.txt](requirements.txt)。正式训练数据应按第 5 节要求配置。

## 3. 网络结构与运算规则

```text
64×64×3 彩色输入
  → 概率脉冲编码
  → Conv 3→8，3×3，padding=1，无 bias → LIF
  → 2×2 OR 池化
  → Conv 8→16，3×3，padding=1，无 bias → LIF
  → 2×2 OR 池化 → 2×2 OR 池化
  → 按 channel、row、column 展平为 1024
  → FC 1024→2，无 bias → LIF → 50 步脉冲计数
```

- 彩色像素在帧文件中是 `RRGGBB`；RTL 的通道 0/1/2 读取低字节到高字节，因此模型张量按 B/G/R 排列。
- 类别 0 = `not_drone`，类别 1 = `drone`，计数相同时判类别 0。
- 权重为有符号 16 位、12 个小数位，真实数值 = 存储整数 / 4096。
- 膜电位和电流为有符号 26 位。更新为 `candidate = v + ((I - v) >>> 1)`，遵循 26 位回绕、算术右移；阈值为 4096，发放后归零。
- 卷积宽字最低的 16 位对应 `ci=0, co=0`；全连接每个 64 位字最高的 16 位对应该组第一个特征。转换脚本分别处理两种排列。
- 概率脉冲编码采用与 `prng_lfsr` 一致的种子和反馈抽头；按照 `input_frontend` 的寄存器时序，复位后首个采样随机字节为 0，其后为种子的高字节。
- Python 的一次模型调用表示**从全局复位状态开始处理一帧**；随机序列在该帧的 50 个时间步之间连续。实际硬件连续多帧的 PRNG 状态不在本次等价验证范围内。

## 4. 参数转换与功能验证

在项目目录打开 PowerShell。运行环境尚未安装依赖时，执行：

```powershell
python -m pip install -r requirements.txt
```

1. 导入配套 COE/MEM 参数，生成包含张量形状的定点参数文件。`both` 模式执行双格式一致性检查；内容不一致时终止转换并报告错误。

```powershell
python convert_weights.py decode --source weights --format both --output recovered_weights.json
```

2. 将模型参数导出为四对 COE/MEM，以及包含四个权重 ROM 和一个参考输入 ROM 的 Verilog 文件。

```powershell
python convert_weights.py encode --input recovered_weights.json --output generated/weights --rom generated/drone_data_roms.v
```

3. 执行数值一致性与最小训练流程验证。

```powershell
python verify.py
python train.py --smoke-test
```

`verify.py` 分别使用参考输入和全黑输入，与独立 NumPy 整数实现比较完整 50 个时间步的输出脉冲序列，同时检查参数文件哈希、3416 个参数的转换往返一致性、存储字通道排列、异常输入拒绝及项目移动后的运行结果。

`--smoke-test` 使用两张合成输入和 3 个时间步，验证各参数张量的梯度、Adam 参数更新及检查点导出。该测试属于软件功能验证，不用于评价模型识别性能；`generated/smoke_checkpoint.pt` 及 `generated/smoke_weights/` 为测试产物。

## 5. 数据集训练与模型导出

训练与验证数据应按 [数据集规范](data/README.md) 配置。每张图像须完成 ROI 预处理，尺寸为 64×64，保留彩色信息。程序直接以 8 位通道强度进行概率脉冲编码，不执行自动缩放、灰度化或额外的标准化。

随机初始化训练命令示例如下。轮数、批量大小和学习率为操作示例，应依据实际数据集和实验配置确定，不作为已验证的训练结论。

```powershell
python train.py --data data --from-scratch --epochs 20 --batch-size 4 --lr 0.0001
```

`--from-scratch` 指定随机初始化训练；不指定该选项时，程序加载 `--weights` 指定的预置参数进行微调。轮数、批量大小和学习率须显式提供，随机种子通过 `--seed` 设置并记录。

训练采用 Adam 优化器、输出脉冲计数交叉熵损失、斜率为 5 的 fast-sigmoid 替代梯度，以及复位路径梯度分离的硬复位机制。前向执行 Q12 权重量化，并以 float64 表示整数派生运算；默认运行设备为 CPU。

训练输出包括 `generated/training/best.pt`、`latest.pt`、`history.json` 和数据文件哈希清单。`best.pt` 按验证集准确率保存，`latest.pt` 保存最近一轮参数。训练完成后执行模型参数导出：

```powershell
python convert_weights.py encode --input generated/training/best.pt --output generated/trained_weights --rom generated/trained_drone_data_roms.v
```

浮点模型参数导出时采用 `round(weight × 4096)` 量化规则。非有限值及超出有符号 16 位表示范围的参数将被拒绝。检查点导入需符合本项目定义的参数名称、张量形状、类别顺序和网络配置。

## 6. 验证记录与适用范围

| 验证项目 | 已记录结果 | 记录文件 |
|---|---|---|
| 3416 个参数的转换往返 | 通过，3416 参数一致；4 个 MEM 逐字节一致 | [数值验证记录](verification/verification.json) |
| 参考输入与全黑输入的 50 步输出 | 与独立整数实现一致 | [数值验证记录](verification/verification.json) |
| 梯度、参数更新及检查点导出 | 最小训练流程通过 | [训练功能验证记录](verification/smoke_test.json) |
| 项目整体移动后的运行 | 通过 | [数值验证记录](verification/verification.json) |
| 导出的 5 个 Verilog ROM 模块 | Vivado 2026.1 `xvlog` 语法编译通过 | [ROM 编译记录](verification/rom_compile.json) |

上述结果用于说明软件功能、定点数值规则和参数转换链的一致性，不作为无人机识别准确率、召回率或复杂场景泛化能力的评测结果。当前尚未完成正式数据集训练及独立测试集评测，因此未报告相关性能指标。

本目录程序不自动修改 Vivado 主工程或比特流。更新部署模型后，应依次完成主工程接入、相关 RTL 仿真、综合与实现、比特流生成以及硬件验证。ROM 语法编译结果不替代上述验证过程。

## 7. 当前部署参数与历史参考

当前规范 weights/ 的四组 COE/MEM 数值一致，默认初始化使用 parameters/final_engine_weights.json；recovered_weights.json 是同一现用参数的另一份已核对表示。生成器的默认导出同样使用现用参数。

references/new_weight_coe/ 与 parameters/new_weight_coe_weights.json 为独立历史参考，与当前部署参数不同，保留用于来源比较，不自动部署。references/final_engine/drone_data_roms.v 保留源包参考快照，其源文件排版哈希可与当前生产 ROM 不同，数据需按数值比较。

本次修正 verify.py 中历史替代 JSON 的比较对象及缺失审计字段；模型计算、训练算法和现用参数不改。运行 convert_weights.py audit 默认核对规范 COE/MEM；显式使用 --coe-source references/new_weight_coe 才比较历史参考。

完整软件验证输出到 generated/；仓库内 verification/ 保存本次实际执行的记录。任何重新运行或修改脚本后，都应核对记录的输入哈希，避免用旧报告作为新结果。真实数据集和原始训练过程尚缺，不将现存参数的部署兼容性写成完整历史训练可复现。
