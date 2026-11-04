# 模型说明与部署口径

- 任务：64×64 彩色 ROI 二分类，0=not_drone、1=drone，平票取 0。
- 结构：Conv 3→8，OR pool，Conv 8→16，两次 OR pool，FC 1024→2；无 bias，共 3416 参数，50 时间步。
- 通道与算术：B/G/R 张量、signed16 Q12 权重、26 位膜电位，详见 training/scnn/model_spec.json。
- 当前参数：training/scnn/parameters/final_engine_weights.json，与规范 COE/MEM 和上层 ROM 一致。
- 历史参考：new_weight_coe_weights.json 只作对照，不能默认为当前模型；两套参数的参考帧输出不同。
- 验证：参数转换、独立整数对照、异常输入、合成训练、ROM 语法与部署数据对照。见训练工程 verification 记录。
- 评测维度：数据集准确率、召回率与场景泛化由独立测试集评测；连续帧和板级行为由 RTL 与板级测试承接。
- 来源记录：现存量化参数、RTL 和部署产物可逐字节核对，训练与数据依据按后续实验记录补充。
