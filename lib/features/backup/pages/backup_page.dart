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
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/loading_dialog_card.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../utils/platform_utils.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

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

  Future<T> _loading<T>(BuildContext context, Future<T> Function() task) async {
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const LoadingDialogCard());
    try {
      return await task();
    } finally {
      if (context.mounted && Navigator.canPop(context)) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _export(BuildContext context, BackupProvider vm) async {
    final l10n = AppLocalizations.of(context)!;
    final file = await _loading(context, vm.exportToFile);
    try {
      if (!context.mounted) return;
      if (Platform.isAndroid || Platform.isIOS) {
        final saved = await NativeFileSave.saveFileFromPath(sourcePath: file.path, fileName: file.uri.pathSegments.last);
        if (saved && context.mounted) await context.read<BackupReminderProvider>().recordBackupCompleted();
      } else {
        final path = await FilePicker.platform.saveFile(dialogTitle: l10n.backupPageExportToFile, fileName: file.uri.pathSegments.last, type: FileType.custom, allowedExtensions: const ['zip']);
        if (path != null) await file.copy(path);
      }
    } catch (e) {
      if (context.mounted) showAppSnackBar(context, message: e.toString(), type: NotificationType.error);
    } finally {
      await DataSync.cleanupTemporaryBackupFile(file);
    }
  }

  Future<void> _importLocal(BuildContext context, BackupProvider vm) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['zip']);
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;
    final mode = await _chooseMode(context);
    if (mode == null || !context.mounted) return;
    try {
      await _loading(context, () => vm.restoreFromLocalFile(File(path), mode: mode));
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context)!;
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: Text(l10n.backupPageRestartRequired), content: Text(l10n.backupPageRestartContent), actions: [TextButton(onPressed: () { Navigator.of(ctx).pop(); PlatformUtils.restartApp(); }, child: Text(l10n.backupPageOK))]));
    } catch (e) {
      if (context.mounted) showAppSnackBar(context, message: e.toString(), type: NotificationType.error);
    }
  }

  Future<void> _importCherry(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['zip', 'bak']);
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;
    final mode = await _chooseMode(context);
    if (mode == null || !context.mounted) return;
    try {
      final res = await _loading(context, () => CherryImporter.importFromCherryStudio(file: File(path), mode: mode, settings: context.read<SettingsProvider>(), chatService: context.read<ChatService>()));
      if (context.mounted) showAppSnackBar(context, message: '${AppLocalizations.of(context)!.backupPageImportFromCherryStudio}: ${res.assistants}', type: NotificationType.success);
    } catch (e) {
      if (context.mounted) showAppSnackBar(context, message: e.toString(), type: NotificationType.error);
    }
  }

  Future<void> _importChatbox(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['json']);
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;
    final mode = await _chooseMode(context);
    if (mode == null || !context.mounted) return;
    try {
      final res = await _loading(context, () => ChatboxImporter.importFromChatbox(file: File(path), mode: mode, settings: context.read<SettingsProvider>(), chatService: context.read<ChatService>()));
      if (context.mounted) showAppSnackBar(context, message: '${AppLocalizations.of(context)!.backupPageImportFromChatbox}: ${res.assistants}', type: NotificationType.success);
    } catch (e) {
      if (context.mounted) showAppSnackBar(context, message: e.toString(), type: NotificationType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ChangeNotifierProvider(
      create: (_) => BackupProvider(chatService: context.read<ChatService>()),
      child: Builder(builder: (context) {
        final vm = context.watch<BackupProvider>();
        return Scaffold(
appBar: AppBar(title: Text(l10n.backupPageTitle), leading: BackButton(onPressed: () => Navigator.of(context).maybePop())),
body: ListView(padding: const EdgeInsets.all(16), children: [
  ListTile(leading: const Icon(Icons.file_upload_outlined), title: Text(l10n.backupPageExportToFile), onTap: vm.busy ? null : () => _export(context, vm)),
  ListTile(leading: const Icon(Icons.file_download_outlined), title: Text(l10n.backupPageImportBackupFile), onTap: vm.busy ? null : () => _importLocal(context, vm)),
  ListTile(leading: const Icon(Icons.archive_outlined), title: Text(l10n.backupPageImportFromCherryStudio), onTap: vm.busy ? null : () => _importCherry(context)),
  ListTile(leading: const Icon(Icons.data_object_outlined), title: Text(l10n.backupPageImportFromChatbox), onTap: vm.busy ? null : () => _importChatbox(context)),
]),
        );
      }),
    );
  }
}
