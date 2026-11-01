# 构建与可复现性

## 环境

本次目标工具为 AMD Vivado 2026.1，器件为 xc7z020clg400-1。Python 3.10以上，所用脚本仅依赖标准库。Windows入口调用官方bat；环境变量 PROCESSOR_ARCHITECTURE 缺失时才设为 AMD64，不拼装DLL路径。

~~~text
python build/verify_repository.py
python build/run.py --vivado-bin "<vivado_install>/bin" --board all --jobs 4
~~~

--jobs 为每块板的作业数；all并行运行两个独立板级工程，资源不足时分别选择upper和lower。脚本从自身位置定位仓库，工具安装目录是运行环境，不是项目文件依赖。

## 输出

- reports/upper/ 和 reports/lower/：资源、时序、DRC、方法学、时钟交互、引脚报告及构建manifest。
- work/：完整本地构建日志，不提交。Vivado自身的runs/gen/cache仍在对应工程位置。
- ../board/bitstreams/：从本次主工程实现run复制的bit；manifest记录主run路径、文件大小、SHA-256及副本一致性。

脚本检查综合、实现、write_bitstream、已约束路径WNS/WHS、DRC Error及组合环相关告警，并检查构建前后输入哈希。满足条件只产生工程预览候选。未约束路径、CDC及其他方法学关键告警仍须解释，不能由正WNS推出完整时序签核或实板通过。

完整复制或克隆到新位置后重新执行上述命令，才验证该环境的实际可复现性。移除任一必需源码、约束或IP配置，应使依赖检查明确失败。
