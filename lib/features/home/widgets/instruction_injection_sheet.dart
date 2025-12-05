import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/instruction_injection_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../core/services/haptics.dart';

/// Bottom sheet for displaying instruction injection items on mobile/tablet.
///
/// This widget shows a list of instruction injection prompts that can be
/// toggled on/off for the current assistant.
class InstructionInjectionSheet extends StatelessWidget {
  const InstructionInjectionSheet({
    super.key,
    required this.assistantId,
  });

  final String? assistantId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        minChildSize: 0.35,
        builder: (ctx, controller) {
          final p = ctx.watch<InstructionInjectionProvider>();
          final list = p.items;
          final activeIds = p.activeIdsFor(assistantId).toSet();
          return Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.instructionInjectionTitle,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.instructionInjectionSheetSubtitle,
                            style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: list.isEmpty
                      ? Center(
                          child: Text(
                            l10n.instructionInjectionEmptyMessage,
                            style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
                          ),
                        )
                      : ListView.separated(
                          controller: controller,
                          itemCount: list.length,
                          itemBuilder: (ctx, index) {
                            final item = list[index];
                            final displayTitle = item.title.trim().isEmpty
                                ? l10n.instructionInjectionDefaultTitle
                                : item.title;
                            final active = activeIds.contains(item.id);
                            return IosCardPress(
                              borderRadius: BorderRadius.circular(14),
                              baseColor: Theme.of(ctx).brightness == Brightness.dark
                                  ? Colors.white10
                                  : Colors.white.withOpacity(0.96),
                              duration: const Duration(milliseconds: 260),
                              onTap: () async {
                                Haptics.light();
                                final prov = ctx.read<InstructionInjectionProvider>();
                                await prov.toggleActiveId(item.id, assistantId: assistantId);
                              },
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: Theme.of(ctx).brightness == Brightness.dark
                                          ? Colors.white10
                                          : const Color(0xFFF2F3F5),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(Lucide.Layers, size: 20, color: cs.primary),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                displayTitle,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: active ? cs.primary : cs.onSurface,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (active) ...[
                                              const SizedBox(width: 6),
                                              Icon(Lucide.Check, size: 16, color: cs.primary),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          item.prompt,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: cs.onSurface.withOpacity(0.72),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Shows the instruction injection bottom sheet.
///
/// This is a convenience function to show the sheet with proper styling.
Future<void> showInstructionInjectionSheet(
  BuildContext context, {
  required String? assistantId,
}) async {
  final cs = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return InstructionInjectionSheet(assistantId: assistantId);
    },
  );
}
