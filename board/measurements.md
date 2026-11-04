# 板级验收与参考比对

本表汇总最终报告书中的板级结果，并把参考行为、实际观察和仓库内证据对应起来。报告书记录的 bit SHA-256 为上层 `a6a27076f61adc6b35ca027db51f8ce2cb926f04a4d549dd3e7601ddeba5710d`、下层 `aebd4004da50f6ee2cb19d249d9c5ac25a5d636019f8b3c76bf22c8aedaec233`；最终主 XPR 重建 bit 为上层 `fa947a84887b1c5122325621bc08ea997ad6d7d87d38158eff5c40ea39677918`、下层 `888f1b1bde28812eac15d66b3261173b01b25e737db220c3aca8278693f5977f`，两组版本分别由 [报告溯源](../report/design_report/formal_report_source.json) 和 [构建报告](../build/reports/upper/manifest.json) 记录。

| 项目 | 参考行为 | 实测或观察结果 | 仓库证据 |
| --- | --- | --- | --- |
| 双板UART与目标框 | 模式命令、目标框和循迹状态到达接收端；目标框驱动云台与底盘协同 | 报告记录两板联调完成目标框下发，云台按目标框跟踪，偏航到限位后由底盘辅助转向 | `tb_board_link`、`tb_bbox_unpack`、`tb_upper_lower_serial_compat` 日志；[fig3-13-defense-tracking.jpeg](evidence/report/fig3-13-defense-tracking.jpeg) |
| 语音与停止 | 五条词条切换循迹、跟随、防空、停止和装卸货模式；停止时关闭使能并广播舵机停止包 | 报告记录五条词条的模式映射、语音链路和停止保护；语音模块、动作时序和停止包均有实现与验证记录 | [fig3-10-voice-module.jpeg](evidence/report/fig3-10-voice-module.jpeg)；`tb_voice_mode`、`tb_voice_arm`、`tb_arm_stop` |
| 图像与SCNN | 非无人机显示红框；无人机显示绿框并按多次确认锁定 | 报告实拍显示非目标红框、目标绿框、初始未锁、锁定与脱锁过程，形成红框搜索到绿框锁定的完整状态链 | [fig3-7-nontarget-red.jpeg](evidence/report/fig3-7-nontarget-red.jpeg)、[fig3-8-drone-green.jpeg](evidence/report/fig3-8-drone-green.jpeg)、[fig3-9-initial.jpeg](evidence/report/fig3-9-initial.jpeg)、[fig3-9-unlocked.jpeg](evidence/report/fig3-9-unlocked.jpeg) |
| ROI与识别时序 | ROI应位于 `[0,472]×[0,272]` 有效范围内，状态与识别写信号同步变化 | ILA实测 `roi_x0=0x110`、`roi_y0=0x054`，即 `(272,84)`；窗口覆盖 `272~399`、`84~211`，参考范围检查通过 | [fig3-14-ila-roi.png](evidence/report/fig3-14-ila-roi.png)；报告3.4节 |
| 循迹与底盘 | 识别直行、压线和丢线状态；直角路口完成确认后转向并恢复PID | 报告实拍记录直角转弯过程，底盘控制与五路循迹整链路仿真通过 | [fig3-11-corner-turn.jpeg](evidence/report/fig3-11-corner-turn.jpeg)；`tb_corner_turn`、`tb_line_pid`、`tb_xunbi_tracking` |
| 机械臂 | 按12步动作完成抓取、搬运、放置与复位；停止指令可立即中止 | 报告实拍记录完整装卸过程，六个舵机按总线寻址执行；停止包与复位时序仿真通过 | [fig3-12-arm-1.jpeg](evidence/report/fig3-12-arm-1.jpeg)、[fig3-12-arm-2.jpeg](evidence/report/fig3-12-arm-2.jpeg)、[fig3-12-arm-3.jpeg](evidence/report/fig3-12-arm-3.jpeg)、[fig3-12-arm-4.jpeg](evidence/report/fig3-12-arm-4.jpeg)；`tb_arm_stop` |

全部图像的文件名、来源图号、字节数和 SHA-256 见 [evidence_index.json](evidence/report/evidence_index.json)。新增实板测试时，继续按本表结构登记输入、输出、次数和原始证据。
