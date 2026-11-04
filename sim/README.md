# 原始测试台回归

最终工程基线来自指定 xiegithub 源包：上层 10 项、下层 12 项。仓库为下层 RGB→HSV 时序修复补回并通过了 `tb_rgb2hsv_pipeline`，当前为上层 10 项、下层 13 项，共 23 项。

~~~text
python sim/run.py --vivado-bin "<vivado_install>/bin" --board all
~~~

每测试独立目录，收集 RTL 与 compat_support 实例依赖，用 SystemVerilog 编译、默认 timescale，下层加入工具运行时 glbl。零测试不能通过。通过需退出码 0、明确完成标记、无 FAIL/FATAL/ERROR；编译、展开、运行、超时分别记录。

公开日志与 [summary.json](results/summary.json) 有输入/日志哈希；work 不提交。当前最终结果为 23/23，依赖与异常记录保存在 [attempts](results/attempts/initial_snapshot_summary.json)。

上层覆盖 SCCB 分频、框配色、模式/重新进入、候选/运动/ROI、周期复检、CDC、舵机和显示/串行兼容。下层覆盖全部 65536 个 RGB565 的 HSV 对照、相机采样、框 CDC、机械臂、语音/模式、链路、底盘、转弯、旋转、I2C 停止及循迹。

兼容辅助模块复现数字协议与跨板数据通路；物理双板连接、图像集评测、执行机构负载和真实时延由板级测试记录承接。
