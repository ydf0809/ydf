# 权重、测试输入与参考输出

现有SCNN权重保存在上层工程的weights/，参考帧保存在该工程根目录的reference_frame.mem；ROM实现也在RTL中。位置与文件哈希列于report/source_manifest.json。

原始测试台的激励与预期检查逻辑随源码提交，实际仿真输出位于sim/results。板级样本、黄金参考和测量数据尚未交付，不能用合成测试台的通过率替代真实识别效果。

详见[模型说明](model_card.md)。新增数据和图片使用英文文件名，并记录来源、用途、参考标签及适用许可。
