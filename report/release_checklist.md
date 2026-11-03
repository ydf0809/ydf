# 本地工程预览检查

本次授权：指定源包更新、双板、训练工具、技能包、真实协作、验证与 GitHub 发布。原工程只读。

| 检查 | 结果入口 |
| --- | --- |
| 来源、映射与适配哈希 | source_manifest.json、source_integrity.json |
| 名称、依赖、链接、明显凭据模式 | repository_check.json |
| 判定器和 XPR 检查正负反例 | checker_tests.json |
| 作者正式报告与渲染检查 | design/design_report_v7.pdf、design/formal_report_source.json |
| SCNN 训练部署技能结构与可运行检查 | scnn-training-pipeline、skill_validation.json |
| 26 项和首次依赖失败 | sim/results/summary.json、attempts |
| 主 XPR、源未变、bit 对应 | build/reports 各板 manifest |
| 时序/DRC/环/时钟覆盖与工具诊断 | validation.md、rpt/console |
| 训练/数值/语法/部署 | training/scnn/verification、weight_alignment.json |
| 异路径真实仿真和构建 | relocation.json、relocation_simulation.json、repository_check_relocation.json |
| 当前证据时效性 | delivery_check.json |
| MIT/第三方与缺项 | LICENSE、third_party_notices.md、owner_inputs.md |

保留历史，普通本地提交与快进推送。软件检查不等于实板或完整参赛通过。
