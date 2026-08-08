import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../icons/reasoning_icons.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/dialogs/reasoning_budget_custom_dialog.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../core/services/haptics.dart';
import '../../../theme/app_font_weights.dart';
import 'thinking_effort_stack.dart';

Future<void> showReasoningBudgetSheet(
  BuildContext context, {
  String? modelProvider,
  String? modelId,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) =>
        _ReasoningBudgetSheet(modelProvider: modelProvider, modelId: modelId),
  );
}

/// 推理强度档位的稳定标识。
///
/// 不直接用 budget 数值当 id：Ultracode 与 Max/Xhigh 会共用同一个 budget，
/// 靠 id 才能区分选中态。
class _EffortIds {
  const _EffortIds._();

  static const String off = 'off';
  static const String auto = 'auto';
  static const String light = 'light';
  static const String medium = 'medium';
  static const String heavy = 'heavy';
  static const String xhigh = 'xhigh';
  static const String max = 'max';
  static const String ultracode = 'ultracode';
  static const String custom = 'custom';
}

class _ReasoningBudgetSheet extends StatefulWidget {
  const _ReasoningBudgetSheet({this.modelProvider, this.modelId});
  final String? modelProvider;
  final String? modelId;
  @override
  State<_ReasoningBudgetSheet> createState() => _ReasoningBudgetSheetState();
}

class _ReasoningBudgetSheetState extends State<_ReasoningBudgetSheet> {
  /// 显式档位 id 的持久化 key。
  ///
  /// 只用 budget 数值无法区分 Ultracode 与 Max/Xhigh（它们共享同一预算），
  /// 因此把用户显式点选的档位 id 单独持久化一份，面板重开时恢复选中态。
  static const String _effortIdKey = 'thinking_effort_id_v1';

  late int _selected;

  /// 记录用户在本次会话里显式点选的档位 id。
  ///
  /// 只靠 budget 反查会在 Ultracode 与 Max 之间产生歧义（两者 budget 相同），
  /// 因此显式点选时以这里为准；面板重开时也会从本地恢复该值。
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>();
    _selected = s.thinkingBudget ?? -1;
    _loadPersistedEffortId();
  }

  /// 从本地恢复上次显式选择的档位 id。
  ///
  /// 异步读取（SharedPreferences），若本次面板内用户已做过选择则跳过。
  Future<void> _loadPersistedEffortId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_effortIdKey);
    if (!mounted || id == null || _selectedId != null) return;
    setState(() => _selectedId = id);
  }

  Future<void> _select(int value, {String? id}) async {
    setState(() {
      _selected = value;
      _selectedId = id;
    });
    await context.read<SettingsProvider>().setThinkingBudget(value);
    // 持久化显式档位 id，用于区分共享同一 budget 的档位（如 Ultracode 与 Max）。
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_effortIdKey);
    } else {
      await prefs.setString(_effortIdKey, id);
    }
  }

  bool _isCustomSelected({required bool showXhigh, required bool showMax}) {
    final presets = <int>{
      -1, // auto
      0, // off
      1024,
      16000,
      32000,
      if (showXhigh) 64000,
      if (showMax) 128000,
    };
    return !presets.contains(_selected);
  }

  Future<void> _openCustomBudget() async {
    Haptics.light();
    final settings = context.read<SettingsProvider>();
    final isCurrentCustom = _isCustomSelected(
      showXhigh: _showXhighOption(settings),
      showMax: _showMaxOption(settings),
    );
    final initialValue = isCurrentCustom ? _selected : 2048;
    final chosen = await ReasoningBudgetCustomDialog.show(
      context,
      initialValue: initialValue,
    );
    if (!mounted || chosen == null) return;
    await _select(chosen, id: _EffortIds.custom);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  /// 复用桌面端推理面板同一套 SVG 档位图标。
  Widget Function(Color) _budgetIcon(int budget) {
    return (Color color) =>
        ReasoningIcons.budgetIcon(budget, size: 17, color: color);
  }

  /// 构建堆叠式档位列表。
  ///
  /// 顺序固定为：关闭 → 自动 → 轻度 → 中度 → 重度，之后按模型能力追加
  /// 更高档位（Xhigh / Max / Ultracode）。
  List<ThinkingEffortOption> _options(
    AppLocalizations l10n, {
    required bool showXhigh,
    required bool showMax,
  }) {
    return <ThinkingEffortOption>[
      ThinkingEffortOption(
        id: _EffortIds.off,
        label: l10n.reasoningBudgetSheetOff,
        budget: 0,
        leadingBuilder: _budgetIcon(ReasoningIcons.offBudget),
      ),
      ThinkingEffortOption(
        id: _EffortIds.auto,
        label: l10n.reasoningBudgetSheetAuto,
        budget: -1,
        leadingBuilder: _budgetIcon(ReasoningIcons.autoBudget),
      ),
      ThinkingEffortOption(
        id: _EffortIds.light,
        label: l10n.reasoningBudgetSheetLight,
        budget: 1024,
        description: l10n.reasoningBudgetSheetLightSubtitle,
        leadingBuilder: _budgetIcon(ReasoningIcons.lightBudget),
      ),
      ThinkingEffortOption(
        id: _EffortIds.medium,
        label: l10n.reasoningBudgetSheetMedium,
        budget: 16000,
        description: l10n.reasoningBudgetSheetMediumSubtitle,
        leadingBuilder: _budgetIcon(ReasoningIcons.mediumBudget),
      ),
      ThinkingEffortOption(
        id: _EffortIds.heavy,
        label: l10n.reasoningBudgetSheetHeavy,
        budget: 32000,
        description: l10n.reasoningBudgetSheetHeavySubtitle,
        leadingBuilder: _budgetIcon(ReasoningIcons.heavyBudget),
      ),
      if (showXhigh)
        ThinkingEffortOption(
          id: _EffortIds.xhigh,
          label: l10n.reasoningBudgetSheetXhigh,
          budget: 64000,
          description: l10n.reasoningBudgetSheetXhighSubtitle,
          leadingBuilder: _budgetIcon(ReasoningIcons.xhighBudget),
        ),
      if (showMax)
        ThinkingEffortOption(
          id: _EffortIds.max,
          label: l10n.reasoningBudgetSheetMax,
          budget: 128000,
          description: l10n.reasoningBudgetSheetMaxSubtitle,
          leadingBuilder: _budgetIcon(ReasoningIcons.maxBudget),
        ),
      if (showXhigh || showMax)
        ThinkingEffortOption(
          id: _EffortIds.ultracode,
          label: l10n.reasoningBudgetSheetUltracode,
          budget: showMax ? 128000 : 64000,
          description: l10n.reasoningBudgetSheetUltracodeSubtitle,
          leadingBuilder: (color) =>
              Icon(Lucide.Sparkles, size: 17, color: color),
          accent: true,
        ),
    ];
  }

  /// 解析当前应高亮哪一行。
  ///
  /// 优先使用显式选择的 id，但只有在该 id 对应的档位与当前 budget 匹配时才
  /// 采用（避免 budget 被覆盖后仍显示旧档位）；否则按 budget 反查第一个匹配
  /// 项，这样从设置恢复进来时也能正确高亮。
  String? _resolveSelectedId(List<ThinkingEffortOption> options) {
    final explicit = _selectedId;
    if (explicit != null) {
      for (final option in options) {
        if (option.id == explicit && option.budget == _selected) {
          return explicit;
        }
      }
    }
    for (final option in options) {
      if (option.budget == _selected) return option.id;
    }
    return null;
  }

  bool _showXhighOption(SettingsProvider settings) {
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final currentProvider =
        widget.modelProvider ??
        assistant?.chatModelProvider ??
        settings.currentModelProvider;
    final currentModelId =
        widget.modelId ?? assistant?.chatModelId ?? settings.currentModelId;
    if (currentProvider == null || currentModelId == null) return false;
    return settings.supportsXhighReasoning(currentProvider, currentModelId);
  }

  bool _showMaxOption(SettingsProvider settings) {
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final currentProvider =
        widget.modelProvider ??
        assistant?.chatModelProvider ??
        settings.currentModelProvider;
    final currentModelId =
        widget.modelId ?? assistant?.chatModelId ?? settings.currentModelId;
    if (currentProvider == null || currentModelId == null) return false;
    return settings.supportsMaxReasoning(currentProvider, currentModelId);
  }

  Widget _customEntry({required bool active}) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final color = active ? cs.primary : cs.onSurface.withValues(alpha: 0.78);
    return IosCardPress(
      borderRadius: BorderRadius.circular(14),
      baseColor: active
          ? cs.primaryContainer.withValues(alpha: 0.38)
          : cs.surfaceContainerHighest.withValues(alpha: 0.42),
      border: Border.all(
        color: active
            ? cs.primary.withValues(alpha: 0.55)
            : cs.outlineVariant.withValues(alpha: 0.30),
        width: active ? 1.4 : 1,
      ),
      duration: const Duration(milliseconds: 200),
      onTap: _openCustomBudget,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(Lucide.Hash, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.reasoningBudgetSheetCustomShortLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: active
                    ? AppFontWeights.emphasis
                    : AppFontWeights.medium,
                color: color,
              ),
            ),
          ),
          if (active)
            Text(
              _selected.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: AppFontWeights.medium,
                color: color,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final showXhigh = _showXhighOption(settings);
    final showMax = _showMaxOption(settings);
    final customActive = _isCustomSelected(
      showXhigh: showXhigh,
      showMax: showMax,
    );
    final cs = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;
    final options = _options(l10n, showXhigh: showXhigh, showMax: showMax);
    final selectedId = customActive ? null : _resolveSelectedId(options);

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ThinkingEffortStack(
                    title: l10n.reasoningBudgetSheetTitle,
                    options: options,
                    selectedId: selectedId,
                    onSelected: (option) async {
                      Haptics.light();
                      final navigator = Navigator.of(context);
                      await _select(option.budget, id: option.id);
                      if (!mounted) return;
                      // 关闭 / 自动 是一次性选择，选完直接收起面板，
                      // 与原来底部快捷按钮的行为保持一致。
                      if (option.id == _EffortIds.off ||
                          option.id == _EffortIds.auto) {
                        navigator.maybePop();
                      }
                    },
                    footer: _customEntry(active: customActive),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
