import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/services/instruction_injection_store.dart';
import '../../../core/models/instruction_injection.dart';
import '../../../core/providers/instruction_injection_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../model/widgets/ocr_prompt_sheet.dart';

class BottomToolsSheet extends StatelessWidget {
  const BottomToolsSheet({super.key, this.onCamera, this.onPhotos, this.onUpload, this.onClear, this.clearLabel});

  final VoidCallback? onCamera;
  final VoidCallback? onPhotos;
  final VoidCallback? onUpload;
  final VoidCallback? onClear;
  final String? clearLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bg = Theme.of(context).colorScheme.surface;
    final maxHeight = MediaQuery.of(context).size.height * 0.8;

    Widget roundedAction({required IconData icon, required String label, VoidCallback? onTap}) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final cardColor = isDark ? Colors.white10 : const Color(0xFFF2F3F5);
      return Expanded(
        child: SizedBox(
          height: 72,
          child: IosCardPress(
            baseColor: cardColor,
            borderRadius: BorderRadius.circular(14),
            pressedScale: 0.98,
            duration: const Duration(milliseconds: 260),
            onTap: () {
              Haptics.light();
              onTap?.call();
            },
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: Theme.of(context).colorScheme.onSurface),
                  const SizedBox(height: 6),
                  Text(label, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        roundedAction(
                          icon: Lucide.Camera,
                          label: l10n.bottomToolsSheetCamera,
                          onTap: onCamera,
                        ),
                        const SizedBox(width: 12),
                        roundedAction(
                          icon: Lucide.Image,
                          label: l10n.bottomToolsSheetPhotos,
                          onTap: onPhotos,
                        ),
                        const SizedBox(width: 12),
                        roundedAction(
                          icon: Lucide.Paperclip,
                          label: l10n.bottomToolsSheetUpload,
                          onTap: onUpload,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _LearningAndClearSection(clearLabel: clearLabel, onClear: onClear),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LearningAndClearSection extends StatefulWidget {
  const _LearningAndClearSection({this.onClear, this.clearLabel});
  final VoidCallback? onClear;
  final String? clearLabel;

  @override
  State<_LearningAndClearSection> createState() => _LearningAndClearSectionState();
}

class _LearningAndClearSectionState extends State<_LearningAndClearSection> {
  Widget _row({required IconData icon, required String label, bool selected = false, VoidCallback? onTap, VoidCallback? onLongPress}) {
    final cs = Theme.of(context).colorScheme;
    final onColor = selected ? cs.primary : cs.onSurface;
    final radius = BorderRadius.circular(14);
    return SizedBox(
      height: 48,
      child: IosCardPress(
        borderRadius: radius,
        baseColor: Theme.of(context).colorScheme.surface,
        duration: const Duration(milliseconds: 260),
        onTap: onTap,
        onLongPress: onLongPress,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: onColor),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: onColor))),
            if (selected) Icon(Lucide.Check, size: 18, color: cs.primary) else const SizedBox(width: 18),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<InstructionInjectionProvider>();
    final settings = context.watch<SettingsProvider>();
    final items = provider.items;
    final hasOcrModel = settings.ocrModelProvider != null && settings.ocrModelId != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (items.isEmpty)
          _row(
            icon: Lucide.Layers,
            label: l10n.instructionInjectionTitle,
            selected: false,
            onTap: () {},
            onLongPress: () => _showLearningPromptSheet(context),
          )
        else ...[
          for (int i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 8),
              child: _row(
                icon: Lucide.Layers,
                label: items[i].title.trim().isEmpty
                    ? l10n.instructionInjectionDefaultTitle
                    : items[i].title,
                selected: provider.isActive(items[i].id),
                onTap: () async {
                  Haptics.light();
                  final p = context.read<InstructionInjectionProvider>();
                  await p.toggleActiveId(items[i].id);
                },
                onLongPress: () => _editInstructionInjectionPrompt(context, items[i]),
              ),
            ),
        ],
        if (hasOcrModel) ...[
          const SizedBox(height: 8),
          _row(
            icon: Lucide.Eye,
            label: l10n.bottomToolsSheetOcr,
            selected: settings.ocrEnabled,
            onTap: () async {
              Haptics.light();
              final sp = context.read<SettingsProvider>();
              await sp.setOcrEnabled(!sp.ocrEnabled);
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).maybePop();
              }
            },
            onLongPress: () => showOcrPromptSheet(context),
          ),
        ],
        const SizedBox(height: 8),
        _row(
          icon: Lucide.Eraser,
          label: widget.clearLabel ?? l10n.bottomToolsSheetClearContext,
          onTap: () {
            Haptics.light();
            widget.onClear?.call();
          },
        ),
      ],
    );
  }

  Future<void> _showLearningPromptSheet(BuildContext context) async {
    final provider = context.read<InstructionInjectionProvider>();
    await provider.initialize();
    final items = provider.items;
    if (items.isEmpty) return;
    final target = provider.active ?? items.first;
    await _editInstructionInjectionPrompt(context, target);
  }
}

class _InstructionInjectionSheet extends StatelessWidget {
  const _InstructionInjectionSheet();

  @override
  Widget build(BuildContext context) {
    // 已弃用：指令注入列表现在直接渲染在 BottomToolsSheet 中。
    return const SizedBox.shrink();
  }
}

class _InstructionInjectionListItem extends StatelessWidget {
  const _InstructionInjectionListItem({
    required this.item,
    required this.title,
    required this.active,
  });

  final InstructionInjection item;
  final String title;
  final bool active;

  @override
  Widget build(BuildContext context) {
    // 已不再使用独立卡片样式，保留空壳避免潜在引用问题。
    return const SizedBox.shrink();
  }
}

Future<void> _editInstructionInjectionPrompt(BuildContext context, InstructionInjection item) async {
  final l10n = AppLocalizations.of(context)!;
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final bool showNameField = item.title.trim().isNotEmpty;
  final titleController = TextEditingController(text: item.title);
  final controller = TextEditingController(text: item.prompt);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                l10n.instructionInjectionEditTitle,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
            if (showNameField) ...[
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.instructionInjectionNameLabel,
                  filled: true,
                  fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withOpacity(0.4),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: cs.outlineVariant.withOpacity(0.4),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: controller,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: l10n.instructionInjectionPromptLabel,
                alignLabelWithHint: true,
                filled: true,
                fillColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withOpacity(0.4),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withOpacity(0.4),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.primary.withOpacity(0.5)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _IosOutlineButton(
                    label: l10n.quickPhraseCancelButton,
                    onTap: () => Navigator.of(ctx).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _IosFilledButton(
                    label: l10n.quickPhraseSaveButton,
                    onTap: () async {
                      final newTitle = showNameField ? titleController.text.trim() : item.title;
                      final updated = item.copyWith(
                        title: newTitle,
                        prompt: controller.text.trim(),
                      );
                      await ctx.read<InstructionInjectionProvider>().update(updated);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                  ),
                ),
              ],
            ),
            ],
          ),
        ),
      );
    },
  );
}

class _IosOutlineButton extends StatefulWidget {
  const _IosOutlineButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_IosOutlineButton> createState() => _IosOutlineButtonState();
}

class _IosOutlineButtonState extends State<_IosOutlineButton> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => Future.delayed(const Duration(milliseconds: 80), () => _set(false)),
      onTapCancel: () => _set(false),
      onTap: () {
        Haptics.soft();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _IosFilledButton extends StatefulWidget {
  const _IosFilledButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_IosFilledButton> createState() => _IosFilledButtonState();
}

class _IosFilledButtonState extends State<_IosFilledButton> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => Future.delayed(const Duration(milliseconds: 80), () => _set(false)),
      onTapCancel: () => _set(false),
      onTap: () {
        Haptics.soft();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: cs.primary,
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
