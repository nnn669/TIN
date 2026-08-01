import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局「MCP 工具自动执行」开关。
///
/// 语义（与助手「神经权能网关」审批完全independent）：
/// - 开启（默认）：所有 MCP 工具调用直接执行，不再弹出审批。
///   逐个工具上的 `McpToolConfig.needsApproval` 配置被忽略。
/// - 关闭：回到原有逻辑，即按 `McpToolConfig.needsApproval` 逐工具决定是否审批。
///
/// 这里刻意做成独立的轻量单例而不是塞进 `McpProvider` 或 `SettingsProvider`：
/// 那两个类分别是 66KB / 192KB 的巨型 ChangeNotifier，任何 `notifyListeners()`
/// 都会唤醒大量监听者。一个只承载单个 bool 的 [ValueNotifier] 让开关的重建范围
/// 收敛到真正关心它的 widget。
class McpToolAutoApprovalStore {
  McpToolAutoApprovalStore._internal() {
    // 构造即开始加载，调用方可通过 [ensureLoaded] 等待。
    _loadFuture = _load();
  }

  static final McpToolAutoApprovalStore instance =
      McpToolAutoApprovalStore._internal();

  /// 供测试使用：构造一个不共享状态的实例。
  @visibleForTesting
  factory McpToolAutoApprovalStore.forTesting() =>
      McpToolAutoApprovalStore._internal();

  static const String prefsKey = 'mcp_tool_auto_approval_v1';

  /// 默认自动执行：按需求「MCP 的所有审批权限全部取消」。
  static const bool defaultEnabled = true;

  final ValueNotifier<bool> _enabled = ValueNotifier<bool>(defaultEnabled);

  Future<void>? _loadFuture;

  /// 可监听的开关状态。UI 用 `ValueListenableBuilder` 订阅即可。
  ValueListenable<bool> get listenable => _enabled;

  /// 当前是否自动执行（不需要审批）。
  bool get enabled => _enabled.value;

  /// 等待首次持久化读取完成。
  ///
  /// 工具调用链路是异步的，因此在判断审批前 `await` 这里即可保证读到的是用户
  /// 真实设置，而不是构造时的默认值。
  Future<void> ensureLoaded() async {
    final pending = _loadFuture;
    if (pending == null) return;
    try {
      await pending;
    } catch (_) {
      // 读取失败时保持默认值，不阻断工具调用。
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(prefsKey);
      if (stored != null) {
        _enabled.value = stored;
      }
    } finally {
      _loadFuture = null;
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled.value == value) return;
    _enabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, value);
    } catch (_) {
      // 持久化失败时内存状态仍然生效，下次启动回退到默认值。
    }
  }

  /// 供测试重置。
  @visibleForTesting
  void resetForTesting({bool value = defaultEnabled}) {
    _enabled.value = value;
    _loadFuture = null;
  }
}