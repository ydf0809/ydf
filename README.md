# 双板 FPGA 视觉识别与运动控制平台

**工程预览版 · 2026-11-03 · 已发布至 GitHub `main`。**

本仓库以所有者指定的 `xiegithub` 源包为依据，包含两套 Zynq-7000 PL 工程和配套 SCNN 模型、训练、参数转换及数值验证工程。上层包含 OV5640 采集、彩色 ROI、SCNN、目标搜索与锁定、LCD、语音和板间通信；下层包含 OV7670 图像处理、LCD、循迹、底盘与机械臂控制。上述为源码范围，板级功能仍需实测验收。

本仓库按 AMD 竞赛指南第 3.3.5 节组织交付。先阅读作者提供的 [正式设计报告 V7 PDF](report/design_report/design_report_v7.pdf)、[技术报告对照](report/design_report.md)、[功能实现详解](report/implementation_details.md)、[从零复现](report/reproduction.md)、[验证状态](report/validation.md)、[已知限制](report/limitations.md) 和 [待补材料](report/owner_inputs.md)。当前不报告真实数据集准确率，也不把仿真或 bit 生成等同于实板通过。

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

正式训练需要数据集及明确实验配置，见训练说明。合成样本测试只验证梯度、参数更新和导出，不评价识别效果。训练脚本不会自动覆盖硬件 ROM 或重建 bit。

## 目录与指南对应

| 目录 | 内容 | 指南条目 |
| --- | --- | --- |
| projects/ | 双板 XPR、RTL、约束、IP、原始测试台 | 3.3.5.1；替代推荐 src 布局 |
| training/scnn/ | 模型、训练/微调、COE/MEM/ROM 导出、参考输入 | 配套软件及权重来源 |
| sim/ | 仿真入口、真实日志与结果 | 功能验证证据 |
| build/ | 构建与检查脚本、资源/时序/DRC 报告 | 可复现构建 |
| board/ | 引脚、烧录入口、bit、实测记录入口 | 上板工程；实测尚缺 |
| data/ | 模型卡、测试输入及参考输出说明 | 参考数据 |
| skill/ | [SCNN 训练部署流水线、提示词工作流与三类踩坑清单](skill/README.md) | 3.3.5.2 |
| report/ | 设计报告、协作节选、纠错案例、验证及缺项 | 3.3.5.3—3.3.5.5 |

指南允许替代目录布局；文件名使用英文，`README.md`、`LICENSE` 沿用标准名称。源包中的中文导入目录仅在本副本映射为 `imported` 并同步 XPR；可选历史增量 DCP 不作为从零构建依赖。

## 协作与可复用经验

[协作报告](report/ai_collaboration.md) 区分原文节选、编辑分析和当前验证，附 [25 条真实可见消息及来源索引](report/collaboration/README.md)。技能按“现象—触发—定位—处理—验证—边界”整理，覆盖权重混用、实例参数覆盖、目标身份、CDC、I2C 原子性、时序覆盖及旧产物误用；新增 [SCNN 训练部署技能](skill/scnn-training-pipeline/SKILL.md) 和六类可复用提示词工作流；不编造多智能体过程或优化收益。

## 来源、许可与发布

沿用已有 [MIT](LICENSE) 及原署名，第三方声明见 [third_party_notices.md](third_party_notices.md)。[来源清单](report/source_manifest.json) 记录源包相对路径、原始 SHA-256、仓库路径和必要适配；生产 RTL、约束、IP 和权重按字节复制。

正式设计报告以 PDF 预览版纳入仓库，DOCX 源文件保持项目外只读；来源与哈希见 [报告溯源](report/design_report/formal_report_source.json)。原始 xiegithub 发布 bit 与仓库从主 XPR 重建的 bit 分别登记，不能互换哈希。发布状态见 [publish_status.md](report/publish_status.md)。
