# AMD 指南 §3.3.5 对照

依据用户提供的 AMD 指南 §3.3.5（源 PDF 24—25 页，印刷页 21—22）。这里是摘要和交付映射，不把示例当作本作品事实；布局可替代，英文命名仍遵守。

| 要求 | 材料 | 交付证据 |
| --- | --- | --- |
| 3.3.5.1 完整工程/源码 | projects、training/scnn | 直接取指定源包 |
| 仿真/验证 | sim/results、训练 verification | 23 项回归、定点数值与部署检查 |
| 资源/时序/关键指标 | build/reports、resources.csv | 资源、时序、DRC 与工具诊断 |
| 上板工程/运行/实测对照 | board | bit、引脚、烧录入口与测量模板 |
| 可复现构建 | build、relocation.json | 主 XPR 与异路径复现 |
| 3.3.5.2 技能 | skill 训练部署流水线、提示词工作流、三类踩坑及检查器 | 来源/用法/效果/失效条件；非 PYNQ |
| 3.3.5.3 原理/框图/划分/接口 | design_report/design_report_v7.pdf、design_report.md、implementation_details.md | 作者正式报告 PDF 已纳入；技术对照与实现附录用于对齐当前仓库证据 |
| 优化前后对比 | 设计报告第 4 节 | 设计选择、资源与实现结果 |
| 协作/纠错/工作流 | collaboration、ai_collaboration.md | 25 条真实可见消息与来源索引 |
| 从零复现 | reproduction.md、README、build/sim/board | 环境、命令、预期结果与异常处理 |
| 3.3.5.4 结构/命名 | README、repository_check | projects/training 替代布局 |

3.3.5.5 权重：创新应用 30、性能资源优化 20、正确性完整性 20、协作技能 15、文档复现 15；评分按官方规则核定。
