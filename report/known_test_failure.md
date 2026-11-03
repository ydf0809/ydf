# 历史失败与当前状态的区分

旧提交 745a0bd 的旧源快照曾出现 tb_arm_stop 上电回位测试失败。该结论只适用于旧提交，不作为 xiegithub 新源包的当前结论。

本次所有测试重新运行，tb_arm_stop 的实际结果见 [下层日志](../sim/results/lower_tb_arm_stop.txt) 和 [本次汇总](../sim/results/summary.json)。

本次首轮 3 个上层兼容测试因运行入口漏编 compat_support 而展开失败，首次结果与错误日志保存在 sim/results/attempts。修正依赖收集后重跑，生产 RTL 和测试断言保持源包原值。不删除真实失败，也不以历史失败覆盖新测试结果。
