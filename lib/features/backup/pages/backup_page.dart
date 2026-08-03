import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/backup.dart';
import '../../../core/providers/backup_provider.dart';
import '../../../core/providers/backup_reminder_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/backup/cherry_importer.dart';
import '../../../core/services/backup/chatbox_importer.dart';
import '../../../core/services/backup/data_sync.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/native_file_save.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/loading_dialog_card.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../../utils/platform_utils.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  Future<RestoreMode?> _chooseMode(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.white10 : const Color(0xFFF7F7F9);

    return showDialog<RestoreMode>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.52),
      builder: (ctx) => Dialog(
        backgroundColor: cs.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(38)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(42, 38, 42, 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.backupPageSelectImportMode,
                  style: TextStyle(
                    fontSize: 29,
                    fontWeight: AppFontWeights.emphasis,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 34),
                Row(
                  children: [
                    Expanded(
                      child: _ImportModeButton(
                        title: l10n.backupPageMergeMode,
                        filled: false,
                        color: cardColor,
                        onTap: () => Navigator.of(ctx).pop(RestoreMode.merge),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _ImportModeButton(
                        title: l10n.backupPageOverwriteMode,
                        filled: true,
                        color: cs.primary,
                        onTap: () =>
                            Navigator.of(ctx).pop(RestoreMode.overwrite),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<T> _loading(
    BuildContext context,
    Future<T> Function() task, {
    String? label,
  }) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LoadingDialogCard(label: label),
    );
    try {
      return await task();
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _export(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    File? file;
    try {
      file = await _loading(
        context,
        () => context.read<BackupProvider>().exportToFile(),
        label: l10n.backupPageExporting,
      );
      if (!context.mounted) return;
      if (Platform.isAndroid || Platform.isIOS) {
        final saved = await NativeFileSave.saveFileFromPath(
          sourcePath: file.path,
          fileName: file.uri.pathSegments.last,
        );
        if (saved && context.mounted) {
          await context.read<BackupReminderProvider>().recordBackupCompleted();
        }
      } else {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: l10n.backupPageExportToFile,
          fileName: file.uri.pathSegments.last,
          type: FileType.custom,
          allowedExtensions: const ['zip'],
        );
        if (path != null) {
          await File(path).parent.create(recursive: true);
          await file.copy(path);
          if (context.mounted) {
            await context.read<BackupReminderProvider>().recordBackupCompleted();
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: e.toString(),
          type: NotificationType.error,
        );
      }
    } finally {
      if (file != null) {
        await DataSync.cleanupTemporaryBackupFile(file);
      }
    }
  }

  Future<void> _importLocal(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;

    final mode = await _chooseMode(context);
    if (mode == null || !context.mounted) return;

    try {
      await _loading(
        context,
        () => context.read<BackupProvider>().restoreFromLocalFile(
              File(path),
              mode: mode,
            ),
      );
      if (context.mounted) PlatformUtils.restartApp();
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: e.toString(),
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _importCherry(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'bak'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;

    final mode = await _chooseMode(context);
    if (mode == null || !context.mounted) return;

    try {
      final res = await _loading(
        context,
        () => CherryImporter.importFromCherryStudio(
          file: File(path),
          mode: mode,
          settings: context.read<SettingsProvider>(),
          chatService: context.read<ChatService>(),
        ),
      );
      if (context.mounted) {
        showAppSnackBar(
          context,
          message:
              '${l10nForBackup(context).backupPageImportFromCherryStudio}: '
              '${res.assistants}',
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: e.toString(),
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _importChatbox(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;

    final mode = await _chooseMode(context);
    if (mode == null || !context.mounted) return;

    try {
      final res = await _loading(
        context,
        () => ChatboxImporter.importFromChatbox(
          file: File(path),
          mode: mode,
          settings: context.read<SettingsProvider>(),
          chatService: context.read<ChatService>(),
        ),
      );
      if (context.mounted) {
        showAppSnackBar(
          context,
          message:
              '${l10nForBackup(context).backupPageImportFromChatbox}: '
              '${res.assistants}',
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: e.toString(),
          type: NotificationType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ChangeNotifierProvider(
      create: (_) => BackupProvider(chatService: context.read<ChatService>()),
      child: Builder(
        builder: (context) {
          final backup = context.watch<BackupProvider>();
          return Scaffold(
            appBar: AppBar(
              leading: Tooltip(
                message: l10n.settingsPageBackButton,
                child: _TactileIconButton(
                  icon: Lucide.ArrowLeft,
                  color: Theme.of(context).colorScheme.onSurface,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              title: Text(l10n.backupPageTitle),
              actions: const [SizedBox(width: 12)],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 32),
              children: [
                _BackupActionRow(
                  icon: Lucide.Export,
                  label: l10n.backupPageExportToFile,
                  enabled: !backup.busy,
                  onTap: () => _export(context),
                ),
                _BackupActionRow(
                  icon: Lucide.Import2,
                  label: l10n.backupPageImportBackupFile,
                  enabled: !backup.busy,
                  onTap: () => _importLocal(context),
                ),
                _BackupActionRow(
                  icon: Lucide.Box,
                  label: l10n.backupPageImportFromCherryStudio,
                  enabled: !backup.busy,
                  onTap: () => _importCherry(context),
                ),
                _BackupActionRow(
                  icon: Lucide.Code,
                  label: l10n.backupPageImportFromChatbox,
                  enabled: !backup.busy,
                  onTap: () => _importChatbox(context),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

AppLocalizations l10nForBackup(BuildContext context) =>
    AppLocalizations.of(context)!;

class _BackupActionRow extends StatelessWidget {
  const _BackupActionRow({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = cs.onSurface.withValues(alpha: enabled ? 0.92 : 0.38);
    return _TactileRow(
      onTap: enabled ? onTap : null,
      builder: (pressed) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Row(
            children: [
              SizedBox(
                width: 74,
                child: Icon(icon, size: 39, color: color),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: AppFontWeights.medium,
                    color: pressed ? color.withValues(alpha: 0.62) : color,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ImportModeButton extends StatelessWidget {
  const _ImportModeButton({
    required this.title,
    required this.filled,
    required this.color,
    required this.onTap,
  });

  final String title;
  final bool filled;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = filled ? cs.onPrimary : cs.primary;
    return _TactileRow(
      onTap: onTap,
      pressedScale: 0.98,
      builder: (pressed) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 19, horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled
                ? (pressed ? color.withValues(alpha: 0.84) : color)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(34),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 21,
              fontWeight: AppFontWeights.semibold,
              color: filled ? foreground : foreground.withValues(alpha: 0.92),
            ),
          ),
        );
      },
    );
  }
}

class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 22,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          widget.icon,
          size: widget.size,
          color: _pressed ? widget.color.withValues(alpha: 0.65) : widget.color,
        ),
      ),
    );
  }
}

class _TactileRow extends StatefulWidget {
  const _TactileRow({
    required this.builder,
    this.onTap,
    this.pressedScale = 1.0,
  });

  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  final double pressedScale;

  @override
  State<_TactileRow> createState() => _TactileRowState();
}

class _TactileRowState extends State<_TactileRow> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.builder(_pressed),
      ),
    );
  }
}