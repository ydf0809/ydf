# 构建与可复现性

Vivado 2026.1、xc7z020clg400-1、Python≥3.10。构建与仓库检查只用标准库；训练验证另需 training/scnn/requirements.txt。Windows 使用官方 bat；PROCESSOR_ARCHITECTURE 缺失时才设 AMD64。

~~~text
python build/verify_repository.py
python build/test_checkers.py
python build/check_weights.py
python build/run.py --vivado-bin "<vivado_install>/bin" --board all --jobs 4
python build/verify_release.py
python build/verify_relocation.py --vivado-bin "<vivado_install>/bin" --jobs 4
~~~

每板 --jobs=4，all 并行构建两个独立工程；资源不足时分别选择 upper/lower。路径由脚本定位，工具安装属于机器运行环境。

reports/upper、reports/lower 包含时序、资源、DRC、方法学、CDC、时钟交互、引脚、console 与 manifest。work 是本地缓存；Vivado runs/gen/cache 保留在主工程原生位置。board/bitstreams 从当前主 run 复制 bit，manifest 记录输入哈希、top/part、路径、时间、大小及 SHA-256。

通过条件：综合、实现、write_bitstream 完成，WNS/WHS≥0，DRC error=0，组合环/no_clock/未约束内部端点=0，输入未变，发布 bit 匹配主 run。通过后形成可发布构建候选，外部 I/O 与硬件行为由板级记录承接。

本次两板日志记录 Common 17-354 “Could not open 'C' for writing”，工具继续完成综合、实现和 bit 生成，全部构建门限通过。原始诊断保存在 tool_diagnostics.txt 与 console.txt。

verify_release.py 校验源、测试和 bit 的对应关系；更改源后重新验证。完整移动后的工程通过真实构建确认。

test_checkers.py 用成功、失败、FATAL、ERROR、非零退出码、缺少完成标记、缺失 XPR 文件和越界引用等正负用例检查判定器。verify_relocation.py 要求已跟踪文件先暂存，从 Git 索引导出 ZIP，再到带空格的其他路径复跑仓库检查、仿真、双板构建和交付检查；结果写入 report/relocation.json。完整从零流程见 [report/reproduction.md](../report/reproduction.md)。
