TASK: 工具调用循环无轮次上限（最严重）
STEP: 已完成
DONE: 工具调用次数已改为无限制。ToolLoopGuard 移除调用预算与死循环拦截：不再有 100 次预算（ToolLoopBudgetExceeded 已删除），同名同参连续调用不再判死循环，evaluate 仅维护每轮 callCount 统计并始终放行；generation_controller.dart 的 buildToolCallHandler 同步移除 refusal/重试判定与 resetDuplicateStreak 调用。只读结果缓存（ToolCallResultCache）保留：仅 search_web 与 Kelivo Fetch 四个只读工具按完整签名复用成功结果，工具错误、MCP isError、异常与失败结果仍清除缓存并保留重试能力。更新 test/core/services/api/tool_loop_guard_test.dart 与 tool_call_result_cache_policy_test.dart 回归覆盖。
NEXT: 等待最终 Actions 验证