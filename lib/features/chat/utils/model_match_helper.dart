import 'package:flutter/material.dart';

import '../../../core/models/assistant.dart';
import '../../../core/providers/settings_provider.dart';

/// 将模型 ID 归一化为小写 token 列表。
///
/// 忽略大小写以及 `-` `_` `.` `/` 空格等符号差异，只保留字母与数字片段，
/// 用于"本次回答模型"与"当前对话模型"的宽松一致性判断。
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

/// 消息操作栏的模型一致性指示灯。
///
/// 每次模型回答结束后，将该回答的模型与当前对话配置的模型做宽松比较：
/// - 一致 → 绿灯
/// - 不一致 → 橙灯
/// 点击圆点以气泡显示本次回答使用的模型型号。
class ModelMatchIndicator extends StatelessWidget {
  const ModelMatchIndicator({
    super.key,
    required this.answerModelId,
    required this.answerProviderId,
    required this.assistant,
    required this.settings,
  });

  /// 本次回答消息上记录的模型 ID（可能为 null，如历史/本地消息）。
  final String? answerModelId;

  /// 本次回答消息上记录的 provider ID。
  final String? answerProviderId;

  /// 当前对话绑定的 assistant（可能为 null，此时用全局默认模型）。
  final Assistant? assistant;

  final SettingsProvider settings;

  static const Color _matchColor = Color(0xFF34C759);
  static const Color _mismatchColor = Color(0xFFFF9500);

  @override
  Widget build(BuildContext context) {
    final answerApiId = resolveApiModelId(
      settings,
      providerKey: answerProviderId,
      modelId: answerModelId,
    );
    if (answerApiId == null) return const SizedBox.shrink();

    final activeApiId = resolveActiveApiModelId(settings, assistant);
    if (activeApiId == null) return const SizedBox.shrink();

    final matched = isSameModel(answerApiId, activeApiId);
    final color = matched ? _matchColor : _mismatchColor;

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: Tooltip(
            message: answerApiId,
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
