TASK: 多 Key 自动故障转移接线（方案 A / 做法一变体）
STEP: 已完成代码修改与自检，等待 CI（flutter analyze + flutter test）
BRANCH: main
CONTEXT: updateKeyStatus / recordKeyUsage 此前全仓库零调用，导致 usage 永远为 0、
  leastUsed 退化为固定选第一个 key、maxFailuresBeforeDisable /
  failureRecoveryTimeMinutes / enableAutoRecovery 三项配置完全失效。
DONE: lib/core/services/api_key_manager.dart 重写
  - 新增内存态 runtime health overlay（_KeyHealth），叠加在持久化配置之上
  - 新增 reportHttpOutcome(headers, statusCode)，按 auth 头反查 key 归因
  - 失败判定仅 401/403/429/5xx；4xx 请求类错误与传输层错误不计入
  - 429 单独标记 rateLimited，独立 60s 冷却
  - 修复 rateLimited 永久不可用的筛选漏洞
  - enableAutoRecovery=false 时过冷却也不放行
  - 删除零调用的 recordKeyUsage 与重复计数的 _keyUsageMap
  - Random 提为 static，轮询指针保持内存态并注明原因
DONE: lib/core/services/network/dio_http_client.dart 在拿到 statusCode 后调用
  ApiKeyManager().reportHttpOutcome，统一上报点，5 个 provider 文件零改动
DONE: test/api_key_manager_test.dart 新增 11 条 runtime health 测试
SELF_CHECK: recordKeyUsage / _keyUsageMap 在 lib 与 test 中均已无引用；
  import 路径 ../api_key_manager.dart 相对 network/ 目录正确；
  _KeyHealth 与 _KeyBinding 字段无未使用项
TRADEOFF: 运行时健康状态不跨重启（冷启动给所有 key 重新试探）；
  多 Key 管理页状态灯仍只反映手动检测结果，不显示运行时熔断
NEXT: lib/core/services/api_key_manager.dart
PENDING: 世界书任务遗留 —— 清理临时 wb-verify workflow/脚本
PENDING: 可选项 —— 提取 api_key_health_store.dart 实现健康状态持久化 + UI 可见
