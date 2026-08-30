import 'package:flutter/material.dart';

import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/app_font_weights.dart';

/// 堆叠式推理强度选项。
@immutable
class ThinkingEffortOption {
  const ThinkingEffortOption({
    required this.id,
    required this.label,
    required this.budget,
    this.description,
    this.trailingText,
    this.leadingBuilder,
    this.accent = false,
  });

  /// 稳定标识，仅用于选中比对与 widget key，不参与展示。
  final String id;

  final String label;

  /// 对应的 `thinkingBudget` 值。0 = 关闭，-1 = 自动，其余为 token 预算。
  final int budget;

  final String? description;

  /// 右侧附加文案，例如自定义档位显示当前数值。
  final String? trailingText;

  /// 前置图标构建器，参数为当前应使用的前景色。
  ///
  /// 用 builder 而不是 [IconData]，是为了能直接复用 `ReasoningIcons` 的 SVG
  /// 档位图标（与桌面端推理面板保持同一套视觉）。
  final Widget Function(Color color)? leadingBuilder;

  /// 是否使用强调色描绘（用于 Ultracode 这类特殊档位）。
  final bool accent;
}

/// 堆叠（纵向列表）式推理强度选择器。
///
/// 替代原来的横向滑块：每个档位独立成行，命中区域更大，也不再需要用户
/// 靠拖拽去猜档位边界。视觉上复用 App 既有的 [IosCardPress] 与
/// `ColorScheme`，因此会自动跟随主题色与深浅色模式。
class ThinkingEffortStack extends StatelessWidget {
  const ThinkingEffortStack({
    super.key,
    required this.options,
    required this.selectedId,
    required this.onSelected,
    this.title,
    this.footer,
  });

  static const ValueKey<String> stackKey = ValueKey<String>(
    'thinking-effort-stack',
  );

  static ValueKey<String> optionKey(String id) =>
      ValueKey<String>('thinking-effort-option-$id');

  final List<ThinkingEffortOption> options;

  /// 当前选中的选项 id；为 null 时不高亮任何行。
  final String? selectedId;

  final ValueChanged<ThinkingEffortOption> onSelected;

  final String? title;

  /// 列表底部附加内容（例如自定义档位入口）。
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (options.isEmpty) return const SizedBox.shrink();

    return Column(
      key: stackKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title!,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                fontWeight: AppFontWeights.emphasis,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
        for (int i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _ThinkingEffortRow(
            option: options[i],
            selected: options[i].id == selectedId,
            onTap: () => onSelected(options[i]),
          ),
        ],
        if (footer != null) ...[const SizedBox(height: 8), footer!],
      ],
    );
  }
}

class _ThinkingEffortRow extends StatelessWidget {
  const _ThinkingEffortRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ThinkingEffortOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // 强调档位（Ultracode）用 tertiary，普通选中用 primary，保持与主题一致。
    final Color activeColor = option.accent ? cs.tertiary : cs.primary;
    final Color labelColor = selected
        ? activeColor
        : cs.onSurface.withValues(alpha: 0.86);
    final Color descColor = cs.onSurface.withValues(alpha: 0.56);
    final Color leadingColor = selected ? activeColor : descColor;

    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      child: IosCardPress(
        key: ThinkingEffortStack.optionKey(option.id),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        baseColor: selected
            ? activeColor.withValues(alpha: isDark ? 0.20 : 0.10)
            : cs.surfaceContainerHighest.withValues(
                alpha: isDark ? 0.34 : 0.46,
              ),
        border: Border.all(
          color: selected
              ? activeColor.withValues(alpha: 0.55)
              : cs.outlineVariant.withValues(alpha: 0.30),
          width: selected ? 1.4 : 1,
        ),
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            if (option.leadingBuilder != null) ...[
              SizedBox(
                width: 20,
                height: 20,
                child: Center(child: option.leadingBuilder!(leadingColor)),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 15,
                      fontWeight: selected
                          ? AppFontWeights.emphasis
                          : AppFontWeights.medium,
                      color: labelColor,
                    ),
                  ),
                  if (option.description != null &&
                      option.description!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      option.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 1.35,
                        color: descColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (option.trailingText != null &&
                option.trailingText!.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(
                option.trailingText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  fontWeight: AppFontWeights.medium,
                  color: selected ? activeColor : descColor,
                ),
              ),
            ],
            const SizedBox(width: 8),
            // 选中态用一个描边圆点表示，避免额外引入图标依赖。
            _SelectionDot(selected: selected, activeColor: activeColor),
          ],
        ),
      ),
    );
  }
}

class _SelectionDot extends StatelessWidget {
  const _SelectionDot({required this.selected, required this.activeColor});

  final bool selected;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? activeColor : Colors.transparent,
        border: Border.all(
          color: selected ? activeColor : cs.onSurface.withValues(alpha: 0.28),
          width: selected ? 1.4 : 1.2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surface,
                ),
              ),
            )
          : null,
    );
  }
}
