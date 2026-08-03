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
    raw = p.read_bytes()
    lines = raw.splitlines(keepends=True)
    p.write_bytes(b''.join(line for line in lines if not predicate(line.decode(errors='ignore'))))


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


def remove_dart_call(path, title):
    p = file(path)
    text = p.read_text()
    title_pos = text.find(title)
    if title_pos < 0:
        return
    start = text.rfind('test(', 0, title_pos)
    if start < 0:
        raise RuntimeError(f'{path}: test call start not found for {title!r}')
    depth = 0
    quote = None
    escaped = False
    for pos in range(start, len(text)):
        ch = text[pos]
        if quote:
            if escaped:
                escaped = False
            elif ch == '\\':
                escaped = True
            elif ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
        elif ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                end = pos + 1
                if end < len(text) and text[end] == ';':
                    end += 1
                p.write_text(text[:start] + text[end:])
                return
    raise RuntimeError(f'{path}: unmatched test call for {title!r}')


# Break the removed remote provider out of the application graph.
replace_once('lib/main.dart', "import 'core/providers/s3_backup_provider.dart';\n", '')
remove_regex(
    'lib/main.dart',
    r"\n        ChangeNotifierProvider\(\n          create: \(ctx\) => S3BackupProvider\(.*?\n        \),",
    expected=1,
)
remove_lines('lib/main.dart', lambda line: 'initialConfig: ctx.read<SettingsProvider>().webDavConfig' in line)
remove_lines('lib/main.dart', lambda line: 'initialConfig: ctx.read<SettingsProvider>().s3Config' in line)

# Remove old remote backup persistence and load-time reads, retaining WebDavConfig
# in the model because DataSync uses it as the local ZIP include-options carrier.
remove_lines('lib/core/providers/settings_provider.dart', lambda line: "import '../models/backup.dart';" in line)
remove_lines('lib/core/providers/settings_provider.dart', lambda line: '_webDavConfigKey' in line or '_s3ConfigKey' in line)
remove_regex(
    'lib/core/providers/settings_provider.dart',
    r"\n    // webdav config.*?\n    if \(_providerConfigs\.isEmpty\)",
    '\n    if (_providerConfigs.isEmpty)',
)
remove_method('lib/core/providers/settings_provider.dart', '  WebDavConfig _webDavConfig')
remove_method('lib/core/providers/settings_provider.dart', '  Future setWebDavConfig(')
remove_method('lib/core/providers/settings_provider.dart', '  S3Config _s3Config')
remove_method('lib/core/providers/settings_provider.dart', '  Future setS3Config(')
remove_lines(
    'lib/core/providers/settings_provider.dart',
    lambda line: any(token in line for token in ('webDavConfig', 'setWebDavConfig', 's3Config', 'setS3Config')),
)

# Remove any remaining assistant-level temperature update lines while preserving CRLF files.
remove_lines(
    'lib/features/assistant/pages/assistant_settings_edit_page.dart',
    lambda line: 'clearTemperature' in line or 'a.temperature' in line,
)

# Remove the obsolete sponsor page and its only settings entry point.
replace_once('lib/features/settings/pages/settings_page.dart', "import 'sponsor_page.dart';\n", '')
remove_regex(
    'lib/features/settings/pages/settings_page.dart',
    r"\n              _iosNavRow\(\n                context,\n                icon: Lucide\.Heart,\n                label: l10n\.settingsPageSponsor,.*?\n              \),",
    '',
    expected=1,
)
(root / 'lib/features/settings/pages/sponsor_page.dart').unlink()

# Keep desktop backup navigation for local ZIP and third-party imports only.
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
''')

for path in ('test/core/services/backup/s3_bucket_list_fallback_test.dart', 'test/features/backup/backup_page_settings_navigation_test.dart'):
    p = root / path
    if p.exists():
        p.unlink()
remove_dart_call('test/core/services/backup/data_sync_backup_file_test.dart', 'cleans temporary restore files when WebDAV restore fails')

needles = (
    'S3BackupProvider', 'S3Config', 's3Config', 'setS3Config', 'webDavConfig', 'setWebDavConfig',
    'testWebdav', 'backupToWebDav', 'listBackupFiles', 'restoreFromWebDav', 'deleteWebDavBackupFile',
    'assistant?.temperature', 'a.temperature', 'clearTemperature', 'temperature: assistant', 'SponsorPage',
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