# 双板 FPGA 视觉识别与运动控制平台

**工程预览版 / Engineering preview**

本仓库从所有者指定的两套主 Vivado 工程重新整理，面向2026年全国大学生嵌入式芯片与系统设计竞赛 AMD 自主选题赛道3.3.5的工程交付要求。此处采用功能描述作为临时标题，作品正式名称和参赛介绍待所有者补充。

上层工程包含 OV5640 图像采集、RGB 图像通路、SCNN 识别与目标锁定、LCD、语音指令和板间通信；下层工程包含 OV7670/LCD、模式控制、底盘、循迹及机械臂接口。这是源码所表达的设计范围，不代表所有功能已完成实板验收。

**请先阅读[验证状态](report/validation.md)和[已知限制](report/limitations.md)。本预览不宣称训练过程可复现、识别效果达标或已通过实板验收。**

本次回归为15/16通过，尚有机械臂上电回位预期不一致，详见[失败记录](report/known_test_failure.md)。两板主XPR均已重建生成bit，但仍有方法学关键告警；使用前应核对具体报告。

## 主工程

| 板级工程 | 入口 | 顶层 | 器件 |
| --- | --- | --- | --- |
| 上层 | [主XPR](projects/merged_cam_lcd_voice_scnn/vivado_prj/merged_cam_lcd_voice_scnn.xpr) | top | xc7z020clg400-1 |
| 下层 | [主XPR](projects/realfinal_min_102404/realfinal.xpr) | super_top | xc7z020clg400-1 |

一个系统由两块板组成，每块板各保留一个主工程，bit不能互换。工程源码、约束、IP配置和现有权重位于仓库内，机器上已安装的 Vivado 与 Python 属于运行环境。

## 从零复现

1. 完整克隆或下载本仓库。安装 AMD Vivado 2026.1 和 Python 3.10以上版本；Python脚本只用标准库。
2. 在仓库根目录运行依赖检查。
3. 按以下命令执行仿真和双板构建。将占位符替换为本机工具安装目录；也可设置 XILINX_VIVADO 后省略参数。
4. 核对日志、报告、manifest和bit哈希，再按[硬件运行说明](board/README.md)进行板级测试。

~~~text
python build/verify_repository.py
python sim/run.py --vivado-bin "<vivado_install>/bin"
python build/run.py --vivado-bin "<vivado_install>/bin"
~~~

两条运行命令默认处理两块板；可加 --board upper 或 --board lower。详见[构建说明](build/README.md)和[仿真说明](sim/README.md)。陌生环境复现范围和实测缺项见验证状态，不以已有bit代替重建验证。

## 目录与提交要求

| 目录 | 内容 | 对应指南 |
| --- | --- | --- |
| projects/ | 两套主XPR、RTL、约束、IP、权重和原始测试台 | 3.3.5.1 工程与源码；替代推荐src布局 |
| sim/ | 测试入口、实际日志与结果汇总 | 仿真或验证证据 |
| build/ | 构建、依赖校验脚本和综合/实现报告 | 可复现构建、资源与时序证据 |
| board/ | 引脚表、烧录步骤、主工程生成的bit和实测记录入口 | 上板工程与参考比对 |
| data/ | 权重、参考数据及来源说明 | 测试数据与参考输出说明 |
| skill/ | [可独立复用的技能包](skill/README.md) | 3.3.5.2 |
| report/ | [设计报告](report/design_report.md)、协作摘要、需求核对、验证与限制 | 3.3.5.3—3.3.5.5 |

指南目录布局为推荐项，本仓库保留两套Vivado工程的原有内部结构，并给出上述对应关系。文件名采用英文；README.md、LICENSE保留常见标准名称。工具生成的运行目录留在Vivado要求的位置，由构建重新生成，不纳入源码提交。

## 来源与许可

沿用仓库已有[MIT许可证](LICENSE)及原有署名。原工程内供应商声明予以保留，适用范围见[第三方与数据说明](third_party_notices.md)。源文件来源、导出路径及SHA-256见[输入清单](report/source_manifest.json)。生产RTL、测试台、约束、IP配置与权重在整理时按原始字节复制。XPR仅做交付路径和可选增量缓存配置调整。

本预览尚缺正式作品介绍、板级实测、优化对比及模型训练来源等材料，具体清单见[待补充材料](report/owner_inputs.md)。

整理日期：2026-11-02；仓库：ydf0809/ydf。
