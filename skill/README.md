# 可复用技能包

本目录按指南3.3.5.2提炼可供其他题目使用的技能，不要求采用本项目SCNN、板卡或双板架构。

| 技能 | 用法 | 验证与边界 |
| --- | --- | --- |
| [XPR工程依赖检查](project_repro/README.md) | 独立Python脚本；指定项目根与XPR | 已用于本仓库；不替代综合、时序或硬件验证 |
| [接口边界验证工作流](interface_checks/README.md) | 契约、坏输入、忙状态、停止和退出测试模板 | 依据原始接口测试与本次回归；具体协议需重新定义 |

技能提炼过程见report/ai_collaboration.md，执行证据见report/validation.md。当前工程没有迁移为PYNQ，这些通用检查方法不申报为PYNQ专用加分技能。
