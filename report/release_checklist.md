# 工程预览发布检查

本次授权：单仓库双主工程、独立开源副本、沿用原MIT与署名、先公开工程预览。原工作工程与旧审核目录均不作为修改目标。

| 检查 | 结果入口 |
| --- | --- |
| 两套主工程来源、输入哈希与生产源码不改写 | source_manifest.json |
| 命名、项目依赖、文档链接、明显凭据模式 | repository_check.json |
| 仿真16项，失败不隐藏 | sim/results/summary.json，known_test_failure.md |
| 主XPR真实构建、输入不变、bit副本哈希一致 | build/reports各板manifest |
| 时序、DRC、组合环与关键方法学告警 | validation.md及原始rpt |
| 压缩迁移后依赖及实际构建 | relocation.json |
| MIT保留、工具与供应商声明、模型来源缺项 | 根LICENSE、third_party_notices.md、data/model_card.md |
| 实板、优化基线、训练与正式作品材料尚缺 | limitations.md、owner_inputs.md |

GitHub发布保留远端已有历史，使用普通提交和推送，不强推。当前发布为工程预览，不以文件齐全或bit生成代替完整参赛验收。
