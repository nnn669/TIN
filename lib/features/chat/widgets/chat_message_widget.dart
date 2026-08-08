import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../../../core/services/haptics.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:open_filex/open_filex.dart';
// import 'package:easy_image_viewer/easy_image_viewer.dart';
import 'dart:convert';
import '../../home/widgets/file_processing_indicator.dart';
import '../pages/image_viewer_page.dart';
import '../../../core/models/chat_message.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../icons/reasoning_icons.dart';
// import '../../../theme/design_tokens.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/providers/assistant_provider.dart';
import 'package:intl/intl.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../../utils/avatar_cache.dart';
import '../../../utils/assistant_regex.dart';
import '../../../core/models/assistant.dart';
import '../../../core/providers/tts_provider.dart';
import '../../../core/services/app_control/app_control_service.dart';
import '../../../shared/widgets/markdown_with_highlight.dart';
import '../../../shared/widgets/snackbar.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/model_provider.dart';
import '../../../core/models/assistant_regex.dart';
import '../../../shared/widgets/ios_checkbox.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../desktop/desktop_context_menu.dart';
import '../../../desktop/menu_anchor.dart';
import '../../../shared/widgets/emoji_text.dart';
import '../../home/services/ask_user_interaction_service.dart';
import '../../home/services/local_tools_service.dart';
import '../../home/services/tool_approval_service.dart';
import '../utils/model_match_helper.dart';
import '../utils/thinking_tag_parser.dart';
import 'citation_sources_sheet.dart';
import 'chat_suggestion_bubbles.dart';
import 'token_display_widget.dart';
import 'local_response_timer_badge.dart';
import '../../../theme/app_font_weights.dart';

final RegExp _urlSchemeRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:');

Uri? _tryNormalizeExternalUri(String raw) {
  var u = raw.trim();
  if (u.isEmpty) return null;

  // Handle JSON-ish values like `"example.com"` defensively.
  if ((u.startsWith('"') && u.endsWith('"')) ||
      (u.startsWith("'") && u.endsWith("'"))) {
    u = u.substring(1, u.length - 1).trim();
    if (u.isEmpty) return null;
  }

  if (u.startsWith('//')) {
    u = 'https:$u';
  } else if (!_urlSchemeRe.hasMatch(u)) {
    u = 'https://$u';
  }

  final uri = Uri.tryParse(u);
  if (uri == null) return null;
  if ((uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isEmpty) {
    return null;
  }
  return uri;
}

/// Extract image paths from tool result content.
/// Returns (cleanText, imagePaths). Supports local file paths and HTTP URLs.
(String, List<String>) _parseMcpImagePaths(String? content) {
  if (content == null || content.isEmpty) return ('', const []);

  final images = <String>[];
  final imgRe = RegExp(r'\[image:(.+?)\]');

  final cleanText = content.replaceAllMapped(imgRe, (m) {
    final path = m.group(1)!;
    // Filter invalid values
    if (path.isNotEmpty && path != 'generated') {
      images.add(path);
    }
    return '';
  });

  return (cleanText.trim(), images);
}

dynamic _redactSensitiveToolValue(dynamic value) {
  if (value is List) return value.map(_redactSensitiveToolValue).toList();
  if (value is! Map) return value;
  return value.map((key, entryValue) {
    final keyText = key.toString().toLowerCase();
    final sensitive =
        keyText.contains('key') ||
        keyText.contains('token') ||
        keyText.contains('secret') ||
        keyText.contains('password') ||
        keyText.contains('authorization') ||
        keyText.contains('cookie');
    return MapEntry(
      key.toString(),
      sensitive ? '***' : _redactSensitiveToolValue(entryValue),
    );
  });
}

Map<String, dynamic> _redactSensitiveToolArguments(Map<String, dynamic> args) {
  final redacted = _redactSensitiveToolValue(args);
  return redacted is Map<String, dynamic> ? redacted : args;
}

String _prettyToolArguments(Map<String, dynamic> args) {
  return const JsonEncoder.withIndent(
    '  ',
  ).convert(_redactSensitiveToolArguments(args));
}

String _toolArgumentsSummary(Map<String, dynamic> args) {
  if (args.isEmpty) return '';
  final redacted = _redactSensitiveToolArguments(args);
  final entries = redacted.entries.take(2).map((entry) {
    final value = entry.value?.toString() ?? '';
    final truncated = value.length > 40
        ? '${value.substring(0, 40)}...'
        : value;
    return '${entry.key}: $truncated';
  });
  final suffix = redacted.length > 2 ? ' ...' : '';
  return entries.join(', ') + suffix;
}

IconData _toolIconFor(String name, [Map<String, dynamic> args = const {}]) {
  final localIcon = _localToolIconFor(name, args);
  if (localIcon != null) return localIcon;
  switch (name) {
    case AppControlToolNames.appControl:
      return Lucide.Shield;
    case 'create_memory':
      return Lucide.bookHeart;
    case 'edit_memory':
      return Lucide.bookHeart;
    case 'delete_memory':
      return Lucide.bookDashed;
    case 'search_web':
      return Lucide.Earth;
    case 'builtin_search':
      return Lucide.Search;
    default:
      return Lucide.Wrench;
  }
}

IconData? _localToolIconFor(String name, Map<String, dynamic> args) {
  if (name == LocalToolNames.askUser) {
    return Lucide.MessageCircleQuestionMark;
  }
  return switch (name) {
    LocalToolNames.timeInfo => Lucide.clock,
    LocalToolNames.clipboard => switch ((args['action'] ?? '').toString()) {
      'read' => Lucide.ClipboardCheck,
      'write' => Lucide.ClipboardPen,
      _ => Lucide.Clipboard,
    },
    LocalToolNames.textToSpeech => Lucide.Volume2,
    LocalToolNames.calculate => Lucide.Calculator,
    _ => null,
  };
}

String? _localToolTitleFor(
  AppLocalizations l10n,
  String name,
  Map<String, dynamic> args,
) {
  if (name == LocalToolNames.askUser) {
    return _askUserToolTitleFor(l10n, args);
  }
  return switch (name) {
    LocalToolNames.timeInfo => l10n.assistantEditLocalToolTimeInfoTitle,
    LocalToolNames.clipboard => switch ((args['action'] ?? '').toString()) {
      'read' => l10n.chatMessageWidgetReadClipboard,
      'write' => l10n.chatMessageWidgetWriteClipboard,
      _ => l10n.assistantEditLocalToolClipboardTitle,
    },
    LocalToolNames.textToSpeech => l10n.chatMessageWidgetSpeakingTitle,
    LocalToolNames.calculate => l10n.assistantEditLocalToolCalculateTitle,
    _ => null,
  };
}

String _textToSpeechToolText(Map<String, dynamic> args) {
  return (args['text'] ?? '').toString().trim();
}

void _replayTextToSpeech(BuildContext context, String text) {
  final content = text.trim();
  if (content.isEmpty) return;

  final tts = context.read<TtsProvider>();
  if (!tts.isAvailable) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError('Text-to-speech is unavailable.'),
        library: 'Kelivo chat message tools',
        context: ErrorDescription('while replaying text-to-speech'),
      ),
    );
    return;
  }

  unawaited(
    tts.speak(content).catchError((Object error, StackTrace stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'Kelivo chat message tools',
          context: ErrorDescription('while replaying text-to-speech'),
        ),
      );
    }),
  );
}

Widget _buildTextToSpeechReplayRow(
  BuildContext context, {
  required String text,
  required Color textColor,
  required Color buttonColor,
  double fontSize = 12,
  int maxLines = 2,
}) {
  final l10n = AppLocalizations.of(context)!;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: fontSize, height: 1.4, color: textColor),
        ),
      ),
      const SizedBox(width: 8),
      Tooltip(
        message: l10n.ttsFloatingReplayTooltip,
        child: IosIconButton(
          size: 14,
          minSize: 30,
          padding: const EdgeInsets.all(6),
          color: buttonColor,
          semanticLabel: l10n.ttsFloatingReplayTooltip,
          builder: (color) => Icon(Lucide.RefreshCw, size: 14, color: color),
          onTap: () => _replayTextToSpeech(context, text),
        ),
      ),
    ],
  );
}

String _askUserToolTitleFor(AppLocalizations l10n, Map<String, dynamic> args) {
  final questions = AskUserInteractionService.normalizeQuestions(args);
  if (questions.isNotEmpty) {
    return l10n.askUserCardQuestionCount(questions.length);
  }
  return l10n.assistantEditLocalToolAskUserTitle;
}

String _toolTitleFor(
  BuildContext context,
  String name,
  Map<String, dynamic> args, {
  required bool isResult,
}) {
  final l10n = AppLocalizations.of(context)!;
  if (name == LocalToolNames.askUser) {
    return _askUserToolTitleFor(l10n, args);
  }
  final localToolTitle = _localToolTitleFor(l10n, name, args);
  if (localToolTitle != null) return localToolTitle;
  switch (name) {
    case AppControlToolNames.appControl:
      return '神经权能网关';
    case 'create_memory':
      return l10n.chatMessageWidgetCreateMemory;
    case 'edit_memory':
      return l10n.chatMessageWidgetEditMemory;
    case 'delete_memory':
      return l10n.chatMessageWidgetDeleteMemory;
    case 'search_web':
      final q = (args['query'] ?? '').toString();
      return l10n.chatMessageWidgetWebSearch(q);
    case 'builtin_search':
      return l10n.chatMessageWidgetBuiltinSearch;
    default:
      return isResult
          ? l10n.chatMessageWidgetToolResult(name)
          : l10n.chatMessageWidgetToolCall(name);
  }
}

ToolApprovalRequest? _pendingApprovalForToolPart(
  ToolApprovalService approvalService,
  ToolUIPart part,
) {
  if (part.id.isNotEmpty && approvalService.isPending(part.id)) {
    return approvalService.pendingRequests[part.id];
  }
  for (final request in approvalService.pendingRequests.values) {
    if (request.toolName == part.toolName) return request;
  }
  return null;
}

bool _toolPartNeedsStandaloneStep(
  ToolApprovalService approvalService,
  ToolUIPart part,
) {
  if (_pendingApprovalForToolPart(approvalService, part) != null) {
    return true;
  }
  // Interactive local tools and ask-user cards must remain visible so their
  // controls and results are immediately available instead of being hidden in
  // a collapsed generic tool group.
  if (part.toolName == LocalToolNames.askUser ||
      part.toolName == LocalToolNames.timeInfo ||
      part.toolName == LocalToolNames.clipboard ||
      part.toolName == LocalToolNames.textToSpeech ||
      part.toolName == LocalToolNames.calculate) {
    return true;
  }
  return false;
}

String _toolGroupTitle(BuildContext context, int count) {
  final isZh = Localizations.localeOf(context).languageCode == 'zh';
  if (isZh) return '工具调用 · $count 次';
  return count == 1 ? '1 tool call' : '$count tool calls';
}

String _toolGroupPreview(BuildContext context, List<ToolUIPart> parts) {
  if (parts.isEmpty) return '';
  final names = <String>[];
  for (final part in parts) {
    final title = _toolTitleFor(
      context,
      part.toolName,
      part.arguments,
      isResult: !part.loading,
    );
    if (!names.contains(title)) names.add(title);
    if (names.length == 3) break;
  }
  final isZh = Localizations.localeOf(context).languageCode == 'zh';
  final remaining = parts.length - names.length;
  if (remaining <= 0) return names.join(' · ');
  return isZh
      ? '${names.join(' · ')} · 另 $remaining 个'
      : '${names.join(' · ')} · $remaining more';
}

String _prettyToolJson(String raw) {
  try {
    final obj = jsonDecode(raw);
    return const JsonEncoder.withIndent('  ').convert(obj);
  } catch (_) {
    return raw;
  }
}

Widget _buildToolImageFromPath(
  BuildContext context,
  String path, {
  double? height,
  BoxFit fit = BoxFit.contain,
}) {
  final cs = Theme.of(context).colorScheme;
  Widget errorWidget() => Container(
    width: height != null ? height * 0.67 : 120,
    height: height ?? 180,
    color: cs.surfaceContainerHighest,
    child: Icon(
      Lucide.ImageOff,
      size: 24,
      color: cs.onSurface.withValues(alpha: 0.5),
    ),
  );

  if (path.startsWith('http://') || path.startsWith('https://')) {
    return Image.network(
      path,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => errorWidget(),
    );
  }

  return Image.file(
    File(path),
    height: height,
    fit: fit,
    errorBuilder: (_, __, ___) => errorWidget(),
  );
}

void _showToolFullImage(BuildContext context, String path) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      pageBuilder: (_, __, ___) => ImageViewerPage(images: [path]),
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      transitionsBuilder: (context, anim, sec, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

void _showToolDetail(BuildContext context, ToolUIPart part) {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final argsPretty = _prettyToolArguments(part.arguments);
  final (cleanText, images) = _parseMcpImagePaths(part.content);
  final resultText = cleanText.isNotEmpty
      ? _prettyToolJson(cleanText)
      : l10n.chatMessageWidgetNoResultYet;

  final bool isDesktop =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  if (isDesktop) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          elevation: 12,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 360,
              maxWidth: 560,
              maxHeight: 560,
            ),
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
                          Icon(
                            _toolIconFor(part.toolName, part.arguments),
                            size: 18,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _toolTitleFor(
                                context,
                                part.toolName,
                                part.arguments,
                                isResult: !part.loading,
                              ),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: AppFontWeights.emphasis,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Tooltip(
                            message: l10n.mcpPageClose,
                            child: IconButton(
                              icon: Icon(
                                Lucide.X,
                                size: 18,
                                color: cs.onSurface.withValues(alpha: 0.75),
                              ),
                              onPressed: () => Navigator.of(ctx).maybePop(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.chatMessageWidgetArguments,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white10
                                      : const Color(0xFFF7F7F9),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: cs.outlineVariant.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                                child: SelectableText(
                                  argsPretty,
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l10n.chatMessageWidgetResult,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white10
                                      : const Color(0xFFF7F7F9),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: cs.outlineVariant.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                                child: SelectableText(
                                  resultText,
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              if (images.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  l10n.chatMessageWidgetImages,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: images.map((path) {
                                    return GestureDetector(
                                      onTap: () =>
                                          _showToolFullImage(context, path),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: _buildToolImageFromPath(
                                          context,
                                          path,
                                          height: 280,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
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
      },
    );
    return;
  }

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
      return SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.6,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _toolIconFor(part.toolName, part.arguments),
                        size: 18,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _toolTitleFor(
                            context,
                            part.toolName,
                            part.arguments,
                            isResult: !part.loading,
                          ),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: AppFontWeights.emphasis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.chatMessageWidgetArguments,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white10
                          : const Color(0xFFF7F7F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.2),
                      ),
                    ),
                    child: SelectableText(
                      argsPretty,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.chatMessageWidgetResult,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white10
                          : const Color(0xFFF7F7F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.2),
                      ),
                    ),
                    child: SelectableText(
                      resultText,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  if (images.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.chatMessageWidgetImages,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 220,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: images.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (ctx, i) {
                          final path = images[i];
                          return GestureDetector(
                            onTap: () => _showToolFullImage(context, path),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _buildToolImageFromPath(
                                context,
                                path,
                                height: 220,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ChatMessageWidget extends StatefulWidget {
  final ChatMessage message;
  final Widget? modelIcon;
  final bool showModelIcon;
  // Assistant identity override
  final bool useAssistantAvatar;
  final bool useAssistantName;
  final String? assistantName;
  final String? assistantAvatar; // path/url/emoji; null => use initial
  final bool showUserAvatar;
  final bool showTokenStats;
  final VoidCallback? onRegenerate;
  final VoidCallback? onResend;
  final VoidCallback? onCopy;
  final VoidCallback? onTranslate;
  final VoidCallback? onSpeak;
  final VoidCallback? onMore;
  final VoidCallback? onEdit; // user: edit
  final VoidCallback? onDelete; // user: delete
  // Optional version switcher (branch) UI controls
  final int? versionIndex; // zero-based
  final int? versionCount;
  final VoidCallback? onPrevVersion;
  final VoidCallback? onNextVersion;
  // Optional reasoning UI props (for reasoning-capable models)
  final String? reasoningText;
  final bool reasoningExpanded;
  final bool reasoningLoading;
  final DateTime? reasoningStartAt;
  final DateTime? reasoningFinishedAt;
  final VoidCallback? onToggleReasoning;
  // For multiple reasoning segments
  final List<ReasoningSegment>? reasoningSegments;
  // Optional translation UI props
  final bool translationExpanded;
  final VoidCallback? onToggleTranslation;
  // MCP tool calls/results mixed-in cards
  final List<ToolUIPart>? toolParts;
  final List<int>? contentSplitOffsets;
  final List<int>? reasoningCountAtSplit;
  final List<int>? toolCountAtSplit;
  // Hide streaming dots when pinned globally
  final bool hideStreamingIndicator;
  // Whether files are currently being processed
  final bool isProcessingFiles;
  final bool enableStreamingTextMotion;
  final List<String> suggestions;
  final ValueChanged<String>? onSuggestionTap;
  final Future<void> Function(ToolUIPart part, AskUserResult result)?
  onRecoveredAskUserAnswer;

  const ChatMessageWidget({
    super.key,
    required this.message,
    this.modelIcon,
    this.showModelIcon = true,
    this.useAssistantAvatar = false,
    this.useAssistantName = false,
    this.assistantName,
    this.assistantAvatar,
    this.showUserAvatar = true,
    this.showTokenStats = true,
    this.onRegenerate,
    this.onResend,
    this.onCopy,
    this.onTranslate,
    this.onSpeak,
    this.onMore,
    this.onEdit,
    this.onDelete,
    this.versionIndex,
    this.versionCount,
    this.onPrevVersion,
    this.onNextVersion,
    this.reasoningText,
    this.reasoningExpanded = false,
    this.reasoningLoading = false,
    this.reasoningStartAt,
    this.reasoningFinishedAt,
    this.onToggleReasoning,
    this.reasoningSegments,
    this.translationExpanded = true,
    this.onToggleTranslation,
    this.toolParts,
    this.contentSplitOffsets,
    this.reasoningCountAtSplit,
    this.toolCountAtSplit,
    this.hideStreamingIndicator = false,
    this.isProcessingFiles = false,
    this.enableStreamingTextMotion = true,
    this.suggestions = const <String>[],
    this.onSuggestionTap,
    this.onRecoveredAskUserAnswer,
  });

  @override
  State<ChatMessageWidget> createState() => _ChatMessageWidgetState();
}

class _ChatMessageWidgetState extends State<ChatMessageWidget> {
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
  final ScrollController _reasoningScroll = ScrollController();
  bool _tickActive = false;
  // Local expand state for inline <think> card (defaults to expanded)
  bool? _inlineThinkExpanded;
  bool _inlineThinkManuallyToggled = false;
  // User message context menu state
  final GlobalKey _userBubbleKey = GlobalKey();
  OverlayEntry? _userMenuOverlay;
  // Desktop anchored menus for bottom action buttons
  final GlobalKey _moreBtnKey1 = GlobalKey();
  final GlobalKey _moreBtnKey2 = GlobalKey();
  final GlobalKey _translateBtnKey2 = GlobalKey();
  // ValueNotifier for reasoning animation tick - avoids full widget rebuild
  final ValueNotifier<int> _reasoningTick = ValueNotifier<int>(0);
  late final Ticker _ticker = Ticker((_) {
    if (mounted && _tickActive) {
      _reasoningTick.value++; // Only notify reasoning section, not full rebuild
    }
  });

  @override
  void initState() {
    super.initState();
    _syncTicker();

    // Determine initial state for inline <think> card BEFORE first paint to avoid
    // post-frame size changes that can cause list scroll jitter/snapping.
    try {
      final parsed = _legacyInlineThinkingFor(widget);
      final extracted = parsed.thinkingTexts.join('\n\n');
      final usingInlineThink =
          (widget.reasoningText == null || widget.reasoningText!.isEmpty) &&
          extracted.isNotEmpty;
      if (usingInlineThink && _inlineThinkExpanded == null) {
        final autoCollapse = context
            .read<SettingsProvider>()
            .autoCollapseThinking;
        _inlineThinkExpanded = !autoCollapse ? true : false;
      }
    } catch (_) {
      // If anything fails here, fall back to later update logic.
    }
  }

  @override
  void didUpdateWidget(covariant ChatMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
    // Auto-collapse when inline <think> transitions from loading -> finished
    _applyAutoCollapseInlineThinkIfFinished(oldWidget: oldWidget);
  }

  void _applyAutoCollapseInlineThinkIfFinished({ChatMessageWidget? oldWidget}) {
    if (!mounted) return;
    final newExtracted = _legacyInlineThinkingFor(
      widget,
    ).thinkingTexts.join('\n\n');
    final usingInlineThinkNew =
        (widget.reasoningText == null || widget.reasoningText!.isEmpty) &&
        newExtracted.isNotEmpty;

    bool usingInlineThinkOld = false;
    if (oldWidget != null) {
      final oldExtracted = _legacyInlineThinkingFor(
        oldWidget,
      ).thinkingTexts.join('\n\n');
      usingInlineThinkOld =
          (oldWidget.reasoningText == null ||
              oldWidget.reasoningText!.isEmpty) &&
          oldExtracted.isNotEmpty;
    }

    final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;

    // If finished now (not loading), inline think is used, and auto-collapse is on
    // Only collapse when user hasn't manually toggled; also if we don't yet have a chosen state.
    final finishedNow = usingInlineThinkNew;
    final justFinished = oldWidget != null
        ? (!usingInlineThinkOld && finishedNow)
        : finishedNow;

    if (autoCollapse && finishedNow && justFinished) {
      if (!_inlineThinkManuallyToggled || _inlineThinkExpanded == null) {
        if (mounted) setState(() => _inlineThinkExpanded = false);
        return;
      }
    }

    // On first mount where already finished and no user choice yet, honor autoCollapse
    if (oldWidget == null &&
        usingInlineThinkNew &&
        _inlineThinkExpanded == null) {
      if (autoCollapse) {
        if (mounted) setState(() => _inlineThinkExpanded = false);
      } else {
        if (mounted) setState(() => _inlineThinkExpanded = true);
      }
    }
  }

  void _syncTicker() {
    final loading =
        widget.reasoningLoading &&
        widget.reasoningStartAt != null &&
        widget.reasoningFinishedAt == null;
    _tickActive = loading;
    if (loading) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      if (_ticker.isActive) _ticker.stop();
    }
  }

  ThinkingTagParseResult _legacyInlineThinkingFor(ChatMessageWidget widget) {
    if ((widget.reasoningText?.isNotEmpty ?? false) ||
        widget.reasoningLoading ||
        (widget.reasoningSegments?.isNotEmpty ?? false)) {
      return ThinkingTagParseResult(
        visibleContent: widget.message.content,
        thinkingTexts: const <String>[],
      );
    }
    return ThinkingTagParser.parseLegacyInlineBlocks(widget.message.content);
  }

  String _assistantNameFallback() {
    try {
      final chat = context.read<ChatService>();
      final convo = chat.getConversation(widget.message.conversationId);
      final aId = convo?.assistantId;
      if (aId != null && aId.isNotEmpty) {
        final ap = context.read<AssistantProvider>();
        final a = ap.getById(aId);
        final name = a?.name.trim();
        if (name != null && name.isNotEmpty) return name;
      }
    } catch (_) {}
    return 'AI Assistant';
  }

  Assistant? _assistantForMessage() {
    try {
      final chat = context.read<ChatService>();
      final convo = chat.getConversation(widget.message.conversationId);
      final aId = convo?.assistantId;
      if (aId == null || aId.isEmpty) return null;
      final ap = context.watch<AssistantProvider>();
      return ap.getById(aId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _confirmRegeneration(VoidCallback action) async {
    final settings = context.read<SettingsProvider>();
    if (!settings.showRegenerateConfirmDialog) {
      action();
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final content = settings.regenerateDeleteTrailingMessages
        ? l10n.chatMessageWidgetRegenerateConfirmDeleteTrailingContent
        : l10n.chatMessageWidgetRegenerateConfirmContent;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: Theme.of(dctx).colorScheme.surface,
        title: Text(l10n.chatMessageWidgetRegenerateConfirmTitle),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(l10n.chatMessageWidgetRegenerateConfirmCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(l10n.chatMessageWidgetRegenerateConfirmOk),
          ),
        ],
      ),
    );
    if (ok == true && mounted) action();
  }

  String _resolveModelDisplayName(SettingsProvider settings) {
    final modelId = widget.message.modelId;
    if (modelId == null || modelId.trim().isEmpty) {
      // Model metadata can be missing for legacy/preset messages.
      return AppLocalizations.of(context)?.messageExportSheetAssistant ??
          'Assistant';
    }

    final providerId = widget.message.providerId;
    String baseId = modelId;
    String? providerName;
    if (providerId != null && providerId.isNotEmpty) {
      try {
        final cfg = settings.getProviderConfig(providerId);
        providerName = cfg.name.trim();
        final ov = cfg.modelOverrides[modelId] as Map?;
        if (ov != null) {
          final name = (ov['name'] as String?)?.trim();
          if (name != null && name.isNotEmpty) {
            if (settings.showProviderInChatMessage && providerName.isNotEmpty) {
              return '$name | $providerName';
            }
            return name;
          }
          final apiId = (ov['apiModelId'] ?? ov['api_model_id'])
              ?.toString()
              .trim();
          if (apiId != null && apiId.isNotEmpty) {
            baseId = apiId;
          }
        }
      } catch (_) {
        // ignore lookup failures; fall through to inferred name.
      }
    }

    final inferred = ModelRegistry.infer(
      ModelInfo(id: baseId, displayName: baseId),
    );
    final fallback = inferred.displayName.trim();
    final displayName = fallback.isNotEmpty ? fallback : baseId;
    if (settings.showProviderInChatMessage &&
        providerName != null &&
        providerName.isNotEmpty) {
      return '$displayName | $providerName';
    }
    return displayName;
  }

  @override
  void dispose() {
    try {
      _userMenuOverlay?.remove();
    } catch (_) {}
    _userMenuOverlay = null;
    _ticker.dispose();
    _reasoningTick.dispose();
    _reasoningScroll.dispose();
    super.dispose();
  }

  void _showUserContextMenu() {
    // Haptic feedback (optional)
    try {
      Haptics.light();
    } catch (_) {}

    final box = _userBubbleKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (box == null || overlayBox == null) return;

    final bubbleTopLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final bubbleSize = box.size;
    final screenSize = overlayBox.size;
    final insets = MediaQuery.paddingOf(context); // status bar / gesture insets
    final safeLeft = insets.left + 12;
    final safeRight = insets.right + 12;
    final safeTop = insets.top + 12;
    final safeBottom = insets.bottom + 12;

    const double menuWidth = 220; // compact width
    const double estMenuHeight = 140; // ~ 3 rows
    const double gap = 10; // space between bubble and menu

    // Horizontal placement: align menu's right edge to bubble's right edge,
    // and clamp into safe area for better reachability on long messages.
    final double bubbleRight = bubbleTopLeft.dx + bubbleSize.width;
    double x = bubbleRight - menuWidth;
    final double minX = safeLeft;
    final double maxX = screenSize.width - safeRight - menuWidth;
    if (x < minX) x = minX;
    if (x > maxX) x = maxX;

    // Decide above vs below using safe area
    final availableAbove = bubbleTopLeft.dy - gap - safeTop;
    final availableBelow =
        (screenSize.height - safeBottom) -
        (bubbleTopLeft.dy + bubbleSize.height + gap);
    final bool canPlaceAbove = availableAbove >= estMenuHeight;
    final bool canPlaceBelow = availableBelow >= estMenuHeight;

    bool placeAbove;
    if (canPlaceAbove) {
      placeAbove = true;
    } else if (canPlaceBelow) {
      placeAbove = false;
    } else {
      // Fallback: choose the side with more space
      placeAbove = availableAbove > availableBelow;
    }

    double y = placeAbove
        ? (bubbleTopLeft.dy - estMenuHeight - gap)
        : (bubbleTopLeft.dy + bubbleSize.height + gap);

    // Clamp vertically to remain fully visible within safe area
    final double minY = safeTop;
    final double maxY = screenSize.height - safeBottom - estMenuHeight;
    if (y < minY) y = minY;
    if (y > maxY) y = maxY;

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'context-',
    );
  }
}