# 从零复现

本文给出竞赛指南 §3.3.5 所需的完整操作顺序。适用版本为 2026-11-04 最终工程快照，目标器件为 `xc7z020clg400-1`。上板输入、预期输出和原始证据按 [measurements.md](../board/measurements.md) 记录。

## 1. 环境

- Windows 10/11，Vivado 2026.1，Python 3.10 或更高版本。
- 训练验证依赖：PyTorch、NumPy、Pillow，版本记录于 [requirements.txt](../training/scnn/requirements.txt)。
- 将仓库放在路径含空格的目录也可运行；脚本按自身位置解析全部工程引用。
- 以下命令均在仓库根目录执行。`<vivado-bin>` 指 Vivado 安装目录下的 `bin`，例如 `D:\vivado2026.1\2026.1\Vivado\bin`，不要把该安装目录复制进仓库。

## 2. 静态检查

~~~powershell
python build/test_checkers.py
python build/verify_repository.py
~~~

预期结果：`report/checker_tests.json` 的 11 个正负用例通过；`report/repository_check.json` 显示两个主 XPR 的缺失、越界和未解析引用均为 0，文件命名、文档链接和明显凭据模式无错误。

若 `PROCESSOR_ARCHITECTURE` 为空，启动 Vivado 前只需在 PowerShell 设置：

~~~powershell
$env:PROCESSOR_ARCHITECTURE = 'AMD64'
~~~

## 3. 模型与部署数据

权重一致性已由当前快照核对，常规复现不必再次比较。需要检查训练软件与参数转换链时执行：

~~~powershell
python -m pip install -r training/scnn/requirements.txt
python training/scnn/verify.py
python training/scnn/train.py --smoke-test
python build/check_weights.py
~~~

预期结果：参考帧、黑帧 50 步整数对照通过；3416 参数转换往返通过；合成样本的梯度、更新和导出通过；5 个 ROM 语法与部署数值一致。合成训练用于验证从模型到部署产物的软件流程。

## 4. 仿真

~~~powershell
python sim/run.py --vivado-bin "<vivado-bin>" --board all
~~~

预期结果：上层 10/10、下层 13/13，共 23/23。每个测试必须同时满足工具退出码为 0、出现该测试的明确完成标记、无 `FAIL`/`FATAL`/`ERROR`。结果写入 [summary.json](../sim/results/summary.json)，测试依赖与异常日志保存在 [attempts](../sim/results/attempts/initial_snapshot_summary.json)。

单板调试可把 `--board all` 改为 `--board upper` 或 `--board lower`。

## 5. 主工程构建

~~~powershell
python build/run.py --vivado-bin "<vivado-bin>" --board all --jobs 4
python build/verify_release.py
~~~

预期结果：两套主 XPR 完成综合、实现、布线和 `write_bitstream`；WNS/WHS 非负；DRC error、组合环、`no_clock` 和未约束内部端点均为 0；发布 bit 与各自主 run 哈希一致。报告位于 [upper](../build/reports/upper/manifest.json) 和 [lower](../build/reports/lower/manifest.json)。

构建期间保持源文件不变。若修改任何 RTL、XDC、XCI、COE/MEM 或测试台，必须重跑仿真、主 XPR 构建、`verify_release.py` 和异路径复现。两板日志保留 `Common 17-354 Could not open 'C' for writing` 诊断；工具随后完成综合、实现和 bit 生成，全部门限通过，原始诊断可在 build/reports 中复核。

## 6. 异路径复现

先暂存本次全部改动，再让脚本从 Git 索引生成 ZIP，避免工作目录换行转换造成哈希差异：

~~~powershell
python build/verify_relocation.py --vivado-bin "<vivado-bin>" --jobs 4
~~~

该命令在临时目录下创建带空格的新路径，解压 Git 索引，执行仓库检查、23 项仿真、双板主 XPR 构建和证据时效检查。结果写入 [relocation.json](relocation.json)、[relocation_simulation.json](relocation_simulation.json) 和 [repository_check_relocation.json](repository_check_relocation.json)。脚本要求暂存区与工作树中的已跟踪文件一致；不要从工作目录直接手工压缩来替代此检查。

## 7. 上板

按 [board/README.md](../board/README.md) 核对实物、引脚、供电与 JTAG，随后分别烧录：

~~~powershell
vivado -mode batch -source board/program.tcl -tclargs upper <exact-hw-target> <exact-hw-device>
vivado -mode batch -source board/program.tcl -tclargs lower <exact-hw-target> <exact-hw-device>
~~~

上层使用 `top.bit`，下层使用 `super_top.bit`，两者不能互换。烧录后按板级测试表逐项确认相机、LCD、语音、UART、循迹、底盘、机械臂和目标识别，并保存原始证据。

## 8. 结果判定

提交前至少确认：

| 项目 | 通过条件 | 当前状态 |
| --- | --- | --- |
| 静态检查 | 检查器与仓库检查 PASS | PASS |
| 仿真 | 23/23 且日志未过期 | PASS |
| 主 XPR 构建 | 两板 bit、时序、DRC、来源哈希一致 | PASS，保留工具诊断 |
| 异路径复现 | 归档检查、仿真、构建、交付检查 PASS | PASS |
| 实板功能 | 按测试表记录输入、输出、次数和原始证据 | 测量入口见 board/measurements.md |

异常排查按编译、展开、仿真、综合、实现、写 bit 和烧录阶段分别记录，并与当前 PASS 日志建立可追溯对应关系。
