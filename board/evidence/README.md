# 板级证据索引

本目录保存最终报告书中与板级结果、系统组成和实现质量直接相关的原始图像证据。图像从 `report/design_report/design_report_final.docx` 的嵌入对象原样提取，未重新编码。

## 报告图像

`report/` 包含系统实物、机械与电路、Vivado实现结果、SCNN识别框、目标锁定过程、语音模块、循迹转弯、机械臂动作、防空云台跟踪和ILA抓取。逐项文件说明、来源图号、字节数与SHA-256见 [report/evidence_index.json](report/evidence_index.json)。

识别与锁定结果：

| 场景 | 证据 |
| --- | --- |
| 低空非目标显示红框 | [fig3-7-nontarget-red.jpeg](report/fig3-7-nontarget-red.jpeg) |
| 无人机目标显示绿框 | [fig3-8-drone-green.jpeg](report/fig3-8-drone-green.jpeg) |
| 初始未锁、锁定与脱锁过程 | [fig3-9-initial.jpeg](report/fig3-9-initial.jpeg)、[fig3-9-unlocked.jpeg](report/fig3-9-unlocked.jpeg) |
| 防空云台跟踪 | [fig3-13-defense-tracking.jpeg](report/fig3-13-defense-tracking.jpeg) |
| ROI窗口与识别写信号ILA抓取 | [fig3-14-ila-roi.png](report/fig3-14-ila-roi.png) |

系统与执行结果：

| 场景 | 证据 |
| --- | --- |
| 双板与整机实物 | [fig3-1-platform-overall.jpeg](report/fig3-1-platform-overall.jpeg)、[fig3-1-system-boards.jpeg](report/fig3-1-system-boards.jpeg) |
| 机械结构与麦克纳姆底盘 | [fig3-2-mechanical.jpeg](report/fig3-2-mechanical.jpeg)、[fig3-3-chassis.png](report/fig3-3-chassis.png) |
| 电路实现与整机连接 | [fig3-4-circuit.jpeg](report/fig3-4-circuit.jpeg)、[fig3-4-hardware-platform.jpeg](report/fig3-4-hardware-platform.jpeg) |
| 循迹直角转弯 | [fig3-11-corner-turn.jpeg](report/fig3-11-corner-turn.jpeg) |
| 机械臂装卸动作序列 | [fig3-12-arm-1.jpeg](report/fig3-12-arm-1.jpeg)、[fig3-12-arm-2.jpeg](report/fig3-12-arm-2.jpeg)、[fig3-12-arm-3.jpeg](report/fig3-12-arm-3.jpeg)、[fig3-12-arm-4.jpeg](report/fig3-12-arm-4.jpeg) |

实现结果：

| 场景 | 证据 |
| --- | --- |
| 上层Vivado实现摘要 | [fig3-5-upper-build.png](report/fig3-5-upper-build.png) |
| 下层Vivado实现摘要 | [fig3-6-lower-build.png](report/fig3-6-lower-build.png) |

## 核对方式

1. 运行 `python board/evidence/verify_evidence.py`，核对最终报告DOCX来源、文件数量和SHA-256。
2. 以 [evidence_index.json](report/evidence_index.json) 核对每个文件的来源图号、报告页码和观察结果。
3. 将结果与 [measurements.md](../measurements.md) 中的参考行为逐项对照。
4. 新采集的原始日志、视频或波形继续放入本目录，并在索引和测量表中登记。
