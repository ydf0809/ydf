# 模型参数与参考输入

现用规范权重、JSON 参数、参考帧位于 [training/scnn](../training/scnn/README.md)。上层实际编译的权重在 [drone_data_roms.v](../projects/merged_cam_lcd_voice_scnn/rtl/drone_data_roms.v)。

当前四组 COE/MEM 与部署 ROM 数值一致，见 [一致性报告](../report/weight_alignment.json)。训练工程 references/new_weight_coe 是独立历史参考，不作为默认部署源。不能因同名而互换。

参考输入是 64×64、24 位 RRGGBB 文件，不是数据集。固定点软件从全局复位起处理 50 步，现用参数参考输出 [0,50]、黑帧 [0,0]；平票取类别 0。上述是功能基准，不是准确率。训练数据目录当前只含说明。
