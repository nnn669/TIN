from pathlib import Path
import re

root = Path('.')


def file(path):
    p = root / path
    if not p.exists():
        raise RuntimeError(f'missing file: {path}')
    return p


def replace_once(path, old, new):
    p = file(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected one match, got {count}: {old[:100]!r}')
    p.write_text(text.replace(old, new, 1))


def remove_lines(path, predicate):
    p = file(path)
    lines = p.read_text().splitlines(keepends=True)
    kept = [line for line in lines if not predicate(line)]
    p.write_text(''.join(kept))


def remove_regex(path, pattern, replacement='', expected=None):
    p = file(path)
    text = p.read_text()
    updated, count = re.subn(pattern, replacement, text, count=0, flags=re.S)
    if expected is not None and count != expected:
        raise RuntimeError(f'{path}: expected {expected} regex matches, got {count}: {pattern[:120]!r}')
    p.write_text(updated)


def remove_method(path, marker):
    p = file(path)
    lines = p.read_text().splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if marker in line]
    if not starts:
        return
    if len(starts) != 1:
        raise RuntimeError(f'{path}: duplicate method marker {marker!r}')
    start = starts[0]
    depth = 0
    seen_brace = False
    for end in range(start, len(lines)):
        line = lines[end]
        depth += line.count('{') - line.count('}')
        seen_brace |= '{' in line
        if seen_brace and depth == 0:
            del lines[start:end + 1]
            p.write_text(''.join(lines))
            return
    raise RuntimeError(f'{path}: unmatched braces for {marker!r}')


# Break the removed remote providers out of the application graph.
replace_once('lib/main.dart', "import 'core/providers/s3_backup_provider.dart';\n", '')
remove_regex(
    'lib/main.dart',
    r"\n        ChangeNotifierProvider\(\n          create: \(ctx\) => S3BackupProvider\(.*?\n        \),",
    expected=1,
)
remove_lines('lib/main.dart', lambda line: 'initialConfig: ctx.read<SettingsProvider>().webDavConfig' in line)
remove_lines('lib/main.dart', lambda line: 'initialConfig: ctx.read<SettingsProvider>().s3Config' in line)

# Remove the old backup settings persistence and all of its load-time references.
remove_lines('lib/core/providers/settings_provider.dart', lambda line: "import '../models/backup.dart';" in line)
remove_lines('lib/core/providers/settings_provider.dart', lambda line: '_webDavConfigKey' in line or '_s3ConfigKey' in line)
remove_regex(
    'lib/core/providers/settings_provider.dart',
    r"\n    // webdav config.*?\n    if \(_providerConfigs\.isEmpty\)",
    '\n    if (_providerConfigs.isEmpty)',
)
remove_method('lib/core/providers/settings_provider.dart', '  WebDavConfig _webDavConfig')
remove_method('lib/core/providers/settings_provider.dart', '  Future<void> setWebDavConfig(')
remove_method('lib/core/providers/settings_provider.dart', '  S3Config _s3Config')
remove_method('lib/core/providers/settings_provider.dart', '  Future<void> setS3Config(')
remove_lines(
    'lib/core/providers/settings_provider.dart',
    lambda line: any(
        token in line
        for token in ('webDavConfig', 'setWebDavConfig', 's3Config', 'setS3Config')
    ),
)

# The assistant model no longer exposes an assistant-level temperature.
remove_lines(
    'lib/features/assistant/pages/assistant_settings_edit_page.dart',
    lambda line: 'clearTemperature' in line or 'a.temperature' in line,
)

# Keep desktop backup navigation, but only for local files and third-party imports.
file('lib/desktop/setting/backup_pane.dart').write_text(r'''import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(RestoreMode.merge),
            child: Text(l10n.backupPageMergeMode),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(RestoreMode.overwrite),
            child: Text(l10n.backupPageOverwriteMode),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<BackupProvider>();
    final file = await provider.exportToFile();
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
        if (context.mounted) {
          await context.read<BackupReminderProvider>().recordBackupCompleted();
        }
      }
    } finally {
      await DataSync.cleanupTemporaryBackupFile(file);
    }
  }

  Future<void> _importLocal(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;
    final mode = await _chooseMode(context);
    if (mode == null || !context.mounted) return;
    await context.read<BackupProvider>().restoreFromLocalFile(
      File(path),
      mode: mode,
    );
    if (context.mounted) PlatformUtils.restartApp();
  }

  Future<void> _importCherry(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'bak'],
    );
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;
    final mode = await _chooseMode(context);
    if (mode == null || !context.mounted) return;
    await CherryImporter.importFromCherryStudio(
      file: File(path),
      mode: mode,
      settings: context.read<SettingsProvider>(),
      chatService: context.read<ChatService>(),
    );
    if (context.mounted) PlatformUtils.restartApp();
  }

  Future<void> _importChatbox(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;
    final mode = await _chooseMode(context);
    if (mode == null || !context.mounted) return;
    await ChatboxImporter.importFromChatbox(
      file: File(path),
      mode: mode,
      settings: context.read<SettingsProvider>(),
      chatService: context.read<ChatService>(),
    );
    if (context.mounted) PlatformUtils.restartApp();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<BackupProvider>();
    final reminder = context.watch<BackupReminderProvider>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.backupPageTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SwitchListTile(
          title: Text(l10n.backupReminderEnableTitle),
          value: reminder.enabled,
          onChanged: (value) => reminder.setEnabled(value),
        ),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: Text(l10n.backupPageExportToFile),
          enabled: !provider.busy,
          onTap: () => _export(context),
        ),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: Text(l10n.backupPageImportBackupFile),
          enabled: !provider.busy,
          onTap: () => _importLocal(context),
        ),
        ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: Text(l10n.backupPageImportFromCherryStudio),
          enabled: !provider.busy,
          onTap: () => _importCherry(context),
        ),
        ListTile(
          leading: const Icon(Icons.data_object_outlined),
          title: Text(l10n.backupPageImportFromChatbox),
          enabled: !provider.busy,
          onTap: () => _importChatbox(context),
        ),
      ],
    );
  }
}
''')

# Remove tests for deleted remote functionality, and keep local DataSync coverage.
for path in (
    'test/core/services/backup/s3_bucket_list_fallback_test.dart',
    'test/features/backup/backup_page_settings_navigation_test.dart',
):
    p = root / path
    if p.exists():
        p.unlink()

remove_regex(
    'test/core/services/backup/data_sync_backup_file_test.dart',
    r"\n    test\(\n      'cleans temporary restore files when WebDAV restore fails',.*?\n    \);\n  \}\);\n\}",
    '\n  });\n}\n',
    expected=1,
)

# Final source-level guard. These names must not remain in executable code/tests.
needles = (
    'S3BackupProvider', 'S3Config', 's3Config', 'setS3Config',
    'webDavConfig', 'setWebDavConfig', 'testWebdav', 'backupToWebDav',
    'listBackupFiles', 'restoreFromWebDav', 'deleteWebDavBackupFile',
    'assistant?.temperature', 'a.temperature', 'clearTemperature',
    'temperature: assistant',
)
stale = []
for p in list((root / 'lib').rglob('*.dart')) + list((root / 'test').rglob('*.dart')):
    text = p.read_text()
    for needle in needles:
        if needle in text:
            stale.append(f'{p}:{needle}')
if stale:
    raise RuntimeError('stale references found:\n' + '\n'.join(stale))
print('feature removal continuation completed')
'''} lyst?]} 彩神争霸的},