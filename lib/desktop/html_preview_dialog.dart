import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as winweb;
import 'package:path_provider/path_provider.dart';
import 'dart:io' as io;
import '../l10n/app_localizations.dart';
import '../icons/lucide_adapter.dart';
import '../shared/widgets/snackbar.dart';

Future<void> showHtmlPreviewDesktopDialog(BuildContext context, {required String html}) async {
  if (Platform.isLinux) {
    final l10n = AppLocalizations.of(context)!;
    showAppSnackBar(context, message: l10n.htmlPreviewNotSupportedOnLinux, type: NotificationType.warning);
    return;
  }
  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _HtmlPreviewDialog(html: html),
  );
}

class _HtmlPreviewDialog extends StatefulWidget {
  const _HtmlPreviewDialog({required this.html});
  final String html;

  @override
  State<_HtmlPreviewDialog> createState() => _HtmlPreviewDialogState();
}

class _HtmlPreviewDialogState extends State<_HtmlPreviewDialog> {
  // macOS uses webview_flutter; Windows uses webview_windows.
  WebViewController? _flutterCtrl;
  winweb.WebviewController? _winCtrl;
  String? _tempFilePath; // for Windows loadUrl
  bool _ready = false;
  bool _loadedOnce = false;
  bool? _lastDark;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (Platform.isWindows) {
      final c = winweb.WebviewController();
      await c.initialize();
      try { await c.setBackgroundColor(const Color(0x00000000)); } catch (_) {}
      _winCtrl = c;
      _ready = true;
      if (mounted) setState(() {});
    } else {
      final c = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted);
      _flutterCtrl = c;
      _ready = true;
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadWithTheme();
  }

  String _wrapWithTheme(String input, {required bool isDark}) {
    final hasHtmlTag = input.toLowerCase().contains('<html');
    final hasBodyTag = input.toLowerCase().contains('<body');
    if (hasHtmlTag && hasBodyTag) return input;
    final bg = isDark ? '#111111' : '#ffffff';
    final fg = isDark ? '#eaeaea' : '#222222';
    return '''<!doctype html><html><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width, initial-scale=1"/><style>html,body{background:${bg};color:${fg};margin:0;padding:0}.container{padding:12px}img,video,canvas,iframe{max-width:100%;height:auto}pre,code{font-family:ui-monospace, SFMono-Regular, Menlo, Consolas, \"Liberation Mono\", monospace;}</style></head><body><div class="container">${input}</div></body></html>''';
  }

  Future<String> _writeTempHtml(String html) async {
    final dir = await getTemporaryDirectory();
    final file = io.File('${dir.path}/html_preview_${DateTime.now().millisecondsSinceEpoch}.html');
    await file.writeAsString(html, flush: true);
    return file.path;
  }

  Future<void> _loadWithTheme() async {
    if (!_ready) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_loadedOnce && _lastDark == isDark) return; // no change
    _lastDark = isDark;
    final html = _wrapWithTheme(widget.html, isDark: isDark);
    if (Platform.isWindows) {
      final path = await _writeTempHtml(html);
      _tempFilePath = path;
      await _winCtrl?.loadUrl(Uri.file(path).toString());
    } else {
      await _flutterCtrl?.loadHtmlString(html);
    }
    _loadedOnce = true;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    // Keep content updated with theme changes
    WidgetsBinding.instance.addPostFrameCallback((_) { _loadWithTheme(); });
    return Dialog(
      elevation: 12,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 520, maxWidth: 900, maxHeight: 740),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: cs.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Text(l10n.assistantEditPreviewTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        tooltip: l10n.mcpPageClose,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(Lucide.X, size: 18, color: cs.onSurface.withOpacity(0.75)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Builder(
                        builder: (context) {
                          if (Platform.isWindows) {
                            final c = _winCtrl;
                            if (c == null) return const SizedBox.shrink();
                            return winweb.Webview(c);
                          }
                          final c = _flutterCtrl;
                          if (c == null) return const SizedBox.shrink();
                          return WebViewWidget(controller: c);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    try {
      _winCtrl?.dispose();
    } catch (_) {}
    super.dispose();
  }
}
