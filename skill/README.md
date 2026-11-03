# 可复用工程技能包

本技能包以实际失败与观察形成的踩坑清单为主，辅以可执行校验。面向 Vivado RTL、定点网络部署及视觉/执行机构接口，不依赖本队题目名称，不冒称通用 PYNQ Skill。

| 技能 | 适用场景 | 用法 | 已验证效果与边界 |
| --- | --- | --- | --- |
| [定点模型与 FPGA 部署](weight_deployment/README.md) | COE/MEM/内嵌 ROM、多通道及定点运算 | 按清单核查；运行 build/check_weights.py | 当前 3416 参数及 5 ROM 一致；不证明数据集精度 |
| [视觉与控制接口](interface_checks/README.md) | 跟踪、模式、UART、CDC、停车 | 根据现象选择测试，运行 sim/run.py | 保存明确 PASS/FAIL；未测实际光照、电机和供电 |
| [工程复现与产物溯源](project_repro/README.md) | 迁移、旧 bit、时序覆盖、验证误判 | 运行 build/test_checkers.py、check_xpr.py 和 build/verify_relocation.py | 固定正负反例、Git 索引归档、真实仿真与双板重建 |

每项均说明触发条件、证据、排查步骤、处理、验证和失效条件。来源为 [协作节选](../report/collaboration/README.md)、[验证状态](../report/validation.md) 及相应日志。历史观察不替代当前验证。

## 陌生队伍的使用步骤

1. 按症状选清单，自行定义时钟、阈值、引脚、类别和预期；不要照搬本项目数值。
2. 固定最小输入，先复现，再定位实际被编译的实例、文件与失败阶段。
3. 只改相关层，保存首次失败、修正后日志、输入哈希与未验证事项。
4. 超出清单边界时补充验证，不能用本工程 PASS 代替新项目验收。
