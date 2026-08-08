import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../core/models/assistant.dart';
import '../../../core/providers/settings_provider.dart';

/// 将模型 ID 归一化为小写 token 列表。
///
/// 忽略大小写以及 `-` `_` `.` `/` 空格等符号差异，只保留字母与数字片段，
/// 用于模型一致性/对账判断。
List<String> normalizeModelTokens(String modelId) {
  return modelId
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

/// 两个模型 ID 是否视为同一模型。
///
/// 只要 名称 + 数字 + 后缀等级（如 pro / flash / sol）按顺序拼接后一致，
/// 即判定为同一模型，忽略大小写与符号差异。
bool isSameModel(String a, String b) {
  final ta = normalizeModelTokens(a);
  final tb = normalizeModelTokens(b);
  if (ta.isEmpty || tb.isEmpty) return false;
  if (ta.length != tb.length) return false;
  for (var i = 0; i < ta.length; i++) {
    if (ta[i] != tb[i]) return false;
  }
  return true;
}

/// 判断“底层响应自报模型”是否匹配“请求模型”。
///
/// 除了完全一致外，允许一方是另一方的前缀（官方/中转站常给请求模型追加
/// 日期或版本后缀，如 `gpt-4o` -> `gpt-4o-2024-05-13`）。只要前缀序列
/// 相同即视为匹配；完全不同的模型（如请求 gpt-4o、响应 gpt-3.5-turbo）
/// 会被判定为不匹配，从而暴露被偷换/掺水的假模型。
bool isRespondedModelMatching(String requested, String responded) {
  final tReq = normalizeModelTokens(requested);
  final tResp = normalizeModelTokens(responded);
  if (tReq.isEmpty || tResp.isEmpty) return false;
  if (isSameModel(requested, responded)) return true;

  final int minLen = tReq.length < tResp.length ? tReq.length : tResp.length;
  if (minLen == 0) return false;
  for (var i = 0; i < minLen; i++) {
    if (tReq[i] != tResp[i]) return false;
  }
  return true;
}

/// 解析配置中的真实 API 模型 ID。
///
/// 优先使用 override 的 `apiModelId`（或 `api_model_id`），否则回退到原始
/// modelId；modelId 为空时返回 null。
String? resolveApiModelId(
  SettingsProvider settings, {
  String? providerKey,
  required String? modelId,
}) {
  if (modelId == null || modelId.trim().isEmpty) return null;
  var apiId = modelId;
  if (providerKey != null && providerKey.isNotEmpty) {
    try {
      final cfg = settings.getProviderConfig(providerKey);
      final ov = cfg.modelOverrides[modelId] as Map?;
      final overrideApiId = ov == null
          ? null
          : (ov['apiModelId'] ?? ov['api_model_id'])?.toString().trim();
      if (overrideApiId != null && overrideApiId.isNotEmpty) {
        apiId = overrideApiId;
      }
    } catch (_) {
      // 配置缺失时回退到原始 modelId
    }
  }
  return apiId;
}

/// 解析当前对话应使用的真实 API 模型 ID（assistant 优先，回退全局默认）。
String? resolveActiveApiModelId(
  SettingsProvider settings,
  Assistant? assistant,
) {
  final providerKey =
      assistant?.chatModelProvider ?? settings.currentModelProvider;
  final modelId = assistant?.chatModelId ?? settings.currentModelId;
  if (providerKey == null || modelId == null || modelId.trim().isEmpty) {
    return null;
  }
  return resolveApiModelId(
    settings,
    providerKey: providerKey,
    modelId: modelId,
  );
}

/// 内存级注册表：messageId -> 底层响应自报模型 ID。
///
/// 由 chat_actions 在消费流式 chunk 时写入，UI 指示灯据此做“请求模型 vs
/// 响应模型”对账。仅存内存（不持久化）：应用重启后历史消息不再显示对账
/// 指示灯，新回答仍会正常记录与展示。
class RespondedModelRegistry {
  RespondedModelRegistry._();

  static final Map<String, String> _records = <String, String>{};

  static void record(String messageId, String modelId) {
    final key = messageId.trim();
    final value = modelId.trim();
    if (key.isEmpty || value.isEmpty) return;
    _records[key] = value;
  }

  static String? lookup(String messageId) {
    final key = messageId?.trim() ?? '';
    if (key.isEmpty) return null;
    return _records[key];
  }

  static void remove(String messageId) {
    final key = messageId?.trim() ?? '';
    if (key.isEmpty) return;
    _records.remove(key);
  }

  @visibleForTesting
  static void clear() => _records.clear();
}

/// 消息操作栏的模型对账指示灯。
///
/// 语义（基于底层模型发来的数据，而非用户本地选择）：
/// - 有响应自报模型：与本次请求实际发送的 API 模型匹配 → 绿灯；
///   不匹配 → 橙灯（疑似被中转站偷换成别的模型）。
/// - 无响应自报模型（如 Gemini 或历史消息）但本次请求开启了推理、
///   响应却没有任何推理内容 → 橙灯（疑似降智，用非推理模型冒充）。
/// - 其余情况不显示，避免误报。
/// 点击圆点以气泡显示“请求模型 → 响应模型”。
class ModelMatchIndicator extends StatelessWidget {
  const ModelMatchIndicator({
    super.key,
    required this.answerModelId,
    required this.answerProviderId,
    this.assistant,
    required this.settings,
    this.messageId,
    this.reasoningRequested = false,
    this.reasoningOutput = false,
  });

  /// 消息上记录的请求模型 ID（逻辑 ID，创建消息时写入）。
  final String? answerModelId;

  /// 消息上记录的 provider ID。
  final String? answerProviderId;

  /// 当前对话绑定的 assistant（保留兼容，不再用于对账）。
  final Assistant? assistant;

  final SettingsProvider settings;

  /// 消息 ID：用于从 RespondedModelRegistry 读取响应自报模型。
  final String? messageId;

  /// 本次请求是否开启了推理（模型支持且 thinkingBudget 启用）。
  final bool reasoningRequested;

  /// 本次响应是否实际产生了推理内容。
  final bool reasoningOutput;

  static const Color _matchColor = Color(0xFF34C759);
  static const Color _mismatchColor = Color(0xFFFF9500);

  @override
  Widget build(BuildContext context) {
    final requestedApiId = resolveApiModelId(
      settings,
      providerKey: answerProviderId,
      modelId: answerModelId,
    );
    if (requestedApiId == null || requestedApiId.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final responded = (messageId != null)
        ? RespondedModelRegistry.lookup(messageId)
        : null;
    final respondedTrimmed = responded?.trim() ?? '';

    Color color;
    String tooltip;
    if (respondedTrimmed.isNotEmpty) {
      final matched = isRespondedModelMatching(requestedApiId, respondedTrimmed);
      color = matched ? _matchColor : _mismatchColor;
      tooltip = '$requestedApiId →\n$respondedTrimmed';
    } else if (reasoningRequested && !reasoningOutput) {
      // 请求了推理但没有返回任何推理内容：疑似降智（用非推理模型冒充）。
      color = _mismatchColor;
      tooltip = '$requestedApiId → ?';
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: Tooltip(
            message: tooltip,
            triggerMode: TooltipTriggerMode.tap,
            waitDuration: Duration.zero,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}