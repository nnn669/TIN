import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../model/pages/default_model_page.dart';
import '../../provider/pages/providers_page.dart';
import 'display_settings_page.dart';
import '../../mcp/pages/mcp_page.dart';
import '../../assistant/pages/assistant_settings_page.dart';
import 'about_page.dart';
import 'tts_services_page.dart';
import 'log_viewer_page.dart';
import '../../search/pages/search_services_page.dart';
import '../../backup/pages/backup_page.dart';
import '../../quick_phrase/pages/quick_phrases_page.dart';
import '../../instruction_injection/pages/instruction_injection_page.dart';
import 'network_proxy_page.dart';
import 'storage_space_page.dart';
import '../../../core/services/storage/storage_usage_service.dart';
import '../../../core/services/haptics.dart';
import 'package:tin/theme/app_font_weights.dart';
import '../../home/widgets/chat_fluid_motion_controller.dart';

enum _ThemeModeChoice { system, light, dark, fluid }

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();

    String modeLabel(ThemeMode m) {
      switch (m) {
        case ThemeMode.dark:
          return l10n.settingsPageDarkMode;
        case ThemeMode.light:
          return l10n.settingsPageLightMode;
        case ThemeMode.system:
          return l10n.settingsPageSystemMode;
      }
    }

    String fluidModeLabel() =>
        Localizations.localeOf(context).languageCode == 'zh'
        ? '流体动效'
        : 'Fluid motion';

    Future<void> pickThemeMode() async {
      final settingsProvider = context.read<SettingsProvider>();
      final selected = await showModalBottomSheet<_ThemeModeChoice>(
        context: context,
        backgroundColor: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sheetOption(
                    ctx,
                    icon: Lucide.Monitor,
                    label: modeLabel(ThemeMode.system),
                    onTap: () => Navigator.of(ctx).pop(_ThemeModeChoice.system),
                  ),
                  _sheetDivider(ctx),
                  _sheetOption(
                    ctx,
                    icon: Lucide.Sun,
                    label: modeLabel(ThemeMode.light),
                    onTap: () => Navigator.of(ctx).pop(_ThemeModeChoice.light),
                  ),
                  _sheetDivider(ctx),
                  _sheetOption(
                    ctx,
                    icon: Lucide.Moon,
                    label: modeLabel(ThemeMode.dark),
                    onTap: () => Navigator.of(ctx).pop(_ThemeModeChoice.dark),
                  ),
                  _sheetDivider(ctx),
                  _sheetOption(
                    ctx,
                    icon: Lucide.AudioWaveform,
                    label: fluidModeLabel(),
                    onTap: () => Navigator.of(ctx).pop(_ThemeModeChoice.fluid),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (selected == null) return;
      final fluidEnabled = selected == _ThemeModeChoice.fluid;
      await ChatFluidMotionController.instance.setEnabled(fluidEnabled);
      if (!fluidEnabled) {
        final mode = switch (selected) {
          _ThemeModeChoice.system => ThemeMode.system,
          _ThemeModeChoice.light => ThemeMode.light,
          _ThemeModeChoice.dark => ThemeMode.dark,
          _ThemeModeChoice.fluid => settingsProvider.themeMode,
        };
        await settingsProvider.setThemeMode(mode);
      }
    }

    Widget header(String text, {bool first = false}) => Padding(
      padding: EdgeInsets.fromLTRB(12, first ? 2 : 12, 12, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: AppFontWeights.semibold,
          color: cs.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.settingsPageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          if (!settings.hasAnyActiveModel)
            Material(
              color: cs.errorContainer.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Lucide.MessageCircleWarning,
                      size: 18,
                      color: cs.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.settingsPageWarningMessage,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          header(l10n.settingsPageGeneralSection, first: true),
          _iosSectionCard(
            children: [
              _iosNavRow(
                context,
                icon: Lucide.SunMoon,
                label: l10n.settingsPageColorMode,
                detailText: ChatFluidMotionController.instance.enabled
                    ? fluidModeLabel()
                    : modeLabel(settings.themeMode),
                onTap: pickThemeMode,
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Monitor,
                label: l10n.settingsPageDisplay,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DisplaySettingsPage(),
                    ),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Bot,
                label: l10n.settingsPageAssistant,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AssistantSettingsPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          header(l10n.settingsPageModelsServicesSection),
          _iosSectionCard(
            children: [
              _iosNavRow(
                context,
                icon: Lucide.Heart,
                label: l10n.settingsPageDefaultModel,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DefaultModelPage()),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Boxes,
                label: l10n.settingsPageProviders,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProvidersPage()),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Earth,
                label: l10n.settingsPageSearch,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SearchServicesPage(),
                    ),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Volume2,
                label: l10n.settingsPageTts,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TtsServicesPage()),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Terminal,
                label: l10n.settingsPageMcp,
                onTap: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const McpPage()));
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Zap,
                label: l10n.settingsPageQuickPhrase,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const QuickPhrasesPage(),
                    ),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.Layers,
                label: l10n.settingsPageInstructionInjection,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const InstructionInjectionPage(),
                    ),
                  );
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.EthernetPort,
                label: l10n.settingsPageNetworkProxy,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NetworkProxyPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          header(l10n.settingsPageDataSection),
          _iosSectionCard(
            children: [
              _iosNavRow(
                context,
                icon: Lucide.Database,
                label: l10n.settingsPageBackup,
                onTap: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const BackupPage()));
                },
              ),
              _iosDivider(context),
              _iosNavRow(
                context,
                icon: Lucide.HardDrive,
                label: l10n.settingsPageChatStorage,
                detailBuilder: (_) => const _ChatStorageSummary(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StorageSpacePage()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          header(l10n.settingsPageAboutSection),
          _iosSectionCard(
            children: [
              _iosNavRow(
                context,
                icon: Lucide.BadgeInfo,
                label: l10n.settingsPageAbout,
                onTap: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const AboutPage()));
                },
              ),
              if (settings.requestLogEnabled || settings.flutterLogEnabled) ...[
                _iosDivider(context),
                _iosNavRow(
                  context,
                  icon: Lucide.FileText,
                  label: l10n.settingsPageLogs,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LogViewerPage()),
                    );
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

Widget _iosSectionCard({required List<Widget> children}) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final Color bg = isDark
          ? Colors.white10
          : Colors.white.withValues(alpha: 0.96);
      return Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
            width: 0.6,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: children),
        ),
      );
    },
  );
}

Widget _iosDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 6,
    thickness: 0.6,
    indent: 54,
    endIndent: 12,
    color: cs.outlineVariant.withValues(alpha: 0.18),
  );
}

class _AnimatedPressColor extends StatelessWidget {
  const _AnimatedPressColor({
    required this.pressed,
    required this.base,
    required this.builder,
  });
  final bool pressed;
  final Color base;
  final Widget Function(Color color) builder;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final target = pressed
        ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base)
        : base;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, color, _) => builder(color ?? base),
    );
  }
}

class _ChatStorageSummary extends StatefulWidget {
  const _ChatStorageSummary();

  @override
  State<_ChatStorageSummary> createState() => _ChatStorageSummaryState();
}

class _ChatStorageSummaryState extends State<_ChatStorageSummary> {
  late Future<StorageUsageReport> _future;

  @override
  void initState() {
    super.initState();
    _future = StorageUsageService.computeReport();
  }

  String _fmtBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(
      color: cs.onSurface.withValues(alpha: 0.6),
      fontSize: 13,
    );

    return FutureBuilder<StorageUsageReport>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) {
          return Text(l10n.settingsPageCalculating, style: style);
        }
        final count = data?.totalFiles ?? 0;
        final size = _fmtBytes(data?.totalBytes ?? 0);
        return Text(l10n.settingsPageFilesCount(count, size), style: style);
      },
    );
  }
}

Widget _iosNavRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  VoidCallback? onTap,
  String? detailText,
  Widget Function(BuildContext ctx)? detailBuilder,
}) {
  final cs = Theme.of(context).colorScheme;
  final interactive = onTap != null;
  return _TactileRow(
    onTap: onTap,
    pressedScale: 1.00,
    haptics: false,
    builder: (pressed) {
      final baseColor = cs.onSurface.withValues(alpha: 0.9);
      return _AnimatedPressColor(
        pressed: pressed,
        base: baseColor,
        builder: (c) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                SizedBox(width: 36, child: Icon(icon, size: 20, color: c)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      color: c,
                      fontWeight: AppFontWeights.medium,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (detailBuilder != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                      child: detailBuilder(context),
                    ),
                  )
                else if (detailText != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      detailText,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                if (interactive)
                  Icon(
                    Lucide.ChevronRight,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: 0.42),
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _sheetDivider(BuildContext context) => Divider(
  height: 1,
  thickness: 0.6,
  indent: 56,
  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.25),
);

Widget _sheetOption(
  BuildContext context, {
  required IconData icon,
  required String label,
  required VoidCallback onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  return _TactileRow(
    onTap: onTap,
    pressedScale: 0.99,
    haptics: false,
    builder: (pressed) {
      final bg = pressed
          ? cs.onSurface.withValues(alpha: 0.08)
          : Colors.transparent;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            SizedBox(width: 28, child: Icon(icon, size: 21, color: cs.onSurface)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  color: cs.onSurface,
                  fontWeight: AppFontWeights.medium,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _TactileRow extends StatefulWidget {
  const _TactileRow({
    required this.onTap,
    required this.pressedScale,
    required this.haptics,
    required this.builder,
  });

  final VoidCallback? onTap;
  final double pressedScale;
  final bool haptics;
  final Widget Function(bool pressed) builder;

  @override
  State<_TactileRow> createState() => _TactileRowState();
}

class _TactileRowState extends State<_TactileRow> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTap: enabled
          ? () {
              if (widget.haptics) Haptics.light();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.builder(_pressed),
      ),
    );
  }
}

class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;

  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Haptics.light();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Icon(widget.icon, color: widget.color, size: widget.size),
      ),
    );
  }
}