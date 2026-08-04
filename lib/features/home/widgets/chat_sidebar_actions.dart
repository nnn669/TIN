import 'package:flutter/material.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../settings/pages/settings_page.dart';
import '../../stats/pages/stats_page.dart';
import '../../translate/pages/translate_page.dart';

class ChatSidebarActions extends StatelessWidget {
  const ChatSidebarActions({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(top: false, child: Container(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface), child: Row(children: [
      const Spacer(),
      _ActionButton(icon: Lucide.ChartColumnBig, label: l10n.settingsPageStatistics, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatsPage()))),
      const SizedBox(width: 4),
      _ActionButton(icon: Lucide.Languages, label: l10n.desktopNavTranslateTooltip, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TranslatePage()))),
      const SizedBox(width: 4),
      _ActionButton(icon: Lucide.Settings, label: l10n.settingsPageTitle, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()))),
    ])));
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(width: 45, height: 45, child: Center(child: Tooltip(message: label, child: IosIconButton(icon: icon, size: 22, color: Theme.of(context).colorScheme.onSurface, padding: const EdgeInsets.all(10), semanticLabel: label, onTap: onTap))));
}
