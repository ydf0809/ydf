# 工程发布检查

本次授权：指定源包更新、双板、训练工具、技能包、真实协作、验证与 GitHub 发布。原工程只读。

| 检查 | 结果入口 |
| --- | --- |
| 来源、映射与适配哈希 | source_manifest.json、source_integrity.json |
| 名称、依赖、链接、明显凭据模式 | repository_check.json |
| 判定器和 XPR 检查正负反例 | checker_tests.json |
| 作者最终报告书与渲染检查 | design_report/design_report_final.pdf、design_report/design_report_final.docx、design_report/formal_report_source.json |
| SCNN 训练部署技能结构与可运行检查 | scnn-training-pipeline、skill_validation.json |
| 23 项回归与依赖检查日志 | sim/results/summary.json、attempts |
| 主 XPR、源未变、bit 对应 | build/reports 各板 manifest |
| 时序/DRC/环/时钟覆盖与工具诊断 | validation.md、rpt/console |
| 板级实拍、识别结果、执行过程与 ILA | board/evidence/README.md、board/measurements.md |
| 训练/数值/语法/部署 | training/scnn/verification、weight_alignment.json |
| 异路径真实仿真和构建 | relocation.json、relocation_simulation.json、repository_check_relocation.json |
| 当前证据时效性 | delivery_check.json |
| MIT、第三方与扩展输入 | LICENSE、third_party_notices.md、owner_inputs.md |

保留历史，普通本地提交与快进推送。检查结果覆盖源代码、仿真、构建、报告和发布证据。
