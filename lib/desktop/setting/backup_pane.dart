import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/backup.dart';
import '../../core/providers/backup_provider.dart';
import '../../core/providers/backup_reminder_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/backup/cherry_importer.dart';
import '../../core/services/backup/chatbox_importer.dart';
import '../../core/services/backup/data_sync.dart';
import '../../core/services/chat/chat_service.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/platform_utils.dart';

class DesktopBackupPane extends StatelessWidget {
  const DesktopBackupPane({super.key});

  Future<RestoreMode?> _chooseMode(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<RestoreMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.backupPageSelectImportMode),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(RestoreMode.merge), child: Text(l10n.backupPageMergeMode)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(RestoreMode.overwrite), child: Text(l10n.backupPageOverwriteMode)),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final file = await context.read<BackupProvider>().exportToFile();
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: l10n.backupPageExportToFile,
        fileName: file.uri.pathSegments.last,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (path != null) {
        await File(path).parent.create(recursive: true);
        await file.copy(path);
        if (context.mounted) await context.read<BackupReminderProvider>().recordBackupCompleted();
      }
    } finally {
      await DataSync.cleanupTemporaryBackupFile(file);
    }
  }

  Future<void> _importLocal(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['zip']);
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;
    final mode = await _chooseMode(context);
    if (mode == null || !context.mounted) return;
    await context.read<BackupProvider>().restoreFromLocalFile(File(path), mode: mode);
    if (context.mounted) PlatformUtils.restartApp();
  }

  Future<void> _importCherry(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['zip', 'bak']);
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;
    final mode = await _chooseMode(context);
    if (mode == null || !context.mounted) return;
    await CherryImporter.importFromCherryStudio(file: File(path), mode: mode, settings: context.read<SettingsProvider>(), chatService: context.read<ChatService>());
    if (context.mounted) PlatformUtils.restartApp();
  }

  Future<void> _importChatbox(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['json']);
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;
    final mode = await _chooseMode(context);
    if (mode == null || !context.mounted) return;
    await ChatboxImporter.importFromChatbox(file: File(path), mode: mode, settings: context.read<SettingsProvider>(), chatService: context.read<ChatService>());
    if (context.mounted) PlatformUtils.restartApp();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final backup = context.watch<BackupProvider>();
    final reminder = context.watch<BackupReminderProvider>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.backupPageTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SwitchListTile(title: Text(l10n.backupReminderEnableTitle), value: reminder.enabled, onChanged: reminder.setEnabled),
        ListTile(leading: const Icon(Icons.file_upload_outlined), title: Text(l10n.backupPageExportToFile), enabled: !backup.busy, onTap: () => _export(context)),
        ListTile(leading: const Icon(Icons.file_download_outlined), title: Text(l10n.backupPageImportBackupFile), enabled: !backup.busy, onTap: () => _importLocal(context)),
        ListTile(leading: const Icon(Icons.archive_outlined), title: Text(l10n.backupPageImportFromCherryStudio), enabled: !backup.busy, onTap: () => _importCherry(context)),
        ListTile(leading: const Icon(Icons.data_object_outlined), title: Text(l10n.backupPageImportFromChatbox), enabled: !backup.busy, onTap: () => _importChatbox(context)),
      ],
    );
  }
}