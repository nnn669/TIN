import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/app_directories.dart';

/// Mobile log viewer - shows list of log files and allows viewing/exporting
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  List<FileSystemEntity> _logFiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLogFiles();
  }

  Future<void> _loadLogFiles() async {
    setState(() => _loading = true);
    try {
      final dir = await AppDirectories.getAppDataDirectory();
      final logsDir = Directory('${dir.path}/logs');
      if (await logsDir.exists()) {
        final files = await logsDir
            .list()
            .where((e) => e is File && e.path.endsWith('.txt'))
            .toList();
        // Sort by modification time descending (newest first)
        files.sort((a, b) {
          final aStat = (a as File).statSync();
          final bStat = (b as File).statSync();
          return bStat.modified.compareTo(aStat.modified);
        });
        setState(() {
          _logFiles = files;
          _loading = false;
        });
      } else {
        setState(() {
          _logFiles = [];
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _logFiles = [];
        _loading = false;
      });
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Lucide.ArrowLeft, color: cs.onSurface, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l10n.logViewerTitle),
        actions: [
          IconButton(
            icon: Icon(Lucide.RefreshCw, color: cs.onSurface, size: 20),
            onPressed: _loadLogFiles,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logFiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Lucide.FileQuestion, size: 48, color: cs.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text(
                        l10n.logViewerEmpty,
                        style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _logFiles.length,
                  itemBuilder: (context, index) {
                    final file = _logFiles[index] as File;
                    final stat = file.statSync();
                    final fileName = file.path.split('/').last;
                    final isCurrentLog = fileName == 'logs.txt';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          isCurrentLog ? Lucide.FileText : Lucide.FileClock,
                          color: isCurrentLog ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
                        ),
                        title: Text(
                          isCurrentLog ? l10n.logViewerCurrentLog : fileName,
                          style: TextStyle(
                            fontWeight: isCurrentLog ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          '${_formatFileSize(stat.size)} · ${_formatDate(stat.modified)}',
                          style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
                        ),
                        trailing: Icon(Lucide.ChevronRight, color: cs.onSurface.withValues(alpha: 0.4)),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _LogContentPage(file: file),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

/// Page to view log file content with export option
class _LogContentPage extends StatefulWidget {
  const _LogContentPage({required this.file});
  final File file;

  @override
  State<_LogContentPage> createState() => _LogContentPageState();
}

class _LogContentPageState extends State<_LogContentPage> {
  String _content = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    setState(() => _loading = true);
    try {
      final content = await widget.file.readAsString();
      setState(() {
        _content = content;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _content = 'Error loading file: $e';
        _loading = false;
      });
    }
  }

  Future<void> _exportFile() async {
    try {
      await Share.shareXFiles(
        [XFile(widget.file.path)],
        subject: widget.file.path.split('/').last,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final fileName = widget.file.path.split('/').last;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Lucide.ArrowLeft, color: cs.onSurface, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(fileName == 'logs.txt' ? l10n.logViewerCurrentLog : fileName),
        actions: [
          IconButton(
            icon: Icon(Lucide.Share2, color: cs.onSurface, size: 20),
            tooltip: l10n.logViewerExport,
            onPressed: _exportFile,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _content.isEmpty
              ? Center(
                  child: Text(
                    l10n.logViewerEmpty,
                    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    _content,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.85),
                      height: 1.4,
                    ),
                  ),
                ),
    );
  }
}
