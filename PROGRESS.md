TASK: 移除助手采样功能（temperature / topP）
STEP: 已完成
DONE: Assistant 模型删除 temperature/topP 字段、copyWith 参数、clearTemperature/clearTopP、toJson/fromJson 键；AssistantProvider 三处默认助手不再设置采样默认值；chat_actions.dart 删除 temperature/topP 透传；助手设置桌面面板与手机基础页删除 Temperature / Top P 入口及 _showTemperatureSheet / _showTopPSheet；app_control_service.dart 删除 temperature / top_p 补丁分支并更新能力描述；app_control_service_test.dart 同步去掉 temperature 断言；版本号 bump 到 1.1.30+9024；CI run 175 编译通过；Release v1.1.30 已发布（arm64-v8a / x86_64）
NEXT: 无，等待下一个任务