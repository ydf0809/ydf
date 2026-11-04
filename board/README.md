# 硬件与上板复现

状态：本仓库提供硬件连接、烧录和板级验收入口，实际硬件版本、线序与供电按实物配置核对。

## 工程表达的硬件组成

| 部分 | 源码中的接口 |
| --- | --- |
| 双板 | XC7Z020CLG400-1，系统时钟约33.333MHz；板卡与外设版本按实物核对 |
| 上层 | OV5640、RGB LCD、LU-ASR02类UART语音输入、五路循迹、板间UART |
| 下层 | OV7670、RGB LCD、底盘I2C、机械臂UART、超声波与板间UART |

## 引脚与协议

[pinmap.csv](pinmap.csv)由当前有效XDC命令提取，不从可能过时的RTL注释抄写。重新导出：

~~~text
python board/export_pinmap.py
~~~

该导出器仅处理本工程使用的显式PACKAGE_PIN/IOSTANDARD写法，不解释任意Tcl表达式；实施后的工具引脚报告也保存在build/reports。实际接线应同时核对板卡原理图、逻辑电平、共地和外设供电。

板间设计采用115200、8N1 UART。上层TX接下层RX，下层TX接上层RX，使用各自XDC对应的引脚。语音模式命令在下层源码中映射为循迹、视觉跟随、防空相关控制、停止与机械臂动作；语音词条和模块参数按实物配置记录。

| 板间信号 | 上层引脚 | 下层引脚 |
| --- | --- | --- |
| 上层TX到下层RX | link_tx / Y17 | link_rx / D20 |
| 下层TX到上层RX | link_rx / V16 | link_tx / F20 |

这些引脚来自本仓库XDC；实物接线按板卡原理图、逻辑电平和上电检查逐项核对。

## 烧录顺序

1. 完成README中的依赖检查、仿真及构建。
2. 在build/reports各板manifest核对顶层、主XPR、bit路径和SHA-256。
3. 按硬件说明确认连接，并分别选择对应板卡器件。
4. Vivado Hardware Manager中向上层写入top.bit，向下层写入super_top.bit。两者不能互换。
5. 先核对复位、图像显示、停止与模式切换，再逐项观察链路、循迹、目标跟随和机械臂动作。
6. 按[实测记录](measurements.md)保存输入、预期结果、实际输出和证据。

上板验收以构建产物、引脚核对、烧录记录和板级测量共同构成完整证据。

也提供program.tcl作为可审核的批处理烧录入口，参数为upper或lower、精确hw_target名称及精确hw_device名称。脚本要求连接目标唯一且器件为xc7z020；执行前核对manifest与实物，不使用通配符随意选取板卡。

报告书中的实拍、识别结果、执行过程、实现摘要和ILA抓取已整理到 [证据索引](evidence/README.md)，图像哈希见 [evidence_index.json](evidence/report/evidence_index.json)。运行 `python board/evidence/verify_evidence.py` 可核对报告来源及全部证据文件的SHA-256。
