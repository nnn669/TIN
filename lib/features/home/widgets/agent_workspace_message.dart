import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';

/// The single message surface used by the conversation stream.
///
/// Chat messages are rendered as nodes in one agent workspace timeline rather
/// than as two opposing user/assistant bubbles. The child remains responsible
/// for message content and all existing actions.
class AgentWorkspaceMessage extends StatelessWidget {
  const AgentWorkspaceMessage({
    super.key,
    required this.role,
    required this.isLast,
    required this.child,
  });

  final String role;
  final bool isLast;
  final Widget child;

  bool get _isUser => role == 'user';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = _isUser ? colors.tertiary : colors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.25),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        _isUser ? Lucide.UserRound : Lucide.Sparkles,
                        size: 14,
                        color: colors.onPrimary,
                      ),
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 1,
                        margin: const EdgeInsets.only(top: 6),
                        color: colors.outlineVariant.withValues(alpha: 0.55),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.28 : 0.62,
                  ),
                  border: Border(
                    left: BorderSide(
                      color: accent.withValues(alpha: 0.45),
                      width: 2,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}