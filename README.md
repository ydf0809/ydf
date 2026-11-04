# 基于FPGA的多模态低空空前预警战备车

## ——双板协同的SCNN脉冲神经网络视觉识别与语音交互感知移动作业平台

**工程发布版 · 2026-11-04 · 已发布至 GitHub `main`。**

> 2026-11-04：双板工程已按最终 `xiegithub` 目录同步，源码、约束、XPR、bit 和验证记录均已更新；作者最终报告书已完成防御性写作修订，并以 DOCX 与导出 PDF 两种格式纳入仓库。

本仓库以所有者指定的 `xiegithub` 源包为依据，包含两套 Zynq-7000 PL 工程和配套 SCNN 模型、训练、参数转换及数值验证工程。上层包含 OV5640 采集、彩色 ROI、SCNN、目标搜索与锁定、LCD、语音和板间通信；下层包含 OV7670 图像处理、LCD、循迹、底盘与机械臂控制。工程同时提供引脚、烧录入口、板级证据索引和实测记录模板。

本仓库按 AMD 竞赛指南第 3.3.5 节组织交付。先阅读 [最终设计报告 PDF](report/design_report/design_report_final.pdf)、[可编辑报告书 DOCX](report/design_report/design_report_final.docx)、[技术报告对照](report/design_report.md)、[功能实现详解](report/implementation_details.md)、[从零复现](report/reproduction.md) 和 [验证结果](report/validation.md)。

## 主工程与权重

| 工程 | 主 XPR | 顶层 | 器件 |
| --- | --- | --- | --- |
| 上层 | [merged_cam_lcd_voice_scnn.xpr](projects/merged_cam_lcd_voice_scnn/merged_cam_lcd_voice_scnn.xpr) | top | xc7z020clg400-1 |
| 下层 | [realfinal.xpr](projects/realfinal_min_102404/realfinal.xpr) | super_top | xc7z020clg400-1 |

每板各保留一个主 XPR，bit 不能互换。上层实际编译的 SCNN 权重位于 `rtl/drone_data_roms.v`；单独复制 COE/MEM 不会更新它。[训练工程](training/scnn/README.md) 的当前四组 COE/MEM、默认参数和上层 ROM 通过 [部署一致性检查](report/weight_alignment.json)。历史 COE 单独保留作来源比较，不作为默认部署参数。

## 从零复现

安装 Vivado 2026.1、Python 3.10 以上版本；训练验证另需安装配套依赖。以下命令在仓库根目录运行，`<vivado_install>` 替换为本机工具目录，也可设置 `XILINX_VIVADO`。

~~~text
python build/verify_repository.py
python build/test_checkers.py
python build/check_weights.py
python -m pip install -r training/scnn/requirements.txt
python training/scnn/verify.py
python training/scnn/train.py --smoke-test
python sim/run.py --vivado-bin "<vivado_install>/bin"
python build/run.py --vivado-bin "<vivado_install>/bin"
python build/verify_release.py
python build/verify_relocation.py --vivado-bin "<vivado_install>/bin"
~~~

仿真、构建可加 `--board upper` 或 `--board lower`。完整步骤、预期结果和异路径归档检查见 [从零复现](report/reproduction.md)，分项说明见 [构建说明](build/README.md)、[仿真说明](sim/README.md)、[上板说明](board/README.md)。主 XPR 的原生 `.runs/`、`.gen/` 等目录由 Vivado 生成；通过检查的 bit 复制至 `board/bitstreams/`。运行缓存不纳入 Git。

正式训练需要数据集及明确实验配置，见训练说明。合成样本测试用于验证梯度、参数更新和导出流程，训练脚本提供从训练结果到硬件 ROM 的独立导出路径。

## 目录与指南对应

| 目录 | 内容 | 指南条目 |
| --- | --- | --- |
| projects/ | 双板 XPR、RTL、约束、IP、原始测试台 | 3.3.5.1；替代推荐 src 布局 |
| training/scnn/ | 模型、训练/微调、COE/MEM/ROM 导出、参考输入 | 配套软件及权重来源 |
| sim/ | 仿真入口、真实日志与结果 | 功能验证证据 |
| build/ | 构建与检查脚本、资源/时序/DRC 报告 | 可复现构建 |
| board/ | 引脚、烧录入口、bit、报告图像证据与实测记录 | 上板工程与实测记录 |
| data/ | 模型卡、测试输入及参考输出说明 | 参考数据 |
| skill/ | [SCNN 训练部署流水线、提示词工作流与三类踩坑清单](skill/README.md) | 3.3.5.2 |
| report/ | 设计报告、协作节选、纠错案例、验证及扩展材料 | 3.3.5.3—3.3.5.5 |

指南允许替代目录布局；文件名使用英文，`README.md`、`LICENSE` 沿用标准名称。源包中的中文导入目录仅在本副本映射为 `imported` 并同步 XPR；可选历史增量 DCP 不作为从零构建依赖。

## 协作与可复用经验

[协作报告](report/ai_collaboration.md) 区分原文节选、编辑分析和当前验证，附 [25 条真实可见消息及来源索引](report/collaboration/README.md)。技能按“现象—触发—定位—处理—验证—边界”整理，覆盖权重一致性、实例参数覆盖、目标身份、CDC、I2C 原子性、时序覆盖及产物追溯；新增 [SCNN 训练部署技能](skill/scnn-training-pipeline/SKILL.md) 和六类可复用提示词工作流。

## 来源、许可与发布

沿用已有 [MIT](LICENSE) 及原署名，第三方声明见 [third_party_notices.md](third_party_notices.md)。[来源清单](report/source_manifest.json) 记录源包相对路径、原始 SHA-256、仓库路径和必要适配；生产 RTL、约束、IP 和权重按字节复制。

作者最终报告书以 DOCX 和导出 PDF 纳入仓库；DOCX 在保留原始版式、图表和实验数据的前提下完成防御性写作修订。来源、原始文件、修改稿及导出 PDF 的哈希见 [报告溯源](report/design_report/formal_report_source.json)。作者报告中的阶段测试、时序和原始发布 bit 快照，与仓库从最终主 XPR 重建的测试、时序和 bit 分别登记，并保持独立溯源。发布状态见 [publish_status.md](report/publish_status.md)。
