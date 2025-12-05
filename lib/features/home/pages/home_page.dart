import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'dart:async';
import '../../../shared/widgets/interactive_drawer.dart';
import '../../../shared/responsive/breakpoints.dart';
import '../widgets/chat_input_bar.dart';
import '../../../core/models/chat_input_data.dart';
import '../../chat/widgets/bottom_tools_sheet.dart';
import '../../chat/widgets/chat_message_widget.dart';
import '../../../theme/design_tokens.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:provider/provider.dart';
import '../../../main.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/models/token_usage.dart';
import '../../../core/providers/model_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/tts_provider.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/assistant.dart';
import '../controllers/chat_controller.dart';
import '../controllers/stream_controller.dart' as stream_ctrl;
import '../controllers/generation_controller.dart';
import '../services/message_builder_service.dart';
import '../services/ocr_service.dart';
import '../services/translation_service.dart';
import '../services/file_upload_service.dart';
import '../../model/widgets/model_select_sheet.dart';
import '../../chat/widgets/message_more_sheet.dart';
import '../../chat/models/message_edit_result.dart';
import '../../chat/widgets/message_edit_sheet.dart';
import '../../../desktop/message_edit_dialog.dart';
import '../../chat/widgets/message_export_sheet.dart';
import '../../assistant/widgets/mcp_assistant_sheet.dart';
import '../../mcp/pages/mcp_page.dart';
import '../../provider/pages/providers_page.dart';
import '../../chat/widgets/reasoning_budget_sheet.dart';
import '../../search/widgets/search_settings_sheet.dart';
import '../../../desktop/search_provider_popover.dart';
import '../../../desktop/reasoning_budget_popover.dart';
import '../../../desktop/mcp_servers_popover.dart';
import '../widgets/mini_map_sheet.dart';
import '../../../desktop/mini_map_popover.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../utils/brand_assets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../../../utils/assistant_regex.dart';
import '../../../utils/markdown_media_sanitizer.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../core/services/haptics.dart';
import 'dart:io' show File;
import '../../../core/services/notification_service.dart';
import '../../../utils/platform_utils.dart';
import '../../../desktop/hotkeys/chat_action_bus.dart';
import '../../../desktop/hotkeys/sidebar_tab_bus.dart';
import '../../../core/models/quick_phrase.dart';
import '../../../core/models/assistant_regex.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../core/providers/quick_phrase_provider.dart';
import '../../../core/providers/instruction_injection_provider.dart';
import '../../quick_phrase/widgets/quick_phrase_menu.dart';
import '../../quick_phrase/pages/quick_phrases_page.dart';
import '../../../shared/widgets/ios_checkbox.dart';
import '../../../desktop/quick_phrase_popover.dart';
import '../../../desktop/instruction_injection_popover.dart';
import 'home_mobile_layout.dart';
import 'home_desktop_layout.dart';
import '../utils/model_display_helper.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin, RouteAware, WidgetsBindingObserver {
  bool get _isDesktopPlatform => PlatformUtils.isDesktopTarget;
  // Desktop drag-and-drop state
  bool _isDragHovering = false;
  // Animation tuning
  static const Duration _postSwitchScrollDelay = Duration(milliseconds: 220);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final InteractiveDrawerController _drawerController = InteractiveDrawerController();
  final ValueNotifier<int> _assistantPickerCloseTick = ValueNotifier<int>(0);
  final FocusNode _inputFocus = FocusNode();
  final TextEditingController _inputController = TextEditingController();
  final ChatInputBarController _mediaController = ChatInputBarController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _inputBarKey = GlobalKey();
  late final AnimationController _convoFadeController;
  late final Animation<double> _convoFade;
  double _inputBarHeight = 72;

  late ChatService _chatService;
  late ChatController _chatController;
  late stream_ctrl.StreamController _streamController;
  late GenerationController _generationController;
  late MessageBuilderService _messageBuilderService;
  late OcrService _ocrService;
  late TranslationService _translationService;
  late FileUploadService _fileUploadService;

  // Delegate to ChatController for conversation state
  Conversation? get _currentConversation => _chatController.currentConversation;
  List<ChatMessage> get _messages => _chatController.messages;
  Map<String, int> get _versionSelections => _chatController.versionSelections;
  Set<String> get _loadingConversationIds => _chatController.loadingConversationIds;
  Map<String, StreamSubscription<dynamic>> get _conversationStreams => _chatController.conversationStreams;

  // Delegate to StreamController for streaming state
  Map<String, stream_ctrl.ReasoningData> get _reasoning => _streamController.reasoning;
  Map<String, List<stream_ctrl.ReasoningSegmentData>> get _reasoningSegments => _streamController.reasoningSegments;
  Map<String, List<ToolUIPart>> get _toolParts => _streamController.toolParts;

  final Map<String, _TranslationData> _translations = <String, _TranslationData>{};
  bool _appInForeground = true; // used to gate notifications only when app is background
  // Message widget keys for navigation to previous question
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  GlobalKey _keyForMessage(String id) => _messageKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'msg:$id'));
  McpProvider? _mcpProvider;
  bool _showJumpToBottom = false;
  bool _isUserScrolling = false;
  Timer? _userScrollTimer;
  bool _autoStickToBottom = true;
  bool _autoScrollScheduled = false;
  bool _autoScrollForceNext = false;
  bool _autoScrollAnimateNext = true;
  static const double _autoScrollSnapTolerance = 56.0;

  // NOTE: Streaming content throttle mechanism moved to StreamController
  // NOTE: Tool schema sanitization moved to GenerationController
  // Tablet: whether the left embedded sidebar is visible
  bool _tabletSidebarOpen = true;
  // Desktop: whether the right embedded topics sidebar is visible
  bool _rightSidebarOpen = true;
  // Desktop: resizable embedded sidebar width
  double _embeddedSidebarWidth = 300;
  static const double _sidebarMinWidth = 200;
  static const double _sidebarMaxWidth = 360;
  double _rightSidebarWidth = 300;
  bool _desktopUiInited = false;
  StreamSubscription<ChatAction>? _chatActionSub;
  
  void _openSearchSettings() {
    // On desktop platforms show the floating popover; mobile keeps bottom sheet
    if (PlatformUtils.isDesktop) {
      showDesktopSearchProviderPopover(context, anchorKey: _inputBarKey);
    } else {
      showSearchSettingsSheet(context);
    }
  }

  Future<void> _openReasoningSettings() async {
    if (PlatformUtils.isDesktop) {
      await showDesktopReasoningBudgetPopover(context, anchorKey: _inputBarKey);
    } else {
      await showReasoningBudgetSheet(context);
    }
  }

  Future<void> _openInstructionInjectionPopover() async {
    final isDesktop = PlatformUtils.isDesktop;
    final assistantId = context.read<AssistantProvider>().currentAssistantId;
    final provider = context.read<InstructionInjectionProvider>();
    await provider.initialize();
    final items = provider.items;
    if (items.isEmpty) return;

    if (isDesktop) {
      // 桌面端使用浮层样式（与搜索服务浮层一致）
      await showDesktopInstructionInjectionPopover(
        context,
        anchorKey: _inputBarKey,
        items: items,
        assistantId: assistantId,
      );
    } else {
      // 平板 / 非桌面端使用 bottom sheet，样式与其它设置 bottom sheet 统一
      final cs = Theme.of(context).colorScheme;
      final l10n = AppLocalizations.of(context)!;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetCtx) {
          return SafeArea(
            top: false,
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.55,
              maxChildSize: 0.9,
              minChildSize: 0.35,
              builder: (ctx, controller) {
                final p = ctx.watch<InstructionInjectionProvider>();
                final list = p.items;
                final activeIds = p.activeIdsFor(assistantId).toSet();
                return Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.instructionInjectionTitle,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  l10n.instructionInjectionSheetSubtitle,
                                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: list.isEmpty
                            ? Center(
                                child: Text(
                                  l10n.instructionInjectionEmptyMessage,
                                  style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
                                ),
                              )
                            : ListView.separated(
                                controller: controller,
                                itemCount: list.length,
                                itemBuilder: (ctx, index) {
                                  final item = list[index];
                                  final displayTitle = item.title.trim().isEmpty
                                      ? l10n.instructionInjectionDefaultTitle
                                      : item.title;
                                  final active = activeIds.contains(item.id);
                                  return IosCardPress(
                                    borderRadius: BorderRadius.circular(14),
                                    baseColor: Theme.of(ctx).brightness == Brightness.dark
                                        ? Colors.white10
                                        : Colors.white.withOpacity(0.96),
                                    duration: const Duration(milliseconds: 260),
                                    onTap: () async {
                                      Haptics.light();
                                      final prov = ctx.read<InstructionInjectionProvider>();
                                      await prov.toggleActiveId(item.id, assistantId: assistantId);
                                    },
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: Theme.of(ctx).brightness == Brightness.dark
                                                ? Colors.white10
                                                : const Color(0xFFF2F3F5),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          alignment: Alignment.center,
                                          child: Icon(Lucide.Layers, size: 20, color: cs.primary),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      displayTitle,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w700,
                                                        color: active ? cs.primary : cs.onSurface,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (active) ...[
                                                    const SizedBox(width: 6),
                                                    Icon(Lucide.Check, size: 16, color: cs.primary),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                item.prompt,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: cs.onSurface.withOpacity(0.72),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    }
  }

  // Drawer haptics for swipe-open
  double _lastDrawerValue = 0.0;
  // Removed early-open haptic; vibrate on open completion instead

  // Removed raw-pointer-based swipe-to-open; rely on drawer's own gestures

  Widget _buildAssistantBackground(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final assistant = context.watch<AssistantProvider>().currentAssistant;
    final bgRaw = (assistant?.background ?? '').trim();
    Widget? bg;
    if (bgRaw.isNotEmpty) {
      if (bgRaw.startsWith('http')) {
        bg = Image.network(bgRaw, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink());
      } else {
        try {
          final fixed = SandboxPathResolver.fix(bgRaw);
          final f = File(fixed);
          if (f.existsSync()) {
            bg = Image(image: FileImage(f), fit: BoxFit.cover);
          }
        } catch (_) {}
      }
    }
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Base fill to avoid black background when no assistant background set
          ColoredBox(color: cs.background),
          if (bg != null) Opacity(opacity: 0.9, child: bg),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  cs.background.withOpacity(0.08),
                  cs.background.withOpacity(0.36),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  // no-op placeholders removed


  Future<void> _showLearningPromptSheet() async {
    final provider = context.read<InstructionInjectionProvider>();
    await provider.initialize();
    final items = provider.items;
    if (items.isEmpty) return;
    final target = provider.active ?? items.first;
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: target.prompt);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.2), borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(l10n.bottomToolsSheetPrompt, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 10,
                  decoration: InputDecoration(
                    hintText: l10n.bottomToolsSheetPromptHint,
                    filled: true,
                    fillColor: Theme.of(ctx).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF2F3F5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary.withOpacity(0.5))),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Spacer(),
                    FilledButton(
                      onPressed: () async {
                        final updated = target.copyWith(prompt: controller.text.trim());
                        await ctx.read<InstructionInjectionProvider>().update(updated);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      child: Text(l10n.bottomToolsSheetSave),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Anchor for chained "jump to previous question" navigation
  String? _lastJumpUserMessageId;

  // Deduplicate tool UI parts (delegate to StreamController)
  List<ToolUIPart> _dedupeToolPartsList(List<ToolUIPart> parts) {
    return _streamController.dedupeToolPartsList(parts);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = (state == AppLifecycleState.resumed);
  }

  // Deduplicate raw persisted tool events (delegate to StreamController)
  List<Map<String, dynamic>> _dedupeToolEvents(List<Map<String, dynamic>> events) {
    return _streamController.dedupeToolEvents(events);
  }

  // Selection mode state for export/share
  bool _selecting = false;
  final Set<String> _selectedItems = <String>{}; // selected message ids (collapsed view)

  // Helper methods to serialize/deserialize reasoning segments (delegate to StreamController)
  String _serializeReasoningSegments(List<stream_ctrl.ReasoningSegmentData> segments) {
    return _streamController.serializeReasoningSegments(segments);
  }

  bool _isReasoningModel(String providerKey, String modelId) {
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(providerKey);
    final ov = cfg.modelOverrides[modelId] as Map?;
    if (ov != null && ov.containsKey('abilities')) {
      final abilities = (ov['abilities'] as List?)
              ?.map((e) => e.toString().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [];
      return abilities.contains('reasoning');
    }
    final inferred = ModelRegistry.infer(ModelInfo(id: modelId, displayName: modelId));
    return inferred.abilities.contains(ModelAbility.reasoning);
  }

  // Whether current conversation is generating
  bool get _isCurrentConversationLoading {
    final cid = _currentConversation?.id;
    if (cid == null) return false;
    return _loadingConversationIds.contains(cid);
  }

  // Update loading state for a conversation and refresh UI if needed
  void _setConversationLoading(String conversationId, bool loading) {
    final prev = _loadingConversationIds.contains(conversationId);
    _chatController.setConversationLoading(conversationId, loading);
    if (mounted && prev != loading) {
      setState(() {}); // Update input bar + drawer indicators
    }
  }

  Future<void> _cancelStreaming() async {
    final cid = _currentConversation?.id;
    if (cid == null) return;
    // Cancel active stream for current conversation only
    final sub = _conversationStreams.remove(cid);
    await sub?.cancel();

    // Find the latest assistant streaming message within current conversation and mark it finished
    ChatMessage? streaming;
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.role == 'assistant' && m.isStreaming) {
        streaming = m;
        break;
      }
    }
    if (streaming != null) {
      await _chatService.updateMessage(
        streaming.id,
        content: streaming.content,
        isStreaming: false,
        totalTokens: streaming.totalTokens,
      );
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == streaming!.id);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(isStreaming: false);
          }
        });
      }
      _setConversationLoading(cid, false);

      // Use unified reasoning completion method
      await _streamController.finishReasoningAndPersist(
        streaming.id,
        updateReasoningInDb: (
          String messageId, {
          String? reasoningText,
          DateTime? reasoningFinishedAt,
          String? reasoningSegmentsJson,
        }) async {
          await _chatService.updateMessage(
            messageId,
            reasoningText: reasoningText,
            reasoningFinishedAt: reasoningFinishedAt,
            reasoningSegmentsJson: reasoningSegmentsJson,
          );
        },
      );

      // If streaming output included inline base64 images, sanitize them even on manual cancel
      _scheduleInlineImageSanitize(streaming.id, latestContent: streaming.content, immediate: true);
    } else {
      _setConversationLoading(cid, false);
    }
  }

  bool _isReasoningEnabled(int? budget) {
    if (budget == null) return true; // treat null as default/auto -> enabled
    if (budget == -1) return true; // auto
    return budget >= 1024;
  }

  void _scheduleInlineImageSanitize(String messageId, {String? latestContent, bool immediate = false}) {
    // Quick pre-check using provided content (if any) to avoid needless timers.
    final snapshot = latestContent ??
        (() {
          final idx = _messages.indexWhere((m) => m.id == messageId);
          return idx == -1 ? '' : _messages[idx].content;
        })();
    if (snapshot.isEmpty || !snapshot.contains('data:image') || !snapshot.contains('base64,')) {
      return;
    }

    _streamController.scheduleInlineImageSanitize(
      messageId,
      latestContent: snapshot,
      immediate: immediate,
      onSanitized: (id, sanitized) async {
        await _chatService.updateMessage(id, content: sanitized);
        if (!mounted) return;
        setState(() {
          final i = _messages.indexWhere((m) => m.id == id);
          if (i != -1) {
            _messages[i] = _messages[i].copyWith(content: sanitized);
          }
        });
      },
    );
  }

  // Delegate to StreamController for Gemini thought signature handling
  String _captureGeminiThoughtSignature(String content, String messageId) {
    return _streamController.captureGeminiThoughtSignature(content, messageId);
  }

  String _appendGeminiThoughtSignatureForApi(ChatMessage message, String content) {
    return _streamController.appendGeminiThoughtSignatureForApi(message, content);
  }

  String _titleForLocale(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return l10n.titleForLocale;
  }

  // Restore per-message UI states (reasoning/segments/tool parts/translation) after switching conversations
  void _restoreMessageUiState() {
    // Do NOT clear global maps here; other conversations might still be streaming.
    // We will simply populate/overwrite entries for messages in the current conversation.
    for (int i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m.role == 'assistant') {
        // Restore message UI state via StreamController
        _streamController.restoreMessageUiState(
          m,
          getToolEventsFromDb: (id) => _chatService.getToolEvents(id),
          getGeminiThoughtSigFromDb: (id) => _chatService.getGeminiThoughtSignature(id),
        );

        // Clean content from gemini thought signatures
        final cleanedContent = _captureGeminiThoughtSignature(m.content, m.id);
        if (cleanedContent != m.content) {
          final updated = m.copyWith(content: cleanedContent);
          _messages[i] = updated;
          unawaited(_chatService.updateMessage(m.id, content: cleanedContent));
        }

        // Clean up any inline base64 images persisted from earlier runs
        _scheduleInlineImageSanitize(m.id, latestContent: _messages[i].content, immediate: true);
      }

      // Restore translation UI state: default collapsed
      if (m.translation != null && m.translation!.isNotEmpty) {
        final td = _TranslationData();
        td.expanded = false;
        _translations[m.id] = td;
      }
    }
  }

  List<ChatMessage> _collapseVersions(List<ChatMessage> items) {
    final Map<String, List<ChatMessage>> byGroup = <String, List<ChatMessage>>{};
    final List<String> order = <String>[];
    for (final m in items) {
      final gid = (m.groupId ?? m.id);
      final list = byGroup.putIfAbsent(gid, () {
        order.add(gid);
        return <ChatMessage>[];
      });
      list.add(m);
    }
    for (final e in byGroup.entries) {
      e.value.sort((a, b) => a.version.compareTo(b.version));
    }
    final out = <ChatMessage>[];
    for (final gid in order) {
      final vers = byGroup[gid]!;
      final sel = _versionSelections[gid];
      final idx = (sel != null && sel >= 0 && sel < vers.length) ? sel : (vers.length - 1);
      out.add(vers[idx]);
    }
    return out;
  }

  String _clearContextLabel() {
    final l10n = AppLocalizations.of(context)!;
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final configured = (assistant?.limitContextMessages ?? true) ? (assistant?.contextMessageSize ?? 0) : 0;
    // Use collapsed view for counting
    final collapsed = _collapseVersions(_messages);
    // Map raw truncate index to collapsed start index
    final int tRaw = _currentConversation?.truncateIndex ?? -1;
    int startCollapsed = 0;
    if (tRaw > 0) {
      final seen = <String>{};
      final int limit = tRaw < _messages.length ? tRaw : _messages.length;
      int count = 0;
      for (int i = 0; i < limit; i++) {
        final gid0 = (_messages[i].groupId ?? _messages[i].id);
        if (seen.add(gid0)) count++;
      }
      startCollapsed = count; // inclusive start index in collapsed list
    }
    int remaining = 0;
    for (int i = 0; i < collapsed.length; i++) {
      if (i >= startCollapsed) {
        if (collapsed[i].content.trim().isNotEmpty) remaining++;
      }
    }
    if (configured > 0) {
      final actual = remaining > configured ? configured : remaining;
      return l10n.homePageClearContextWithCount(actual.toString(), configured.toString());
    }
    return l10n.homePageClearContext;
  }

  Future<void> _onClearContext() async {
    final convo = _currentConversation;
    if (convo == null) return;
    final updated = await _chatService.toggleTruncateAtTail(convo.id, defaultTitle: _titleForLocale(context));
    if (!mounted) return;
    if (updated != null) {
      setState(() {
        _chatController.updateCurrentConversation(updated);
      });
    }
    // No inline panel to close; modal sheet is dismissed before action
  }

  void _toggleTools() async {
    // Open as modal bottom sheet instead of inline overlay
    _dismissKeyboard();
    final cs = Theme.of(context).colorScheme;
    final assistantId = context.read<AssistantProvider>().currentAssistantId;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: BottomToolsSheet(
            onPhotos: () {
              Navigator.of(ctx).maybePop();
              _onPickPhotos();
            },
            onCamera: () {
              Navigator.of(ctx).maybePop();
              _onPickCamera();
            },
            onUpload: () {
              Navigator.of(ctx).maybePop();
              _onPickFiles();
            },
            onClear: () async {
              Navigator.of(ctx).maybePop();
              await _onClearContext();
            },
            clearLabel: _clearContextLabel(),
            assistantId: assistantId,
          ),
        );
      },
    );
  }

  bool _isToolModel(String providerKey, String modelId) {
    final settings = context.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(providerKey);
    final ov = cfg.modelOverrides[modelId] as Map?;
    if (ov != null && ov.containsKey('abilities')) {
      final abilities = (ov['abilities'] as List?)
              ?.map((e) => e.toString().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [];
      return abilities.contains('tool');
    }
    final inferred = ModelRegistry.infer(ModelInfo(id: modelId, displayName: modelId));
    return inferred.abilities.contains(ModelAbility.tool);
  }

  // More page entry is temporarily removed.
  // void _openMorePage() {
  //   _dismissKeyboard();
  //   Navigator.of(context).push(
  //     MaterialPageRoute(builder: (_) => const MorePage()),
  //   );
  // }

  void _dismissKeyboard() {
    _inputFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();
    try { SystemChannels.textInput.invokeMethod('TextInput.hide'); } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    try { WidgetsBinding.instance.addObserver(this); } catch (_) {}
    _convoFadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    _convoFade = CurvedAnimation(parent: _convoFadeController, curve: Curves.easeOutCubic);
    _convoFadeController.value = 1.0;
    // Use the provided ChatService instance
    _chatService = context.read<ChatService>();
    // Initialize ChatController for conversation state management
    _chatController = ChatController(chatService: _chatService);
    // Initialize StreamController for streaming state management
    _streamController = stream_ctrl.StreamController(
      chatService: _chatService,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
      getSettingsProvider: () => context.read<SettingsProvider>(),
      getCurrentConversationId: () => _currentConversation?.id,
    );
    // Initialize OcrService for OCR processing
    _ocrService = OcrService();
    // Initialize TranslationService for message translation
    _translationService = TranslationService(
      chatService: _chatService,
      contextProvider: context,
    );
    // Initialize FileUploadService for file picking and upload
    _fileUploadService = FileUploadService(
      mediaController: _mediaController,
      onScrollToBottom: _scrollToBottomSoon,
    );
    // Initialize MessageBuilderService for API message construction
    _messageBuilderService = MessageBuilderService(
      chatService: _chatService,
      contextProvider: context,
      ocrHandler: (imagePaths) => _ocrService.getOcrTextForImages(imagePaths, context),
      geminiThoughtSignatureHandler: _appendGeminiThoughtSignatureForApi,
    );
    _messageBuilderService.ocrTextWrapper = _ocrService.wrapOcrBlock;
    // Initialize GenerationController for message generation coordination
    _generationController = GenerationController(
      chatService: _chatService,
      chatController: _chatController,
      streamController: _streamController,
      messageBuilderService: _messageBuilderService,
      contextProvider: context,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
      getTitleForLocale: _titleForLocale,
    );
    _initChat();
    _scrollController.addListener(_onScrollControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureInputBar());

    // Initialize quick phrases provider
    Future.microtask(() async {
      try {
        await context.read<QuickPhraseProvider>().initialize();
      } catch (_) {}
    });
    // Initialize instruction injection provider
    Future.microtask(() async {
      try {
        await context.read<InstructionInjectionProvider>().initialize();
      } catch (_) {}
    });

    // Attach MCP provider listener (kept for potential future use)
    try {
      _mcpProvider = context.read<McpProvider>();
      _mcpProvider!.addListener(_onMcpChanged);
    } catch (_) {}

    // 监听键盘弹出
    _inputFocus.addListener(() {
      if (_inputFocus.hasFocus) {
        // 移动端：键盘弹出后稍微滚到底部，避免遮挡输入框；
        // 桌面端：仅聚焦，不再强制滚动，保留当前阅读位置。
        if (!_isDesktopPlatform) {
          Future.delayed(const Duration(milliseconds: 300), () {
            _scrollToBottom();
          });
        }
      }
    });

    // Attach drawer value listener to catch swipe-open and close events
    _drawerController.addListener(_onDrawerValueChanged);

    // 桌面端初次进入聊天页时自动聚焦输入框
    if (_isDesktopPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _inputFocus.requestFocus();
        }
      });
    }

    // Listen to desktop hotkey actions (chat-only)
    _chatActionSub = ChatActionBus.instance.stream.listen((action) async {
      switch (action) {
        case ChatAction.newTopic:
          await _createNewConversationAnimated();
          break;
        case ChatAction.toggleLeftPanelTopics:
        case ChatAction.toggleLeftPanelAssistants:
          final sp = context.read<SettingsProvider>();
          if (sp.desktopTopicPosition != DesktopTopicPosition.left) return;
          final wantAssistants = (action == ChatAction.toggleLeftPanelAssistants);
          // 行为：
          // - 如果侧边栏关闭：打开并切换到目标标签
          // - 如果侧边栏打开：仅切换标签，不再关闭
          if (!_tabletSidebarOpen) {
            setState(() => _tabletSidebarOpen = true);
            try { context.read<SettingsProvider>().setDesktopSidebarOpen(true); } catch (_) {}
          }
          if (wantAssistants) {
            DesktopSidebarTabBus.instance.switchToAssistants();
          } else {
            DesktopSidebarTabBus.instance.switchToTopics();
          }
          break;
        case ChatAction.focusInput:
          if (_isDesktopPlatform) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _inputFocus.requestFocus();
              }
            });
          }
          break;
        default:
          break;
      }
    });
  }

  void _onDrawerValueChanged() {
    final v = _drawerController.value;
    // If user starts opening the drawer via swipe, dismiss the keyboard once
    if (_lastDrawerValue <= 0.01 && v > 0.01) {
      _dismissKeyboard();
    }
    // Fire haptic when drawer becomes sufficiently open (completion)
    if (_lastDrawerValue < 0.95 && v >= 0.95) {
      try {
        if (context.read<SettingsProvider>().hapticsOnDrawer) {
          Haptics.drawerPulse();
        }
      } catch (_) {}
    }
    // Fire haptic when drawer becomes sufficiently closed (cancellation)
    if (_lastDrawerValue > 0.05 && v <= 0.05) {
      try {
        if (context.read<SettingsProvider>().hapticsOnDrawer) {
          Haptics.drawerPulse();
        }
      } catch (_) {}
    }
    // When transitioning from open to closing, close assistant picker overlay
    if (_lastDrawerValue >= 0.95 && v < 0.95) {
      _assistantPickerCloseTick.value++;
    }
    _lastDrawerValue = v;
  }

  // Toggle tablet sidebar (embedded mode); keep icon and haptics same style as mobile
  void _toggleTabletSidebar() {
    _dismissKeyboard();
    try {
      if (context.read<SettingsProvider>().hapticsOnDrawer) {
        Haptics.drawerPulse();
      }
    } catch (_) {}
    setState(() {
      _tabletSidebarOpen = !_tabletSidebarOpen;
    });
    try { context.read<SettingsProvider>().setDesktopSidebarOpen(_tabletSidebarOpen); } catch (_) {}
  }

  void _toggleRightSidebar() {
    _dismissKeyboard();
    try {
      if (context.read<SettingsProvider>().hapticsOnDrawer) {
        Haptics.drawerPulse();
      }
    } catch (_) {}
    setState(() {
      _rightSidebarOpen = !_rightSidebarOpen;
    });
    try { context.read<SettingsProvider>().setDesktopRightSidebarOpen(_rightSidebarOpen); } catch (_) {}
  }

  // ZoomDrawer state listener removed; handled by _onDrawerValueChanged

  void _onScrollControllerChanged() {
    try {
      if (!_scrollController.hasClients) return;
      final settings = context.read<SettingsProvider>();
      final autoScrollEnabled = settings.autoScrollEnabled;

      // Detect user scrolling
      if (_scrollController.position.userScrollDirection != ScrollDirection.idle) {
        _isUserScrolling = true;
        _autoStickToBottom = false;
        // Reset chained jump anchor when user manually scrolls
        _lastJumpUserMessageId = null;
        
        // Cancel previous timer and set a new one
        _userScrollTimer?.cancel();
        final secs = settings.autoScrollIdleSeconds;
        _userScrollTimer = Timer(Duration(seconds: secs), () {
          if (mounted) {
            setState(() {
              _isUserScrolling = false;
            });
            _refreshAutoStickToBottom();
          }
        });
      }
      
      // Only show when not near bottom
      final atBottom = _isNearBottom(24);
      if (!atBottom) {
        _autoStickToBottom = false;
      } else if (!_isUserScrolling && (autoScrollEnabled || _autoStickToBottom)) {
        _autoStickToBottom = true;
      }
      final shouldShow = !atBottom;
      if (_showJumpToBottom != shouldShow) {
        setState(() => _showJumpToBottom = shouldShow);
      }
    } catch (_) {}
  }

  Future<void> _initChat() async {
    await _chatService.init();
    // Respect user preference: create new chat on launch
    final prefs = context.read<SettingsProvider>();
    if (prefs.newChatOnLaunch) {
      await _createNewConversation();
    } else {
      // When disabled, jump to the most recent conversation if exists
      final conversations = _chatService.getAllConversations();
      if (conversations.isNotEmpty) {
        final recent = conversations.first; // already sorted by updatedAt desc
        // Ensure the current assistant matches the conversation's owner to avoid mismatched prompts
        if ((recent.assistantId ?? '').isNotEmpty) {
          try { await context.read<AssistantProvider>().setCurrentAssistant(recent.assistantId!); } catch (_) {}
        }
        _chatService.setCurrentConversation(recent.id);
        setState(() {
          _chatController.setCurrentConversation(recent);
          _streamController.clearGeminiThoughtSigs();
          _restoreMessageUiState();
        });
        _scrollToBottomSoon(animate: false);
      }
    }
  }

  Future<void> _switchConversationAnimated(String id) async {
    // Before switching, persist any in-flight reasoning/content of current conversation
    try { await _flushCurrentConversationProgress(); } catch (_) {}
    if (_currentConversation?.id == id) return;
    if (!_isDesktopPlatform) {
      try {
        await _convoFadeController.reverse();
      } catch (_) {}
    } else {
      // Desktop: skip fade-out to switch instantly
      try { _convoFadeController.stop(); _convoFadeController.value = 1.0; } catch (_) {}
    }
    _chatService.setCurrentConversation(id);
    final convo = _chatService.getConversation(id);
    if (convo != null) {
      if (mounted) {
        setState(() {
          _chatController.setCurrentConversation(convo);
          _streamController.clearGeminiThoughtSigs();
          _restoreMessageUiState();
        });
        // Ensure list lays out, then jump to bottom while hidden
        try { await WidgetsBinding.instance.endOfFrame; } catch (_) {}
        _scrollToBottom(animate: false);
      }
    }
    if (mounted && !_isDesktopPlatform) {
      try { await _convoFadeController.forward(); } catch (_) {}
    }
    // 桌面端：切换话题后自动聚焦输入框，方便继续输入
    if (mounted && _isDesktopPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _inputFocus.requestFocus();
        }
      });
    }
  }

  Future<void> _createNewConversationAnimated() async {
    // Flush current conversation progress before creating a new one
    try { await _flushCurrentConversationProgress(); } catch (_) {}
    if (!_isDesktopPlatform) {
      try { await _convoFadeController.reverse(); } catch (_) {}
    }
    await _createNewConversation();
    if (mounted && !_isDesktopPlatform) {
      // Mobile: keep smooth fade for new conversation
      try { await _convoFadeController.forward(); } catch (_) {}
    }
    // 桌面端：新建话题后也自动聚焦输入框
    if (mounted && _isDesktopPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _inputFocus.requestFocus();
        }
      });
    }
  }

  // _onMcpChanged defined below; remove listener in the main dispose at bottom

  Future<void> _onMcpChanged() async {
    // Assistant-level MCP selection is managed in Assistant settings; no per-conversation merge.
    // This callback is kept for potential future use but currently does nothing.
  }

  // File upload methods delegated to FileUploadService
  Future<void> _onPickPhotos() => _fileUploadService.onPickPhotos();
  Future<void> _onPickCamera() => _fileUploadService.onPickCamera(context);
  Future<void> _onPickFiles() => _fileUploadService.onPickFiles();
  Future<void> _onFilesDroppedDesktop(List<XFile> files) => _fileUploadService.onFilesDroppedDesktop(files);

  // Wraps a widget with desktop DropTarget to accept drag-and-drop files
  Widget _wrapWithDropTarget(Widget child) {
    if (!_isDesktopPlatform) return child;
    return DropTarget(
      onDragEntered: (_) {
        setState(() => _isDragHovering = true);
      },
      onDragExited: (_) {
        setState(() => _isDragHovering = false);
      },
      onDragDone: (details) async {
        setState(() => _isDragHovering = false);
        try {
          final files = details.files; // List<XFile>
          await _onFilesDroppedDesktop(files);
        } catch (_) {}
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (_isDragHovering)
            IgnorePointer(
              child: Container(
                color: Colors.black.withOpacity(0.12),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.4), width: 2),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.homePageDropToUpload,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _createNewConversation() async {
    // Flush any ongoing generation progress for the current conversation
    try { await _flushCurrentConversationProgress(); } catch (_) {}
    final ap = context.read<AssistantProvider>();
    final assistantId = ap.currentAssistantId;
    // Don't change global default model - just use assistant's model if set
    final a = ap.currentAssistant;
    final conversation = await _chatService.createDraftConversation(title: _titleForLocale(context), assistantId: assistantId);
    // Default-enable MCP: select all connected servers for this conversation
    // MCP defaults are now managed per assistant; no per-conversation enabling here
    setState(() {
      _chatController.setCurrentConversation(conversation);
      _streamController.clearAllState();
      _translations.clear();
    });
    // Inject assistant preset messages into new conversation (ordered)
    try {
      final ap2 = context.read<AssistantProvider>();
      final presets = ap2.getPresetMessagesForAssistant(a?.id);
      if (presets.isNotEmpty && _currentConversation != null) {
        for (final pm in presets) {
          final role = (pm['role'] == 'assistant') ? 'assistant' : 'user';
          final content = (pm['content'] ?? '').trim();
          if (content.isEmpty) continue;
          await _chatService.addMessage(
            conversationId: _currentConversation!.id,
            role: role,
            content: content,
          );
          if (mounted) {
            setState(() { _chatController.reloadMessages(); });
          }
        }
      }
    } catch (_) {}
    _scrollToBottomSoon(animate: false);
  }

  // Persist latest in-flight assistant message content and reasoning of the current conversation
  Future<void> _flushCurrentConversationProgress() async {
    final cid = _currentConversation?.id;
    if (cid == null || _messages.isEmpty) return;
    // Find the latest streaming assistant message in the current conversation
    ChatMessage? streaming;
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.role == 'assistant' && m.isStreaming && m.conversationId == cid) {
        streaming = m;
        break;
      }
    }
    if (streaming == null) return;
    // Use the UI-side content snapshot (may be ahead of last persisted chunk)
    String latestContent = streaming.content;
    // Also capture reasoning progress if tracked in-memory
    final r = _reasoning[streaming.id];
    final segs = _reasoningSegments[streaming.id];
    try {
      await _chatService.updateMessage(
        streaming.id,
        content: latestContent,
        totalTokens: streaming.totalTokens,
        // Do not flip isStreaming here; just flush progress
      );
      if (r != null) {
        await _chatService.updateMessage(
          streaming.id,
          reasoningText: r.text,
          reasoningStartAt: r.startAt ?? DateTime.now(),
          // keep finishedAt as-is (may be null while thinking)
        );
      }
      if (segs != null && segs.isNotEmpty) {
        await _chatService.updateMessage(
          streaming.id,
          reasoningSegmentsJson: _serializeReasoningSegments(segs),
        );
      }
      // Ensure any inline data URLs get converted even if the user navigates away mid-stream
      _scheduleInlineImageSanitize(streaming.id, latestContent: latestContent, immediate: true);
    } catch (_) {}
  }

  /// Send a new message and generate an assistant response.
  /// This method handles:
  /// 1. Input validation
  /// 2. User message creation and persistence
  /// 3. Assistant message placeholder creation
  /// 4. API message preparation (documents, OCR, system prompts, tools)
  /// 5. Streaming generation via _executeGeneration
  Future<void> _sendMessage(ChatInputData input) async {
    final content = input.text.trim();
    if (content.isEmpty && input.imagePaths.isEmpty && input.documents.isEmpty) return;
    if (_currentConversation == null) await _createNewConversation();

    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final assistantId = assistant?.id;

    // Use assistant's model if set, otherwise fall back to global default
    final providerKey = assistant?.chatModelProvider ?? settings.currentModelProvider;
    final modelId = assistant?.chatModelId ?? settings.currentModelId;

    if (providerKey == null || modelId == null) {
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.homePagePleaseSelectModel,
        type: NotificationType.warning,
      );
      return;
    }

    // === Step 1: Create and persist user message ===
    final imageMarkers = input.imagePaths.map((p) => '\n[image:$p]').join();
    final docMarkers = input.documents.map((d) => '\n[file:${d.path}|${d.fileName}|${d.mime}]').join();
    final processedUserText = applyAssistantRegexes(
      content,
      assistant: assistant,
      scope: AssistantRegexScope.user,
      visual: false,
    );
    final userMessage = await _chatService.addMessage(
      conversationId: _currentConversation!.id,
      role: 'user',
      content: processedUserText + imageMarkers + docMarkers,
    );

    setState(() {
      _messages.add(userMessage);
    });
    _setConversationLoading(_currentConversation!.id, true);
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollToBottom();
    });

    // === Step 2: Create assistant message placeholder ===
    final assistantMessage = await _chatService.addMessage(
      conversationId: _currentConversation!.id,
      role: 'assistant',
      content: '',
      modelId: modelId,
      providerId: providerKey,
      isStreaming: true,
    );

    setState(() {
      _messages.add(assistantMessage);
    });

    // Haptics on generate (if enabled)
    try {
      if (context.read<SettingsProvider>().hapticsOnGenerate) {
        Haptics.light();
      }
    } catch (_) {}

    // Reset tool parts for this new assistant message
    _toolParts.remove(assistantMessage.id);

    // Initialize reasoning state only when enabled and model supports it
    final supportsReasoning = _isReasoningModel(providerKey, modelId);
    final enableReasoning = supportsReasoning && _isReasoningEnabled((assistant?.thinkingBudget) ?? settings.thinkingBudget);
    if (enableReasoning) {
      final rd = stream_ctrl.ReasoningData();
      _reasoning[assistantMessage.id] = rd;
      await _chatService.updateMessage(
        assistantMessage.id,
        reasoningStartAt: DateTime.now(),
      );
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollToBottom();
    });

    // === Step 3: Build API messages ===
    final apiMessages = _buildApiMessages();

    // === Step 4: Process user messages (documents, OCR, templates) ===
    final bool ocrActive = settings.ocrEnabled &&
        settings.ocrModelProvider != null &&
        settings.ocrModelId != null;
    await _processUserMessagesForApi(apiMessages, settings, assistant);

    // === Step 5: Inject prompts ===
    _injectSystemPrompt(apiMessages, assistant, modelId);
    await _injectMemoryAndRecentChats(apiMessages, assistant);

    final hasBuiltInSearch = _hasBuiltInGeminiSearch(settings, providerKey, modelId);
    _injectSearchPrompt(apiMessages, settings, hasBuiltInSearch);
    await _injectInstructionPrompts(apiMessages, assistantId);

    // === Step 6: Apply context limit and inline images ===
    _applyContextLimit(apiMessages, assistant);
    await _inlineLocalImages(apiMessages);

    // === Step 7: Prepare tools and config ===
    final toolDefs = _buildToolDefinitions(settings, assistant, providerKey, modelId, hasBuiltInSearch);
    final onToolCall = toolDefs.isNotEmpty ? _buildToolCallHandler(settings, assistant) : null;

    // Collect video attachments from current input
    final currentVideoPaths = <String>[
      for (final d in input.documents)
        if (d.mime.toLowerCase().startsWith('video/')) d.path,
    ];

    // Build user image paths for API call
    final userImagePaths = ocrActive
        ? const <String>[]
        : <String>[
            ...input.imagePaths,
            ...currentVideoPaths,
          ];

    // === Step 8: Execute generation ===
    final ctx = stream_ctrl.GenerationContext(
      assistantMessage: assistantMessage,
      apiMessages: apiMessages,
      userImagePaths: userImagePaths,
      providerKey: providerKey,
      modelId: modelId,
      assistant: assistant,
      settings: settings,
      config: settings.getProviderConfig(providerKey),
      toolDefs: toolDefs,
      onToolCall: onToolCall,
      extraHeaders: _buildCustomHeaders(assistant),
      extraBody: _buildCustomBody(assistant),
      supportsReasoning: supportsReasoning,
      enableReasoning: enableReasoning,
      streamOutput: assistant?.streamOutput ?? true,
      generateTitleOnFinish: true,
    );

    await _executeGeneration(ctx);
  }

  Future<void> _regenerateAtMessage(ChatMessage message, {bool assistantAsNewReply = false}) async {
    if (_currentConversation == null) return;
    // Cancel any ongoing stream
    await _cancelStreaming();

    final idx = _messages.indexWhere((m) => m.id == message.id);
    if (idx < 0) return;

    // Compute versioning target (groupId + nextVersion) and where to cut
    String? targetGroupId;
    int nextVersion = 0;
    int lastKeep;
    if (message.role == 'assistant') {
      // Keep the existing assistant message; optionally open a new group for the new reply
      lastKeep = idx; // remove after this
      if (assistantAsNewReply) {
        targetGroupId = null; // start a new group for the upcoming assistant reply
        nextVersion = 0;
      } else {
        targetGroupId = message.groupId ?? message.id;
        int maxVer = -1;
        for (final m in _messages) {
          final gid = (m.groupId ?? m.id);
          if (gid == targetGroupId) {
            if (m.version > maxVer) maxVer = m.version;
          }
        }
        nextVersion = maxVer + 1;
      }
    } else {
      // User message: find the first assistant reply after the FIRST occurrence of this user group,
      // not after the current version's position (which may be appended at tail after edits).
      final userGroupId = message.groupId ?? message.id;
      int userFirst = -1;
      for (int i = 0; i < _messages.length; i++) {
        final gid0 = (_messages[i].groupId ?? _messages[i].id);
        if (gid0 == userGroupId) { userFirst = i; break; }
      }
      if (userFirst < 0) userFirst = idx; // fallback

      int aid = -1;
      for (int i = userFirst + 1; i < _messages.length; i++) {
        if (_messages[i].role == 'assistant') { aid = i; break; }
      }
      if (aid >= 0) {
        lastKeep = aid; // keep that assistant message as old version
        targetGroupId = _messages[aid].groupId ?? _messages[aid].id;
        int maxVer = -1;
        for (final m in _messages) {
          final gid = (m.groupId ?? m.id);
          if (gid == targetGroupId) {
            if (m.version > maxVer) maxVer = m.version;
          }
        }
        nextVersion = maxVer + 1;
      } else {
        // No assistant reply yet; keep up to the first user message occurrence and start new group
        lastKeep = userFirst;
        targetGroupId = null; // will be set to new id automatically
        nextVersion = 0;
      }
    }

    // Remove messages after lastKeep (persistently), but preserve:
    // - all versions of groups that already appeared up to lastKeep (e.g., edited user messages), and
    // - all versions of the target assistant group we are regenerating
    if (lastKeep < _messages.length - 1) {
      // Collect groups that appear at or before lastKeep
      final keepGroups = <String>{};
      for (int i = 0; i <= lastKeep && i < _messages.length; i++) {
        final g = (_messages[i].groupId ?? _messages[i].id);
        keepGroups.add(g);
      }
      if (targetGroupId != null) keepGroups.add(targetGroupId!);

      final trailing = _messages.sublist(lastKeep + 1);
      final removeIds = <String>[];
      for (final m in trailing) {
        final gid = (m.groupId ?? m.id);
        final shouldKeep = keepGroups.contains(gid);
        if (!shouldKeep) removeIds.add(m.id);
      }
      for (final id in removeIds) {
        try { await _chatService.deleteMessage(id); } catch (_) {}
        _reasoning.remove(id);
        _translations.remove(id);
        _toolParts.remove(id);
        _reasoningSegments.remove(id);
      }
      if (removeIds.isNotEmpty) {
        setState(() {
          _messages.removeWhere((m) => removeIds.contains(m.id));
        });
      }
    }

    // Start a new assistant generation from current context
    final settings = context.read<SettingsProvider>();
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final assistantId = assistant?.id;
    
    // Use assistant's model if set, otherwise fall back to global default
    final providerKey = assistant?.chatModelProvider ?? settings.currentModelProvider;
    final modelId = assistant?.chatModelId ?? settings.currentModelId;

    if (providerKey == null || modelId == null) {
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(
        context,
        message: l10n.homePagePleaseSelectModel,
        type: NotificationType.warning,
      );
      return;
    }

    // Create assistant message placeholder (new version in target group)
    final assistantMessage = await _chatService.addMessage(
      conversationId: _currentConversation!.id,
      role: 'assistant',
      content: '',
      modelId: modelId,
      providerId: providerKey,
      isStreaming: true,
      groupId: targetGroupId,
      version: nextVersion,
    );

    // Persist selection to the latest version of this group
    final gid = assistantMessage.groupId ?? assistantMessage.id;
    _versionSelections[gid] = assistantMessage.version;
    await _chatService.setSelectedVersion(_currentConversation!.id, gid, assistantMessage.version);

    setState(() {
      _messages.add(assistantMessage);
    });
    _setConversationLoading(_currentConversation!.id, true);

    // Haptics on regenerate
    try {
      if (context.read<SettingsProvider>().hapticsOnGenerate) {
        Haptics.light();
      }
    } catch (_) {}

    // Initialize reasoning state only when enabled and model supports it
    final supportsReasoning = _isReasoningModel(providerKey, modelId);
    final enableReasoning = supportsReasoning && _isReasoningEnabled((assistant?.thinkingBudget) ?? settings.thinkingBudget);
    if (enableReasoning) {
      final rd = stream_ctrl.ReasoningData();
      _reasoning[assistantMessage.id] = rd;
      await _chatService.updateMessage(assistantMessage.id, reasoningStartAt: DateTime.now());
    }

    // === Build API messages using shared helpers ===
    final apiMessages = _buildApiMessages();

    // Process user messages (documents, OCR, templates) and get image paths from last user message
    final lastUserImagePaths = await _processUserMessagesForApi(apiMessages, settings, assistant);

    // Inject system prompt and additional context
    _injectSystemPrompt(apiMessages, assistant, modelId);
    await _injectMemoryAndRecentChats(apiMessages, assistant);

    final hasBuiltInSearch = _hasBuiltInGeminiSearch(settings, providerKey, modelId);
    _injectSearchPrompt(apiMessages, settings, hasBuiltInSearch);
    await _injectInstructionPrompts(apiMessages, assistantId);

    // Apply context limit and inline images
    _applyContextLimit(apiMessages, assistant);
    await _inlineLocalImages(apiMessages);

    // Prepare tools
    final toolDefs = _buildToolDefinitions(settings, assistant, providerKey, modelId, hasBuiltInSearch);
    final onToolCall = toolDefs.isNotEmpty ? _buildToolCallHandler(settings, assistant) : null;

    // Build user image paths for API call (OCR mode strips images)
    final bool ocrActive = settings.ocrEnabled &&
        settings.ocrModelProvider != null &&
        settings.ocrModelId != null;
    final userImagePaths = ocrActive ? const <String>[] : lastUserImagePaths;

    // === Execute generation using shared method ===
    final ctx = stream_ctrl.GenerationContext(
      assistantMessage: assistantMessage,
      apiMessages: apiMessages,
      userImagePaths: userImagePaths,
      providerKey: providerKey,
      modelId: modelId,
      assistant: assistant,
      settings: settings,
      config: settings.getProviderConfig(providerKey),
      toolDefs: toolDefs,
      onToolCall: onToolCall,
      extraHeaders: _buildCustomHeaders(assistant),
      extraBody: _buildCustomBody(assistant),
      supportsReasoning: supportsReasoning,
      enableReasoning: enableReasoning,
      streamOutput: assistant?.streamOutput ?? true,
      generateTitleOnFinish: false, // Regenerate doesn't need title generation
    );

    await _executeGeneration(ctx);
  }

  Future<void> _maybeGenerateTitleFor(String conversationId, {bool force = false}) async {
    final convo = _chatService.getConversation(conversationId);
    if (convo == null) return;
    if (!force && convo.title.isNotEmpty && convo.title != _titleForLocale(context)) return;

    final settings = context.read<SettingsProvider>();
    final assistantProvider = context.read<AssistantProvider>();

    // Get assistant for this conversation
    final assistant = convo.assistantId != null
        ? assistantProvider.getById(convo.assistantId!)
        : assistantProvider.currentAssistant;

    // Decide model: prefer title model, else fall back to assistant's model, then to global default
    final provKey = settings.titleModelProvider
        ?? assistant?.chatModelProvider
        ?? settings.currentModelProvider;
    final mdlId = settings.titleModelId
        ?? assistant?.chatModelId
        ?? settings.currentModelId;
    if (provKey == null || mdlId == null) return;
    final cfg = settings.getProviderConfig(provKey);

    // Build content from messages (truncate to reasonable length)
    final msgs = _chatService.getMessages(convo.id);
    final tIndex = convo.truncateIndex;
    final List<ChatMessage> sourceAll = (tIndex >= 0 && tIndex <= msgs.length) ? msgs.sublist(tIndex) : msgs;
    final List<ChatMessage> source = _collapseVersions(sourceAll);
    final joined = source
        .where((m) => m.content.isNotEmpty)
        .map((m) => '${m.role == 'assistant' ? 'Assistant' : 'User'}: ${m.content}')
        .join('\n\n');
    final content = joined.length > 3000 ? joined.substring(0, 3000) : joined;
    final locale = Localizations.localeOf(context).toLanguageTag();

    String prompt = settings.titlePrompt
        .replaceAll('{locale}', locale)
        .replaceAll('{content}', content);

    try {
      final title = (await ChatApiService.generateText(config: cfg, modelId: mdlId, prompt: prompt)).trim();
      if (title.isNotEmpty) {
        await _chatService.renameConversation(convo.id, title);
        if (mounted && _currentConversation?.id == convo.id) {
          setState(() {
            _chatController.updateCurrentConversation(_chatService.getConversation(convo.id));
          });
        }
      }
    } catch (_) {
      // Ignore title generation failure silently
    }
  }

  bool _isNearBottom([double tolerance = _autoScrollSnapTolerance]) {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return (pos.maxScrollExtent - pos.pixels) <= tolerance;
  }

  void _refreshAutoStickToBottom() {
    try {
      final nearBottom = _isNearBottom();
      if (!nearBottom) {
        _autoStickToBottom = false;
      } else if (!_isUserScrolling) {
        final enabled = context.read<SettingsProvider>().autoScrollEnabled;
        if (enabled || _autoStickToBottom) {
          _autoStickToBottom = true;
        }
      }
    } catch (_) {}
  }

  void _autoScrollToBottomIfNeeded() {
    if (!mounted) return;
    final enabled = context.read<SettingsProvider>().autoScrollEnabled;
    if (!enabled && !_autoStickToBottom) return;
    _scheduleAutoScrollToBottom(force: false);
  }

  String? _currentStreamingMessageId() {
    for (int i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.role == 'assistant' && m.isStreaming) return m.id;
    }
    return null;
  }

  bool _shouldPinStreamingIndicator(String? messageId) {
    if (messageId == null) return false;
    if (_isUserScrolling) return false;
    if (!_scrollController.hasClients) return false;
    // Only pin when list is long enough to scroll; otherwise keep inline indicator
    if (_scrollController.position.maxScrollExtent < _autoScrollSnapTolerance) return false;
    // Only pin when near bottom to avoid covering content mid-scroll
    if (!_isNearBottom(48)) return false;
    return true;
  }

  Widget _buildPinnedStreamingIndicator() {
    final mid = _currentStreamingMessageId();
    final show = _shouldPinStreamingIndicator(mid);
    if (!show) return const SizedBox.shrink();
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: const LoadingIndicator(),
        ),
      ),
    );
  }

  void _scrollToBottom({bool animate = true}) {
    _autoStickToBottom = true;
    _scheduleAutoScrollToBottom(force: true, animate: animate);
  }

  void _scheduleAutoScrollToBottom({required bool force, bool animate = true}) {
    if (!force) {
      final enabled = context.read<SettingsProvider>().autoScrollEnabled;
      if (!enabled && !_autoStickToBottom) return;
    }
    _autoScrollForceNext = _autoScrollForceNext || force;
    _autoScrollAnimateNext = _autoScrollAnimateNext && animate;
    if (_autoScrollScheduled) return;
    _autoScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _autoScrollScheduled = false;
      final forceNow = _autoScrollForceNext;
      final animateNow = _autoScrollAnimateNext;
      _autoScrollForceNext = false;
      _autoScrollAnimateNext = true;
      await _animateToBottom(force: forceNow, animate: animateNow);
    });
  }

  Future<void> _animateToBottom({required bool force, bool animate = true}) async {
    try {
      if (!_scrollController.hasClients) return;
      if (!force) {
        if (_isUserScrolling) return;
        if (!_autoStickToBottom && !_isNearBottom()) return;
      }

      // Forced scrolls should jump immediately (no animation) to avoid visible slide when switching topics
      final bool doAnimate = (!force) && animate;
      // Prevent using controller while it is still attached to old/new list simultaneously
      if (_scrollController.positions.length != 1) {
        // Try again after microtask when the previous list detaches
        Future.microtask(() => _animateToBottom(force: force, animate: animate));
        return;
      }
      final pos = _scrollController.position;
      final max = pos.maxScrollExtent;
      final distance = (max - pos.pixels).abs();
      if (distance < 0.5) {
        if (_showJumpToBottom) {
          setState(() => _showJumpToBottom = false);
        }
        return;
      }
      if (!doAnimate) {
        pos.jumpTo(max);
      } else {
        final durationMs = distance < 36 ? 120 : distance < 140 ? 180 : 240;
        await pos.animateTo(
          max,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutCubic,
        );
      }
      if (_showJumpToBottom) {
        setState(() => _showJumpToBottom = false);
      }
      _autoStickToBottom = true;
    } catch (_) {}
  }

  void _forceScrollToBottom() {
    // Force scroll to bottom when user explicitly clicks the button
    _isUserScrolling = false;
    _userScrollTimer?.cancel();
    _lastJumpUserMessageId = null;
    _scrollToBottom();
  }

  // Force scroll after rebuilds when switching topics/conversations
  void _forceScrollToBottomSoon({bool animate = true}) {
    _isUserScrolling = false;
    _userScrollTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animate: animate));
    Future.delayed(_postSwitchScrollDelay, () => _scrollToBottom(animate: animate));
  }

  void _measureInputBar() {
    try {
      final ctx = _inputBarKey.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;
      final h = box.size.height;
      if ((_inputBarHeight - h).abs() > 1.0) {
        setState(() => _inputBarHeight = h);
      }
    } catch (_) {}
  }

  // Ensure scroll reaches bottom even after widget tree transitions
  void _scrollToBottomSoon({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animate: animate));
    Future.delayed(const Duration(milliseconds: 120), () => _scrollToBottom(animate: animate));
  }

  Future<void> _showQuickPhraseMenu() async {
    final assistant = context.read<AssistantProvider>().currentAssistant;
    final quickPhraseProvider = context.read<QuickPhraseProvider>();
    final globalPhrases = quickPhraseProvider.globalPhrases;
    final assistantPhrases = assistant != null
        ? quickPhraseProvider.getForAssistant(assistant.id)
        : <QuickPhrase>[];
    
    final allAvailable = [...globalPhrases, ...assistantPhrases];
    if (allAvailable.isEmpty) return;

    // Get input bar height for positioning menu above it
    final RenderBox? inputBox = _inputBarKey.currentContext?.findRenderObject() as RenderBox?;
    if (inputBox == null) return;
    
    final inputBarHeight = inputBox.size.height;
    final topLeft = inputBox.localToGlobal(Offset.zero);
    final position = Offset(topLeft.dx, inputBarHeight); // dx = global left, dy = input height
    
    // Dismiss keyboard before showing menu to prevent flickering
    _dismissKeyboard();
    
    QuickPhrase? selected;
    if (PlatformUtils.isDesktop) {
      selected = await showDesktopQuickPhrasePopover(context, anchorKey: _inputBarKey, phrases: allAvailable);
    } else {
      selected = await showQuickPhraseMenu(
        context: context,
        phrases: allAvailable,
        position: position,
      );
    }

    if (selected != null && mounted) {
      // Insert content at cursor position
      final text = _inputController.text;
      final selection = _inputController.selection;
      final start = (selection.start >= 0 && selection.start <= text.length) 
          ? selection.start 
          : text.length;
      final end = (selection.end >= 0 && selection.end <= text.length && selection.end >= start) 
          ? selection.end 
          : start;
      
      final newText = text.replaceRange(start, end, selected.content);
      _inputController.value = _inputController.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + selected.content.length),
        composing: TextRange.empty,
      );
      
      setState(() {});
      
      // Don't auto-refocus to prevent keyboard flickering on Android
      // User can tap input field if they want to continue typing
    }
  }

  // Scroll to a specific message id (from mini map selection)
  Future<void> _scrollToMessageId(String targetId) async {
    try {
      if (!mounted || !_scrollController.hasClients) return;
      final messages = _collapseVersions(_messages);
      final tIndex = messages.indexWhere((m) => m.id == targetId);
      if (tIndex < 0) return;

      // Try direct ensureVisible first
      final tKey = _messageKeys[targetId];
      final tCtx = tKey?.currentContext;
      if (tCtx != null) {
        await Scrollable.ensureVisible(
          tCtx,
          alignment: 0.1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        _lastJumpUserMessageId = targetId; // allow chaining with prev-question
        return;
      }

      // Coarse jump based on index ratio to bring target into build range
      final pos0 = _scrollController.position;
      final denom = (messages.length - 1).clamp(1, 1 << 30);
      final ratio = tIndex / denom;
      final coarse = (pos0.maxScrollExtent * ratio).clamp(0.0, pos0.maxScrollExtent);
      _scrollController.jumpTo(coarse);
      await WidgetsBinding.instance.endOfFrame;
      final tCtxAfterCoarse = _messageKeys[targetId]?.currentContext;
      if (tCtxAfterCoarse != null) {
        await Scrollable.ensureVisible(tCtxAfterCoarse, alignment: 0.1, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
        _lastJumpUserMessageId = targetId;
        return;
      }

      // Determine direction using visible anchor indices
      final media = MediaQuery.of(context);
      final double listTop = kToolbarHeight + media.padding.top;
      final double listBottom = media.size.height - media.padding.bottom - _inputBarHeight - 8;
      int? firstVisibleIdx;
      int? lastVisibleIdx;
      for (int i = 0; i < messages.length; i++) {
        final key = _messageKeys[messages[i].id];
        final ctx = key?.currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null || !box.attached) continue;
        final top = box.localToGlobal(Offset.zero).dy;
        final bottom = top + box.size.height;
        final visible = bottom > listTop && top < listBottom;
        if (visible) {
          firstVisibleIdx ??= i;
          lastVisibleIdx = i;
        }
      }
      final anchor = lastVisibleIdx ?? firstVisibleIdx ?? 0;
      final dirDown = tIndex > anchor; // target below

      // Page in steps until the target builds, then ensureVisible
      const int maxAttempts = 40;
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        final ctx2 = _messageKeys[targetId]?.currentContext;
        if (ctx2 != null) {
          await Scrollable.ensureVisible(
            ctx2,
            alignment: 0.1,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutCubic,
          );
          _lastJumpUserMessageId = targetId;
          return;
        }
        final pos = _scrollController.position;
        final viewH = media.size.height;
        final step = viewH * 0.85 * (dirDown ? 1 : -1);
        double newOffset = pos.pixels + step;
        if (newOffset < 0) newOffset = 0;
        if (newOffset > pos.maxScrollExtent) newOffset = pos.maxScrollExtent;
        if ((newOffset - pos.pixels).abs() < 1) break;
        _scrollController.jumpTo(newOffset);
        await WidgetsBinding.instance.endOfFrame;
      }
    } catch (_) {}
  }

  // Jump to the previous user message (question) above the current viewport
  Future<void> _jumpToPreviousQuestion() async {
    try {
      if (!mounted || !_scrollController.hasClients) return;
      final messages = _collapseVersions(_messages);
      if (messages.isEmpty) return;
      // Build an id->index map for quick lookup
      final Map<String, int> idxById = <String, int>{};
      for (int i = 0; i < messages.length; i++) { idxById[messages[i].id] = i; }

      // Determine anchor index: prefer last jumped user; otherwise bottom-most visible item
      int? anchor;
      if (_lastJumpUserMessageId != null && idxById.containsKey(_lastJumpUserMessageId)) {
        anchor = idxById[_lastJumpUserMessageId!];
      } else {
        final media = MediaQuery.of(context);
        final double listTop = kToolbarHeight + media.padding.top;
        final double listBottom = media.size.height - media.padding.bottom - _inputBarHeight - 8;
        int? firstVisibleIdx;
        int? lastVisibleIdx;
        for (int i = 0; i < messages.length; i++) {
          final key = _messageKeys[messages[i].id];
          final ctx = key?.currentContext;
          if (ctx == null) continue;
          final box = ctx.findRenderObject() as RenderBox?;
          if (box == null || !box.attached) continue;
          final top = box.localToGlobal(Offset.zero).dy;
          final bottom = top + box.size.height;
          final visible = bottom > listTop && top < listBottom;
          if (visible) {
            firstVisibleIdx ??= i;
            lastVisibleIdx = i;
          }
        }
        anchor = lastVisibleIdx ?? firstVisibleIdx ?? (messages.length - 1);
      }
      // Search backward for previous user message from the anchor index
      int target = -1;
      for (int i = (anchor ?? 0) - 1; i >= 0; i--) {
        if (messages[i].role == 'user') { target = i; break; }
      }
      if (target < 0) {
        // No earlier user message; jump to top instantly
        _scrollController.jumpTo(0.0);
        _lastJumpUserMessageId = null;
        return;
      }
      // If target widget is not built yet (off-screen far above), page up until it is
      const int maxAttempts = 12; // about 10 pages max
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        final tKey = _messageKeys[messages[target].id];
        final tCtx = tKey?.currentContext;
        if (tCtx != null) {
          await Scrollable.ensureVisible(
            tCtx,
            alignment: 0.08,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutCubic,
          );
          _lastJumpUserMessageId = messages[target].id;
          return;
        }
        // Step up by ~85% of viewport height
        final pos = _scrollController.position;
        final viewH = MediaQuery.of(context).size.height;
        final step = viewH * 0.85;
        final newOffset = (pos.pixels - step) < 0 ? 0.0 : (pos.pixels - step);
        if ((pos.pixels - newOffset).abs() < 1) break; // reached top
        _scrollController.jumpTo(newOffset);
        // Let the list build newly visible children
        await WidgetsBinding.instance.endOfFrame;
      }
      // Final fallback: go to top if still not found
      _scrollController.jumpTo(0.0);
      _lastJumpUserMessageId = null;
    } catch (_) {}
  }

  // Edit message and optionally resend immediately
  Future<void> _onEditMessage(ChatMessage message) async {
    final isDesktop = _isDesktopPlatform;
    final MessageEditResult? result = isDesktop
        ? await showMessageEditDesktopDialog(context, message: message)
        : await showMessageEditSheet(context, message: message);
    if (result == null) return;

    final newMsg = await _chatService.appendMessageVersion(messageId: message.id, content: result.content);
    if (!mounted || newMsg == null) return;

    setState(() {
      _messages.add(newMsg);
      final gid = (newMsg.groupId ?? newMsg.id);
      _versionSelections[gid] = newMsg.version;
    });
    if (_currentConversation != null) {
      try {
        final gid = (newMsg.groupId ?? newMsg.id);
        await _chatService.setSelectedVersion(_currentConversation!.id, gid, newMsg.version);
      } catch (_) {}
    }

    if (!mounted || !result.shouldSend) return;
    if (message.role == 'assistant') {
      await _regenerateAtMessage(newMsg, assistantAsNewReply: true);
    } else {
      await _regenerateAtMessage(newMsg);
    }
  }

  // Translate message functionality
  Future<void> _translateMessage(ChatMessage message) async {
    final l10n = AppLocalizations.of(context)!;

    final result = await _translationService.translateMessage(
      message: message,
      onTranslationStarted: () {
        // Set loading state and initialize translation data (called after language selection)
        final loadingMessage = message.copyWith(translation: l10n.homePageTranslating);
        setState(() {
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _messages[index] = loadingMessage;
          }
          // Initialize translation state with expanded
          _translations[message.id] = _TranslationData();
        });
      },
      onTranslationUpdate: (translation) {
        final updatingMessage = message.copyWith(translation: translation);
        setState(() {
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _messages[index] = updatingMessage;
          }
        });
      },
      onTranslationCleared: () {
        final clearedMessage = message.copyWith(translation: '');
        setState(() {
          final index = _messages.indexWhere((m) => m.id == message.id);
          if (index != -1) {
            _messages[index] = clearedMessage;
          }
          _translations.remove(message.id);
        });
      },
    );

    // Handle result
    if (result.isCancelled) {
      // User cancelled, no state change needed
      return;
    }

    if (result.type == TranslationResultType.noModelConfigured) {
      showAppSnackBar(
        context,
        message: l10n.homePagePleaseSetupTranslateModel,
        type: NotificationType.warning,
      );
      return;
    }

    if (result.type == TranslationResultType.error) {
      showAppSnackBar(
        context,
        message: l10n.homePageTranslateFailed(result.errorMessage ?? ''),
        type: NotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tablet and larger: fixed side panel + constrained content
    final width = MediaQuery.sizeOf(context).width;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final assistant = context.watch<AssistantProvider>().currentAssistant;

    // Use unified helper to get model display info
    final modelInfo = getModelDisplayInfo(settings, assistant: assistant);

    final title = ((_currentConversation?.title ?? '').trim().isNotEmpty)
        ? _currentConversation!.title
        : _titleForLocale(context);

    if (width >= AppBreakpoints.tablet) {
      return _buildTabletLayout(
        context,
        title: title,
        providerName: modelInfo.providerName,
        modelDisplay: modelInfo.modelDisplay,
        cs: cs,
      );
    }

    // Use mobile layout scaffold
    return HomeMobileScaffold(
      scaffoldKey: _scaffoldKey,
      drawerController: _drawerController,
      assistantPickerCloseTick: _assistantPickerCloseTick,
      loadingConversationIds: _loadingConversationIds,
      title: title,
      providerName: modelInfo.providerName,
      modelDisplay: modelInfo.modelDisplay,
      onToggleDrawer: () => _drawerController.toggle(),
      onDismissKeyboard: _dismissKeyboard,
      onSelectConversation: (id) {
        _switchConversationAnimated(id);
      },
      onNewConversation: () async {
        await _createNewConversationAnimated();
      },
      onOpenMiniMap: () async {
        final collapsed = _collapseVersions(_messages);
        String? selectedId;
        if (PlatformUtils.isDesktop) {
          selectedId = await showDesktopMiniMapPopover(context, anchorKey: _inputBarKey, messages: collapsed);
        } else {
          selectedId = await showMiniMapSheet(context, collapsed);
        }
        if (!mounted) return;
        if (selectedId != null && selectedId.isNotEmpty) {
          await _scrollToMessageId(selectedId);
        }
      },
      onCreateNewConversation: () async {
        await _createNewConversationAnimated();
        if (mounted) {
          _forceScrollToBottomSoon(animate: false);
        }
      },
      onSelectModel: () => showModelSelectSheet(context),
      body: _wrapWithDropTarget(Stack(
          children: [
            // Assistant-specific chat background + gradient overlay to improve readability
            Builder(
              builder: (context) {
              final bg = context.watch<AssistantProvider>().currentAssistant?.background;
              final maskStrength = context.watch<SettingsProvider>().chatBackgroundMaskStrength;
            if (bg == null || bg.trim().isEmpty) return const SizedBox.shrink();
            ImageProvider provider;
            if (bg.startsWith('http')) {
              provider = NetworkImage(bg);
            } else {
              final localPath = SandboxPathResolver.fix(bg);
              final file = File(localPath);
              if (!file.existsSync()) return const SizedBox.shrink();
              provider = FileImage(file);
            }
            return Positioned.fill(
              child: Stack(
                children: [
                  // Background image
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: provider,
                          fit: BoxFit.cover,
                          colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.04), BlendMode.srcATop),
                        ),
                      ),
                    ),
                  ),
                  // Vertical gradient overlay (top ~20% -> bottom ~50%) using theme background color
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: () {
                              final top = (0.20 * maskStrength).clamp(0.0, 1.0);
                              final bottom = (0.50 * maskStrength).clamp(0.0, 1.0);
                              return [
                                cs.background.withOpacity(top),
                                cs.background.withOpacity(bottom),
                              ];
                            }(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          // Main column content
          Padding(
            padding: EdgeInsets.only(top: kToolbarHeight + MediaQuery.of(context).padding.top),
            child: Column(
            children: [
              // Chat messages list (animate when switching topic)
              Expanded(
                child: Builder(
                    builder: (context) {
                      final __content = KeyedSubtree(
                        key: ValueKey<String>(_currentConversation?.id ?? 'none'),
                        child: _buildMessageListView(
                          context,
                          dividerPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: AppSpacing.md),
                        ),
                      );
                      final isAndroid = Theme.of(context).platform == TargetPlatform.android;
                      Widget w = __content;
                      if (!isAndroid) {
                        w = w
                            .animate(key: ValueKey('mob_body_'+(_currentConversation?.id ?? 'none')))
                            .fadeIn(duration: 200.ms, curve: Curves.easeOutCubic);
                            // .slideY(begin: 0.02, end: 0, duration: 240.ms, curve: Curves.easeOutCubic);
                        w = FadeTransition(opacity: _convoFade, child: w);
                      }
                      return w;
                    },
                  ),
              ),
              // Input bar
              NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (n) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _measureInputBar());
                  return false;
                },
                child: SizeChangedLayoutNotifier(
                  child: Builder(
                    builder: (context) => _buildChatInputBar(context, isTablet: false),
                  ),
                ),
              ),
            ],
            ),
          ),

          // Selection toolbar overlay (above input bar) with iOS glass capsule + animations
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                // Move higher: 72 + 12 + 38
                padding: const EdgeInsets.only(bottom: 122),
                child: _AnimatedSelectionBar(
                  visible: _selecting,
                  child: _SelectionToolbar(
                    onCancel: () {
                      setState(() {
                        _selecting = false;
                        _selectedItems.clear();
                      });
                    },
                    onConfirm: () async {
                      final convo = _currentConversation;
                      if (convo == null) return;
                      final collapsed = _collapseVersions(_messages);
                      final selected = <ChatMessage>[];
                      for (final m in collapsed) {
                        if (_selectedItems.contains(m.id)) selected.add(m);
                      }
                      if (selected.isEmpty) {
                        final l10n = AppLocalizations.of(context)!;
                        showAppSnackBar(
                          context,
                          message: l10n.homePageSelectMessagesToShare,
                          type: NotificationType.info,
                        );
                        return;
                      }
                      setState(() { _selecting = false; });
                      await showChatExportSheet(context, conversation: convo, selectedMessages: selected);
                      if (mounted) setState(() { _selectedItems.clear(); });
                    },
                  ),
                ),
              ),
            ),
          ),

          // Scroll-to-bottom button (bottom-right, above input bar)
          Builder(builder: (context) {
            final showSetting = context.watch<SettingsProvider>().showMessageNavButtons;
            if (!showSetting || _messages.isEmpty) return const SizedBox.shrink();
            return _GlassyScrollButton(
              icon: Lucide.ChevronDown,
              onTap: _forceScrollToBottom,
              bottomOffset: _inputBarHeight + 12,
              visible: _showJumpToBottom,
            );
          }),

          // Scroll-to-previous-question button (stacked above the bottom button)
          Builder(builder: (context) {
            final showSetting = context.watch<SettingsProvider>().showMessageNavButtons;
            if (!showSetting || _messages.isEmpty) return const SizedBox.shrink();
            return _GlassyScrollButton(
              icon: Lucide.ChevronUp,
              onTap: _jumpToPreviousQuestion,
              bottomOffset: _inputBarHeight + 12 + 52, // place above the bottom button with gap
              visible: _showJumpToBottom,
            );
          }),
        ],
      )),
    );
  }

  /// Builds the context divider widget shown at truncate position.
  Widget _buildContextDivider(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final label = l10n.homePageClearContext;
    return Row(
      children: [
        Expanded(child: Divider(color: cs.outlineVariant.withOpacity(0.6), height: 1, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
        ),
        Expanded(child: Divider(color: cs.outlineVariant.withOpacity(0.6), height: 1, thickness: 1)),
      ],
    );
  }

  /// Handles message deletion with confirmation dialog and version selection adjustment.
  Future<void> _handleDeleteMessage(
    BuildContext context,
    ChatMessage message,
    Map<String, List<ChatMessage>> byGroup,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.homePageDeleteMessage),
        content: Text(l10n.homePageDeleteMessageConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.homePageCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.homePageDelete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final id = message.id;
    final gid = (message.groupId ?? message.id);
    // Compute selection adjustment before removal
    final versBefore = (byGroup[gid] ?? const <ChatMessage>[])..sort((a, b) => a.version.compareTo(b.version));
    final oldSel = _versionSelections[gid] ?? (versBefore.isNotEmpty ? versBefore.length - 1 : 0);
    final delIndex = versBefore.indexWhere((m) => m.id == id);
    setState(() {
      _reasoning.remove(id);
      _translations.remove(id);
      _toolParts.remove(id);
      _reasoningSegments.remove(id);
      // Adjust selected version index for this group
      final newTotal = versBefore.length - 1;
      if (newTotal <= 0) {
        _versionSelections.remove(gid);
      } else {
        int newSel = oldSel;
        if (delIndex >= 0) {
          if (delIndex < oldSel) newSel = oldSel - 1;
          else if (delIndex == oldSel) newSel = (oldSel > 0) ? oldSel - 1 : 0;
        }
        if (newSel < 0) newSel = 0;
        if (newSel > newTotal - 1) newSel = newTotal - 1;
        _versionSelections[gid] = newSel;
      }
    });
    // Persist updated selection if group still exists
    final sel = _versionSelections[gid];
    if (sel != null && _currentConversation != null) {
      try { await _chatService.setSelectedVersion(_currentConversation!.id, gid, sel); } catch (_) {}
    }
    await _chatService.deleteMessage(id);
    if (!mounted || _currentConversation == null) return;
    setState(() {
      _chatController.reloadMessages();
    });
  }

  /// Handles forking conversation at a specific message.
  Future<void> _handleForkConversation(BuildContext context, ChatMessage message) async {
    // Determine included groups up to the message's group (inclusive)
    final Map<String, int> groupFirstIndex = <String, int>{};
    final List<String> groupOrder = <String>[];
    for (int i = 0; i < _messages.length; i++) {
      final gid0 = (_messages[i].groupId ?? _messages[i].id);
      if (!groupFirstIndex.containsKey(gid0)) {
        groupFirstIndex[gid0] = i;
        groupOrder.add(gid0);
      }
    }
    final targetGroup = (message.groupId ?? message.id);
    final targetOrderIndex = groupOrder.indexOf(targetGroup);
    if (targetOrderIndex < 0) return;

    final includeGroups = groupOrder.take(targetOrderIndex + 1).toSet();
    final selected = [
      for (final m in _messages)
        if (includeGroups.contains(m.groupId ?? m.id)) m
    ];
    // Filter version selections to included groups
    final sel = <String, int>{};
    for (final gid in includeGroups) {
      final v = _versionSelections[gid];
      if (v != null) sel[gid] = v;
    }
    final newConvo = await _chatService.forkConversation(
      title: _titleForLocale(context),
      assistantId: _currentConversation?.assistantId,
      sourceMessages: selected,
      versionSelections: sel,
    );
    // Switch to the new conversation; skip fade on desktop for instant switch
    if (!mounted) return;
    if (!_isDesktopPlatform) {
      await _convoFadeController.reverse();
    }
    _chatService.setCurrentConversation(newConvo.id);
    if (!mounted) return;
    setState(() {
      _chatController.setCurrentConversation(newConvo);
      _restoreMessageUiState();
    });
    try { await WidgetsBinding.instance.endOfFrame; } catch (_) {}
    _scrollToBottom(animate: false);
    if (!_isDesktopPlatform) {
      await _convoFadeController.forward();
    }
  }

  /// Handles entering share/selection mode with messages up to the specified index.
  void _handleShareMessage(int messageIndex, List<ChatMessage> messages) {
    setState(() {
      _selecting = true;
      _selectedItems.clear();
      for (int i = 0; i <= messageIndex && i < messages.length; i++) {
        final m = messages[i];
        final enabled = (m.role == 'user' || m.role == 'assistant');
        if (enabled) _selectedItems.add(m.id);
      }
    });
  }

  /// Handles TTS speak/stop for a message.
  Future<void> _handleSpeak(BuildContext context, ChatMessage message) async {
    if (PlatformUtils.isDesktopTarget) {
      final sp = context.read<SettingsProvider>();
      final hasNetworkTts = sp.ttsServiceSelected >= 0 && sp.ttsServices.isNotEmpty;
      if (!hasNetworkTts) {
        showAppSnackBar(
          context,
          message: AppLocalizations.of(context)!.desktopTtsPleaseAddProvider,
          type: NotificationType.warning,
        );
        return;
      }
    }
    final tts = context.read<TtsProvider>();
    if (!tts.isSpeaking) {
      await tts.speak(message.content);
    } else {
      await tts.stop();
    }
  }

  /// Builds the message list view shared by both mobile and tablet layouts.
  ///
  /// This method extracts the common ListView.builder logic to reduce code duplication.
  /// The [dividerPadding] parameter allows for slight styling differences between layouts.
  Widget _buildMessageListView(
    BuildContext context, {
    required EdgeInsetsGeometry dividerPadding,
  }) {
    // Stable snapshot for this build (collapse versions)
    final messages = _collapseVersions(_messages);
    final Map<String, List<ChatMessage>> byGroup = <String, List<ChatMessage>>{};
    for (final m in _messages) {
      final gid = (m.groupId ?? m.id);
      byGroup.putIfAbsent(gid, () => <ChatMessage>[]).add(m);
    }
    // Map persisted truncateIndex (raw message count) to collapsed index
    final int truncRaw = _currentConversation?.truncateIndex ?? -1;
    int truncCollapsed = -1;
    if (truncRaw > 0) {
      final seen = <String>{};
      final int limit = truncRaw < _messages.length ? truncRaw : _messages.length;
      int count = 0;
      for (int i = 0; i < limit; i++) {
        final gid0 = (_messages[i].groupId ?? _messages[i].id);
        if (seen.add(gid0)) count++;
      }
      truncCollapsed = count - 1;
    }
    final pinnedId = _currentStreamingMessageId();
    final pinActive = _shouldPinStreamingIndicator(pinnedId);
    final list = ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(bottom: pinActive ? 28 : 16, top: 8),
      itemCount: messages.length,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemBuilder: (context, index) {
        if (index < 0 || index >= messages.length) {
          return const SizedBox.shrink();
        }
        final message = messages[index];
        final r = _reasoning[message.id];
        final t = _translations[message.id];
        final chatScale = context.watch<SettingsProvider>().chatFontScale;
        final assistant = context.watch<AssistantProvider>().currentAssistant;
        final useAssist = assistant?.useAssistantAvatar == true;
        final showDivider = truncCollapsed >= 0 && index == truncCollapsed;
        final gid = (message.groupId ?? message.id);
        final vers = (byGroup[gid] ?? const <ChatMessage>[]).toList()..sort((a,b)=>a.version.compareTo(b.version));
        int selectedIdx = _versionSelections[gid] ?? (vers.isNotEmpty ? vers.length - 1 : 0);
        final total = vers.length;
        if (selectedIdx < 0) selectedIdx = 0;
        if (total > 0 && selectedIdx > total - 1) selectedIdx = total - 1;
        final showMsgNav = context.watch<SettingsProvider>().showMessageNavButtons;
        final effectiveTotal = showMsgNav ? total : 1;
        final effectiveIndex = showMsgNav ? selectedIdx : 0;

        return Column(
          key: _keyForMessage(message.id),
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selecting && (message.role == 'user' || message.role == 'assistant'))
                  Padding(
                    padding: const EdgeInsets.only(left: 10, right: 6),
                    child: IosCheckbox(
                      value: _selectedItems.contains(message.id),
                      onChanged: (v) {
                        setState(() {
                          if (v) {
                            _selectedItems.add(message.id);
                          } else {
                            _selectedItems.remove(message.id);
                          }
                        });
                      },
                    ),
                  ),
                Expanded(
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaleFactor: MediaQuery.of(context).textScaleFactor * chatScale,
                    ),
                    child: ChatMessageWidget(
                      message: message,
                      versionIndex: effectiveIndex,
                      versionCount: effectiveTotal,
                      onPrevVersion: (showMsgNav && selectedIdx > 0) ? () async {
                        final next = selectedIdx - 1;
                        _versionSelections[gid] = next;
                        await _chatService.setSelectedVersion(_currentConversation!.id, gid, next);
                        if (mounted) setState(() {});
                      } : null,
                      onNextVersion: (showMsgNav && selectedIdx < total - 1) ? () async {
                        final next = selectedIdx + 1;
                        _versionSelections[gid] = next;
                        await _chatService.setSelectedVersion(_currentConversation!.id, gid, next);
                        if (mounted) setState(() {});
                      } : null,
                      modelIcon: (!useAssist && message.role == 'assistant' && message.providerId != null && message.modelId != null)
                          ? _CurrentModelIcon(providerKey: message.providerId, modelId: message.modelId, size: 30)
                          : null,
                      showModelIcon: useAssist ? false : context.watch<SettingsProvider>().showModelIcon,
                      useAssistantAvatar: useAssist && message.role == 'assistant',
                      assistantName: useAssist ? (assistant?.name ?? 'Assistant') : null,
                      assistantAvatar: useAssist ? (assistant?.avatar ?? '') : null,
                      showUserAvatar: context.watch<SettingsProvider>().showUserAvatar,
                      showTokenStats: context.watch<SettingsProvider>().showTokenStats,
                      hideStreamingIndicator: pinActive && (message.id == pinnedId),
                      reasoningText: (message.role == 'assistant') ? (r?.text ?? '') : null,
                      reasoningExpanded: (message.role == 'assistant') ? (r?.expanded ?? false) : false,
                      reasoningLoading: (message.role == 'assistant') ? (r?.finishedAt == null && (r?.text.isNotEmpty == true)) : false,
                      reasoningStartAt: (message.role == 'assistant') ? r?.startAt : null,
                      reasoningFinishedAt: (message.role == 'assistant') ? r?.finishedAt : null,
                      onToggleReasoning: (message.role == 'assistant' && r != null)
                          ? () {
                              setState(() {
                                r.expanded = !r.expanded;
                              });
                            }
                          : null,
                      translationExpanded: t?.expanded ?? true,
                      onToggleTranslation: (message.translation != null && message.translation!.isNotEmpty && t != null)
                          ? () {
                              setState(() {
                                t.expanded = !t.expanded;
                              });
                            }
                          : null,
                      onRegenerate: message.role == 'assistant' ? () { _regenerateAtMessage(message); } : null,
                      onResend: message.role == 'user' ? () { _regenerateAtMessage(message); } : null,
                      onTranslate: message.role == 'assistant'
                          ? () {
                              _translateMessage(message);
                            }
                          : null,
                      onSpeak: message.role == 'assistant'
                          ? () => _handleSpeak(context, message)
                          : null,
                      onEdit: (message.role == 'user' || message.role == 'assistant')
                          ? () { _onEditMessage(message); }
                          : null,
                      onDelete: message.role == 'user'
                          ? () => _handleDeleteMessage(context, message, byGroup)
                          : null,
                      onMore: () async {
                        final action = await showMessageMoreSheet(context, message);
                        if (!mounted) return;
                        if (action == MessageMoreAction.delete) {
                          await _handleDeleteMessage(context, message, byGroup);
                        } else if (action == MessageMoreAction.edit) {
                          await _onEditMessage(message);
                        } else if (action == MessageMoreAction.fork) {
                          await _handleForkConversation(context, message);
                        } else if (action == MessageMoreAction.share) {
                          _handleShareMessage(index, messages);
                        }
                      },
                      toolParts: message.role == 'assistant' ? _toolParts[message.id] : null,
                      reasoningSegments: message.role == 'assistant'
                          ? (() {
                              final segments = _reasoningSegments[message.id];
                              if (segments == null || segments.isEmpty) return null;
                              return segments
                                  .map((s) => ReasoningSegment(
                                        text: s.text,
                                        expanded: s.expanded,
                                        loading: s.finishedAt == null && s.text.isNotEmpty,
                                        startAt: s.startAt,
                                        finishedAt: s.finishedAt,
                                        onToggle: () {
                                          setState(() {
                                            s.expanded = !s.expanded;
                                          });
                                        },
                                        toolStartIndex: s.toolStartIndex,
                                      ))
                                  .toList();
                            })()
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            if (showDivider)
              Padding(
                padding: dividerPadding,
                child: _buildContextDivider(context),
              ),
          ],
        );
      },
    );
    return Stack(
      children: [
        list,
        if (pinActive) _buildPinnedStreamingIndicator(),
      ],
    );
  }

  /// Builds the ChatInputBar widget with common parameters.
  /// [isTablet] determines whether to include tablet-specific features like
  /// mini map, learning mode, camera/photos pickers, and file upload.
  Widget _buildChatInputBar(BuildContext context, {required bool isTablet}) {
    final settings = context.watch<SettingsProvider>();
    final ap = context.watch<AssistantProvider>();
    final a = ap.currentAssistant;
    final assistantId = a?.id;

    // Use unified helper to get model identifiers
    final modelIds = getActiveModelIds(settings, assistant: a);
    final pk = modelIds.providerKey;
    final mid = modelIds.modelId;

    // Enforce model capabilities: disable MCP selection if model doesn't support tools
    if (pk != null && mid != null) {
      final supportsTools = _isToolModel(pk, mid);
      if (!supportsTools && (a?.mcpServerIds.isNotEmpty ?? false)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final aa = ap.currentAssistant;
          if (aa != null && aa.mcpServerIds.isNotEmpty) {
            ap.updateAssistant(aa.copyWith(mcpServerIds: const <String>[]));
          }
        });
      }
      final supportsReasoning = _isReasoningModel(pk, mid);
      if (!supportsReasoning && a != null) {
        final enabledNow = _isReasoningEnabled(a.thinkingBudget ?? settings.thinkingBudget);
        if (enabledNow) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final aa = ap.currentAssistant;
            if (aa != null) {
              await ap.updateAssistant(aa.copyWith(thinkingBudget: 0));
            }
          });
        }
      }
    }

    // Compute whether built-in search (Gemini incl. Vertex or Claude) is active to highlight the search button
    final cfg = getActiveProviderConfig(settings, assistant: a);
    bool builtinSearchActive = false;
    if (cfg != null && mid != null) {
      final isGemini = cfg.providerType == ProviderKind.google;
      final isClaude = cfg.providerType == ProviderKind.claude;
      final isOpenAIResponses = cfg.providerType == ProviderKind.openai && (cfg.useResponseApi == true);
      if (isGemini || isClaude || isOpenAIResponses) {
        final ov = cfg.modelOverrides[mid] as Map?;
        final list = (ov?['builtInTools'] as List?) ?? const <dynamic>[];
        builtinSearchActive = list.map((e) => e.toString().toLowerCase()).contains('search');
      }
    }

    final isDesktop = PlatformUtils.isDesktopTarget;

    return ChatInputBar(
      key: _inputBarKey,
      onMore: _toggleTools,
      searchEnabled: context.watch<SettingsProvider>().searchEnabled || builtinSearchActive,
      onToggleSearch: (enabled) {
        context.read<SettingsProvider>().setSearchEnabled(enabled);
      },
      onSelectModel: () => showModelSelectSheet(context),
      onLongPressSelectModel: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProvidersPage()),
        );
      },
      onOpenMcp: () {
        final a = context.read<AssistantProvider>().currentAssistant;
        if (a != null) {
          if (PlatformUtils.isDesktop) {
            showDesktopMcpServersPopover(context, anchorKey: _inputBarKey, assistantId: a.id);
          } else {
            showAssistantMcpSheet(context, assistantId: a.id);
          }
        }
      },
      onLongPressMcp: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const McpPage()),
        );
      },
      onStop: _cancelStreaming,
      modelIcon: (settings.showModelIcon && pk != null && mid != null)
          ? _CurrentModelIcon(
              providerKey: pk,
              modelId: mid,
              size: 40,
              withBackground: true,
              backgroundColor: Colors.transparent,
            )
          : null,
      focusNode: _inputFocus,
      controller: _inputController,
      mediaController: _mediaController,
      onConfigureReasoning: () async {
        final assistant = context.read<AssistantProvider>().currentAssistant;
        if (assistant != null) {
          if (assistant.thinkingBudget != null) {
            context.read<SettingsProvider>().setThinkingBudget(assistant.thinkingBudget);
          }
          await _openReasoningSettings();
          final chosen = context.read<SettingsProvider>().thinkingBudget;
          await context.read<AssistantProvider>().updateAssistant(
            assistant.copyWith(thinkingBudget: chosen),
          );
        }
      },
      reasoningActive: _isReasoningEnabled((context.watch<AssistantProvider>().currentAssistant?.thinkingBudget) ?? settings.thinkingBudget),
      supportsReasoning: (pk != null && mid != null) ? _isReasoningModel(pk, mid) : false,
      onOpenSearch: _openSearchSettings,
      onSend: (text) {
        _sendMessage(text);
        _inputController.clear();
        // Keep focus on desktop; only dismiss on mobile to hide soft keyboard
        if (PlatformUtils.isMobile) {
          _dismissKeyboard();
        } else {
          _inputFocus.requestFocus();
        }
      },
      loading: _isCurrentConversationLoading,
      showMcpButton: (() {
        final pk2 = a?.chatModelProvider ?? settings.currentModelProvider;
        final mid3 = a?.chatModelId ?? settings.currentModelId;
        if (pk2 == null || mid3 == null) return false;
        final hasEnabledMcp = context.watch<McpProvider>().hasAnyEnabled;
        return _isToolModel(pk2, mid3) && hasEnabledMcp;
      })(),
      mcpActive: (() {
        final a = context.watch<AssistantProvider>().currentAssistant;
        final connected = context.watch<McpProvider>().connectedServers;
        final selected = a?.mcpServerIds ?? const <String>[];
        if (selected.isEmpty || connected.isEmpty) return false;
        return connected.any((s) => selected.contains(s.id));
      })(),
      showQuickPhraseButton: (() {
        final assistant = context.watch<AssistantProvider>().currentAssistant;
        final quickPhraseProvider = context.watch<QuickPhraseProvider>();
        final globalCount = quickPhraseProvider.globalPhrases.length;
        final assistantCount = assistant != null
            ? quickPhraseProvider.getForAssistant(assistant.id).length
            : 0;
        return (globalCount + assistantCount) > 0;
      })(),
      onQuickPhrase: _showQuickPhraseMenu,
      onLongPressQuickPhrase: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QuickPhrasesPage()),
        );
      },
      // OCR button: show on desktop for mobile layout, always check settings for tablet layout
      showOcrButton: isTablet
          ? (settings.ocrModelProvider != null && settings.ocrModelId != null)
          : (isDesktop && settings.ocrModelProvider != null && settings.ocrModelId != null),
      ocrActive: settings.ocrEnabled,
      onToggleOcr: () async {
        final sp = context.read<SettingsProvider>();
        await sp.setOcrEnabled(!sp.ocrEnabled);
      },
      // Tablet-specific parameters
      showMiniMapButton: isTablet,
      onOpenMiniMap: isTablet ? () async {
        final collapsed = _collapseVersions(_messages);
        String? selectedId;
        if (PlatformUtils.isDesktop) {
          selectedId = await showDesktopMiniMapPopover(context, anchorKey: _inputBarKey, messages: collapsed);
        } else {
          selectedId = await showMiniMapSheet(context, collapsed);
        }
        if (selectedId != null && selectedId.isNotEmpty) {
          await _scrollToMessageId(selectedId);
        }
      } : null,
      onPickCamera: isTablet ? (isDesktop ? null : _onPickCamera) : null,
      onPickPhotos: isTablet ? (isDesktop ? null : _onPickPhotos) : null,
      onUploadFiles: isTablet ? _onPickFiles : null,
      onToggleLearningMode: isTablet ? _openInstructionInjectionPopover : null,
      onLongPressLearning: isTablet ? _showLearningPromptSheet : null,
      learningModeActive: isTablet
          ? context.watch<InstructionInjectionProvider>().activeIdsFor(assistantId).isNotEmpty
          : false,
      showMoreButton: !isTablet,
      onClearContext: isTablet ? _onClearContext : null,
    );
  }

  Widget _buildTabletLayout(
    BuildContext context, {
    required String title,
    required String? providerName,
    required String? modelDisplay,
    required ColorScheme cs,
  }) {
    if (PlatformUtils.isDesktopTarget && !_desktopUiInited) {
      _desktopUiInited = true;
      try {
        final sp = context.read<SettingsProvider>();
        _embeddedSidebarWidth = sp.desktopSidebarWidth.clamp(_sidebarMinWidth, _sidebarMaxWidth);
        _tabletSidebarOpen = sp.desktopSidebarOpen;
        _rightSidebarOpen = sp.desktopRightSidebarOpen;
        _rightSidebarWidth = sp.desktopRightSidebarWidth.clamp(_sidebarMinWidth, _sidebarMaxWidth);
      } catch (_) {}
    }

    // Use desktop layout scaffold
    return HomeDesktopScaffold(
      scaffoldKey: _scaffoldKey,
      assistantPickerCloseTick: _assistantPickerCloseTick,
      loadingConversationIds: _loadingConversationIds,
      title: title,
      providerName: providerName,
      modelDisplay: modelDisplay,
      tabletSidebarOpen: _tabletSidebarOpen,
      rightSidebarOpen: _rightSidebarOpen,
      embeddedSidebarWidth: _embeddedSidebarWidth,
      rightSidebarWidth: _rightSidebarWidth,
      sidebarMinWidth: _sidebarMinWidth,
      sidebarMaxWidth: _sidebarMaxWidth,
      onToggleSidebar: _toggleTabletSidebar,
      onToggleRightSidebar: _toggleRightSidebar,
      onSelectConversation: (id) {
        _switchConversationAnimated(id);
      },
      onNewConversation: () async {
        await _createNewConversationAnimated();
      },
      onCreateNewConversation: () async {
        await _createNewConversationAnimated();
        if (mounted) _forceScrollToBottomSoon(animate: false);
      },
      onSelectModel: () => showModelSelectSheet(context),
      onSidebarWidthChanged: (dx) {
        setState(() {
          _embeddedSidebarWidth = (_embeddedSidebarWidth + dx).clamp(_sidebarMinWidth, _sidebarMaxWidth);
        });
      },
      onSidebarWidthChangeEnd: () {
        try { context.read<SettingsProvider>().setDesktopSidebarWidth(_embeddedSidebarWidth); } catch (_) {}
      },
      onRightSidebarWidthChanged: (dx) {
        setState(() {
          _rightSidebarWidth = (_rightSidebarWidth - dx).clamp(_sidebarMinWidth, _sidebarMaxWidth);
        });
      },
      onRightSidebarWidthChangeEnd: () {
        try { context.read<SettingsProvider>().setDesktopRightSidebarWidth(_rightSidebarWidth); } catch (_) {}
      },
      buildAssistantBackground: _buildAssistantBackground,
      body: _wrapWithDropTarget(Stack(
              children: [

                Padding(
                  padding: EdgeInsets.only(top: kToolbarHeight + MediaQuery.of(context).padding.top),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: Column(
                        children: [
                          // Message list (add subtle animate on conversation switch)
                          Expanded(
                            child: FadeTransition(
                              opacity: _convoFade,
                              child: KeyedSubtree(
                                key: ValueKey<String>(_currentConversation?.id ?? 'none'),
                                child: _buildMessageListView(
                                  context,
                                  dividerPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                ),
                              ).animate(key: ValueKey('tab_body_'+(_currentConversation?.id ?? 'none')))
                               .fadeIn(duration: 200.ms, curve: Curves.easeOutCubic),
                               // .slideY(begin: 0.02, end: 0, duration: 240.ms, curve: Curves.easeOutCubic),
                            ),
                          ),

                          // Input bar with max width
                          NotificationListener<SizeChangedLayoutNotification>(
                            onNotification: (n) {
                              WidgetsBinding.instance.addPostFrameCallback((_) => _measureInputBar());
                              return false;
                            },
                            child: SizeChangedLayoutNotifier(
                              child: Builder(
                                builder: (context) {
                                  Widget input = _buildChatInputBar(context, isTablet: true);
                                  input = Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 800),
                                      child: input,
                                    ),
                                  );
                                  return input;
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Selection toolbar overlay (tablet) with iOS glass capsule + animations
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      // Move higher: 72 + 12 + 38
                      padding: const EdgeInsets.only(bottom: 122),
                      child: _AnimatedSelectionBar(
                        visible: _selecting,
                        child: _SelectionToolbar(
                          onCancel: () {
                            setState(() {
                              _selecting = false;
                              _selectedItems.clear();
                            });
                          },
                          onConfirm: () async {
                            final convo = _currentConversation;
                            if (convo == null) return;
                            final collapsed = _collapseVersions(_messages);
                            final selected = <ChatMessage>[];
                            for (final m in collapsed) {
                              if (_selectedItems.contains(m.id)) selected.add(m);
                            }
                            if (selected.isEmpty) {
                              final l10n = AppLocalizations.of(context)!;
                              showAppSnackBar(
                                context,
                                message: l10n.homePageSelectMessagesToShare,
                                type: NotificationType.info,
                              );
                              return;
                            }
                            setState(() { _selecting = false; });
                            await showChatExportSheet(context, conversation: convo, selectedMessages: selected);
                            if (mounted) setState(() { _selectedItems.clear(); });
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // Scroll-to-bottom button
                Builder(builder: (context) {
                  final showSetting = context.watch<SettingsProvider>().showMessageNavButtons;
                  if (!showSetting || _messages.isEmpty) return const SizedBox.shrink();
                  return _GlassyScrollButton(
                    icon: Lucide.ChevronDown,
                    onTap: _forceScrollToBottom,
                    bottomOffset: _inputBarHeight + 12,
                    visible: _showJumpToBottom,
                  );
                }),

                // Scroll-to-previous-question button
                Builder(builder: (context) {
                  final showSetting = context.watch<SettingsProvider>().showMessageNavButtons;
                  if (!showSetting || _messages.isEmpty) return const SizedBox.shrink();
                  return _GlassyScrollButton(
                    icon: Lucide.ChevronUp,
                    onTap: _jumpToPreviousQuestion,
                    bottomOffset: _inputBarHeight + 12 + 52,
                    visible: _showJumpToBottom,
                  );
                }),
              ],
            )),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    try { WidgetsBinding.instance.removeObserver(this); } catch (_) {}
    _convoFadeController.dispose();
    _mcpProvider?.removeListener(_onMcpChanged);
    // Remove drawer value listener
    _drawerController.removeListener(_onDrawerValueChanged);
    _inputFocus.dispose();
    _inputController.dispose();
    _scrollController.removeListener(_onScrollControllerChanged);
    _scrollController.dispose();
    try { _chatActionSub?.cancel(); } catch (_) {}
    // Dispose ChatController (handles stream cleanup)
    _chatController.dispose();
    // Dispose StreamController (handles throttle timers cleanup)
    _streamController.dispose();
    _userScrollTimer?.cancel();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() {
    // Navigating away: drop focus so it won't be restored.
    _dismissKeyboard();
  }

  @override
  void didPopNext() {
    // 返回到本页：
    // - 移动端保持原有行为，不自动弹出软键盘；
    // - 桌面端则自动聚焦输入框，方便立即输入。
    if (_isDesktopPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _inputFocus.requestFocus();
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _dismissKeyboard());
    }
  }

  // ===========================================================================
  // REGION: Message Generation Helpers (Refactored)
  // ===========================================================================

  /// Build API messages list from current conversation state.
  /// Applies truncation, version collapsing, and strips [image:] / [file:] markers.
  /// NOTE: Delegates to MessageBuilderService.
  List<Map<String, dynamic>> _buildApiMessages() {
    return _messageBuilderService.buildApiMessages(
      messages: _messages,
      versionSelections: _versionSelections,
      currentConversation: _currentConversation,
    );
  }

  /// Process user messages in apiMessages: extract documents, apply OCR, inject file prompts.
  /// Returns the image paths from the last user message (for API call).
  /// NOTE: Delegates to MessageBuilderService.
  Future<List<String>> _processUserMessagesForApi(
    List<Map<String, dynamic>> apiMessages,
    SettingsProvider settings,
    dynamic assistant,
  ) async {
    return _messageBuilderService.processUserMessagesForApi(apiMessages, settings, assistant as Assistant?);
  }

  /// Inject system prompt into apiMessages.
  /// NOTE: Delegates to MessageBuilderService.
  void _injectSystemPrompt(
    List<Map<String, dynamic>> apiMessages,
    dynamic assistant,
    String modelId,
  ) {
    _messageBuilderService.injectSystemPrompt(apiMessages, assistant as Assistant?, modelId);
  }

  /// Inject memory prompts and recent chats reference into apiMessages.
  /// NOTE: Delegates to MessageBuilderService.
  Future<void> _injectMemoryAndRecentChats(
    List<Map<String, dynamic>> apiMessages,
    dynamic assistant,
  ) async {
    await _messageBuilderService.injectMemoryAndRecentChats(apiMessages, assistant as Assistant?);
  }

  /// Inject search tool usage prompt into apiMessages.
  /// NOTE: Delegates to MessageBuilderService.
  void _injectSearchPrompt(
    List<Map<String, dynamic>> apiMessages,
    SettingsProvider settings,
    bool hasBuiltInSearch,
  ) {
    _messageBuilderService.injectSearchPrompt(apiMessages, settings, hasBuiltInSearch);
  }

  /// Inject instruction injection prompts into apiMessages.
  /// NOTE: Delegates to MessageBuilderService.
  Future<void> _injectInstructionPrompts(
    List<Map<String, dynamic>> apiMessages,
    String? assistantId,
  ) async {
    await _messageBuilderService.injectInstructionPrompts(apiMessages, assistantId);
  }

  /// Apply context message limit based on assistant settings.
  /// NOTE: Delegates to MessageBuilderService.
  void _applyContextLimit(List<Map<String, dynamic>> apiMessages, dynamic assistant) {
    _messageBuilderService.applyContextLimit(apiMessages, assistant as Assistant?);
  }

  /// Convert local Markdown image links to inline base64 for model context.
  /// NOTE: Delegates to MessageBuilderService.
  Future<void> _inlineLocalImages(List<Map<String, dynamic>> apiMessages) async {
    await _messageBuilderService.inlineLocalImages(apiMessages);
  }

  /// Check if Gemini built-in search is enabled for the given provider/model.
  /// NOTE: Delegates to MessageBuilderService.
  bool _hasBuiltInGeminiSearch(SettingsProvider settings, String providerKey, String modelId) {
    return _messageBuilderService.hasBuiltInGeminiSearch(settings, providerKey, modelId);
  }

  /// Prepare tool definitions for API call.
  /// NOTE: Delegates to GenerationController.
  List<Map<String, dynamic>> _buildToolDefinitions(
    SettingsProvider settings,
    dynamic assistant,
    String providerKey,
    String modelId,
    bool hasBuiltInSearch,
  ) {
    return _generationController.buildToolDefinitions(
      settings,
      assistant as Assistant?,
      providerKey,
      modelId,
      hasBuiltInSearch,
    );
  }

  /// Build tool call handler function.
  /// NOTE: Delegates to GenerationController.
  Future<String> Function(String, Map<String, dynamic>)? _buildToolCallHandler(
    SettingsProvider settings,
    dynamic assistant,
  ) {
    return _generationController.buildToolCallHandler(settings, assistant as Assistant?);
  }

  /// Build custom headers from assistant settings.
  /// NOTE: Delegates to GenerationController.
  Map<String, String>? _buildCustomHeaders(dynamic assistant) {
    return _generationController.buildCustomHeaders(assistant as Assistant?);
  }

  /// Build custom body from assistant settings.
  /// NOTE: Delegates to GenerationController.
  Map<String, dynamic>? _buildCustomBody(dynamic assistant) {
    return _generationController.buildCustomBody(assistant as Assistant?);
  }

  // ===========================================================================
  // REGION: Streaming Chunk Handlers
  // ===========================================================================

  /// Transform raw content using assistant regexes.
  String _transformAssistantContent(stream_ctrl.StreamingState state, [String? raw]) {
    return applyAssistantRegexes(
      raw ?? state.fullContentRaw,
      assistant: state.ctx.assistant,
      scope: AssistantRegexScope.assistant,
      visual: false,
    );
  }

  /// Clean up stream throttle timers for a message.
  void _cleanupStreamTimers(String messageId) {
    _streamController.cleanupTimers(messageId);
  }

  /// Handle reasoning chunk from stream.
  Future<void> _handleReasoningChunk(ChatStreamChunk chunk, stream_ctrl.StreamingState state) async {
    if ((chunk.reasoning ?? '').isEmpty || !state.ctx.supportsReasoning) return;

    final messageId = state.messageId;
    final conversationId = state.conversationId;

    if (state.ctx.streamOutput) {
      final r = _reasoning[messageId] ?? stream_ctrl.ReasoningData();
      r.text += chunk.reasoning!;
      r.startAt ??= DateTime.now();
      r.expanded = false;
      _reasoning[messageId] = r;

      // Add to reasoning segments for mixed display
      final segments = _reasoningSegments[messageId] ?? <stream_ctrl.ReasoningSegmentData>[];
      if (segments.isEmpty) {
        final newSegment = stream_ctrl.ReasoningSegmentData();
        newSegment.text = chunk.reasoning!;
        newSegment.startAt = DateTime.now();
        newSegment.expanded = false;
        newSegment.toolStartIndex = (_toolParts[messageId]?.length ?? 0);
        segments.add(newSegment);
      } else {
        final hasToolsAfterLastSegment = (_toolParts[messageId]?.isNotEmpty ?? false);
        final lastSegment = segments.last;
        if (hasToolsAfterLastSegment && lastSegment.finishedAt != null) {
          final newSegment = stream_ctrl.ReasoningSegmentData();
          newSegment.text = chunk.reasoning!;
          newSegment.startAt = DateTime.now();
          newSegment.expanded = false;
          newSegment.toolStartIndex = (_toolParts[messageId]?.length ?? 0);
          segments.add(newSegment);
        } else {
          lastSegment.text += chunk.reasoning!;
          lastSegment.startAt ??= DateTime.now();
        }
      }
      _reasoningSegments[messageId] = segments;

      await _chatService.updateMessage(
        messageId,
        reasoningSegmentsJson: _serializeReasoningSegments(segments),
      );

      if (mounted && _currentConversation?.id == conversationId) setState(() {});
      await _chatService.updateMessage(
        messageId,
        reasoningText: r.text,
        reasoningStartAt: r.startAt,
      );
    } else {
      state.reasoningStartAt ??= DateTime.now();
      state.bufferedReasoning += chunk.reasoning!;
      await _chatService.updateMessage(
        messageId,
        reasoningText: state.bufferedReasoning,
        reasoningStartAt: state.reasoningStartAt,
      );
    }
  }

  /// Handle tool calls chunk from stream.
  Future<void> _handleToolCallsChunk(ChatStreamChunk chunk, stream_ctrl.StreamingState state) async {
    if ((chunk.toolCalls ?? const []).isEmpty) return;

    final messageId = state.messageId;
    final conversationId = state.conversationId;

    // Finish any unfinished reasoning segment when tools start
    final segments = _reasoningSegments[messageId] ?? <stream_ctrl.ReasoningSegmentData>[];
    if (segments.isNotEmpty && segments.last.finishedAt == null) {
      segments.last.finishedAt = DateTime.now();
      final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
      if (autoCollapse) {
        segments.last.expanded = false;
        final rd = _reasoning[messageId];
        if (rd != null) rd.expanded = false;
      }
      _reasoningSegments[messageId] = segments;
      await _chatService.updateMessage(
        messageId,
        reasoningSegmentsJson: _serializeReasoningSegments(segments),
      );
    }

    // Add tool call placeholders
    final existing = List<ToolUIPart>.of(_toolParts[messageId] ?? const []);
    for (final c in chunk.toolCalls!) {
      existing.add(ToolUIPart(id: c.id, toolName: c.name, arguments: c.arguments, loading: true));
    }
    if (mounted && _currentConversation?.id == conversationId) {
      setState(() {
        _toolParts[messageId] = _dedupeToolPartsList(existing);
      });
    }

    // Persist tool events
    try {
      final prev = _chatService.getToolEvents(messageId);
      final newEvents = <Map<String, dynamic>>[
        ...prev,
        for (final c in chunk.toolCalls!)
          {'id': c.id, 'name': c.name, 'arguments': c.arguments, 'content': null},
      ];
      await _chatService.setToolEvents(messageId, _dedupeToolEvents(newEvents));
    } catch (_) {}
  }

  /// Handle tool results chunk from stream.
  Future<void> _handleToolResultsChunk(ChatStreamChunk chunk, stream_ctrl.StreamingState state) async {
    if ((chunk.toolResults ?? const []).isEmpty) return;

    final messageId = state.messageId;
    final conversationId = state.conversationId;

    final parts = List<ToolUIPart>.of(_toolParts[messageId] ?? const []);
    for (final r in chunk.toolResults!) {
      int idx = -1;
      for (int i = 0; i < parts.length; i++) {
        if (parts[i].loading && (parts[i].id == r.id || (parts[i].id.isEmpty && parts[i].toolName == r.name))) {
          idx = i;
          break;
        }
      }
      if (idx >= 0) {
        parts[idx] = ToolUIPart(
          id: parts[idx].id,
          toolName: parts[idx].toolName,
          arguments: (r.arguments is Map && (r.arguments as Map).isNotEmpty)
              ? Map<String, dynamic>.from(r.arguments)
              : parts[idx].arguments,
          content: r.content,
          loading: false,
        );
      } else {
        parts.add(ToolUIPart(
          id: r.id,
          toolName: r.name,
          arguments: r.arguments,
          content: r.content,
          loading: false,
        ));
      }
      try {
        await _chatService.upsertToolEvent(
          messageId,
          id: r.id,
          name: r.name,
          arguments: r.arguments,
          content: r.content,
        );
      } catch (_) {}
    }
    if (mounted && _currentConversation?.id == conversationId) {
      setState(() {
        _toolParts[messageId] = _dedupeToolPartsList(parts);
      });
    }
    if (!_isUserScrolling) {
      _scrollToBottomSoon();
    }
  }

  /// Handle content chunk from stream (non-done).
  Future<void> _handleContentChunk(ChatStreamChunk chunk, stream_ctrl.StreamingState state, String chunkContent) async {
    final messageId = state.messageId;
    final conversationId = state.conversationId;

    state.fullContentRaw += chunkContent;
    if (chunk.totalTokens > 0) {
      state.totalTokens = chunk.totalTokens;
    }
    if (chunk.usage != null) {
      state.usage = (state.usage ?? const TokenUsage()).merge(chunk.usage!);
      state.totalTokens = state.usage!.totalTokens;
    }

    String streamingProcessed = _transformAssistantContent(state);
    if (streamingProcessed.contains('data:image') && streamingProcessed.contains('base64,')) {
      try {
        final sanitized = await MarkdownMediaSanitizer.replaceInlineBase64Images(streamingProcessed);
        if (sanitized != streamingProcessed) {
          streamingProcessed = sanitized;
          state.fullContentRaw = sanitized;
        }
      } catch (e) {
        // ignore
      }
    }
    _scheduleInlineImageSanitize(messageId, latestContent: streamingProcessed, immediate: true);
    await _chatService.updateMessage(
      messageId,
      content: streamingProcessed,
      totalTokens: state.totalTokens,
    );
    if (state.ctx.streamOutput && mounted && _currentConversation?.id == conversationId) {
      setState(() {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            content: streamingProcessed,
            totalTokens: state.totalTokens,
          );
        }
      });
    }

    // End reasoning when content starts
    if (state.ctx.streamOutput && chunkContent.isNotEmpty) {
      await _finishReasoningOnContent(state);
    }

    // Schedule throttled UI update via StreamController
    if (state.ctx.streamOutput) {
      _streamController.scheduleThrottledUpdate(
        messageId,
        conversationId,
        streamingProcessed,
        totalTokens: state.totalTokens,
        updateMessageInList: (id, content, tokens) {
          final index = _messages.indexWhere((m) => m.id == id);
          if (index != -1) {
            _messages[index] = _messages[index].copyWith(
              content: content,
              totalTokens: tokens,
            );
          }
          _autoScrollToBottomIfNeeded();
        },
      );
    }
  }

  /// Finish reasoning segment when content starts arriving.
  Future<void> _finishReasoningOnContent(stream_ctrl.StreamingState state) async {
    // Use unified reasoning completion method from StreamController
    await _streamController.finishReasoningAndPersist(
      state.messageId,
      updateReasoningInDb: (
        String messageId, {
        String? reasoningText,
        DateTime? reasoningFinishedAt,
        String? reasoningSegmentsJson,
      }) async {
        await _chatService.updateMessage(
          messageId,
          reasoningText: reasoningText,
          reasoningFinishedAt: reasoningFinishedAt,
          reasoningSegmentsJson: reasoningSegmentsJson,
        );
      },
    );
  }

  /// Handle stream finish (isDone == true).
  Future<void> _handleStreamFinish(ChatStreamChunk chunk, stream_ctrl.StreamingState state, String chunkContent) async {
    final messageId = state.messageId;
    final conversationId = state.conversationId;

    if (chunkContent.isNotEmpty) {
      state.fullContentRaw += chunkContent;
    }

    // Don't finish if tools are still loading
    final hasLoadingTool = (_toolParts[messageId]?.any((p) => p.loading) ?? false);
    if (hasLoadingTool) {
      return;
    }

    if (chunk.totalTokens > 0) {
      state.totalTokens = chunk.totalTokens;
    }
    if (chunk.usage != null) {
      state.usage = (state.usage ?? const TokenUsage()).merge(chunk.usage!);
      state.totalTokens = state.usage!.totalTokens;
    }

    await _finishStreaming(state);

    // Show notification if in background
    try {
      final sp = context.read<SettingsProvider>();
      if (PlatformUtils.isAndroid && !_appInForeground && sp.androidBackgroundChatMode == AndroidBackgroundChatMode.onNotify) {
        await NotificationService.showChatCompleted(
          title: AppLocalizations.of(context)!.notificationChatCompletedTitle,
          body: AppLocalizations.of(context)!.notificationChatCompletedBody,
        );
      }
    } catch (_) {}

    // Handle buffered reasoning for non-streaming mode
    if (!state.ctx.streamOutput && state.bufferedReasoning.isNotEmpty) {
      final now = DateTime.now();
      final startAt = state.reasoningStartAt ?? now;
      await _chatService.updateMessage(
        messageId,
        reasoningText: state.bufferedReasoning,
        reasoningStartAt: startAt,
        reasoningFinishedAt: now,
      );
      final autoCollapse = context.read<SettingsProvider>().autoCollapseThinking;
      _reasoning[messageId] = stream_ctrl.ReasoningData()
        ..text = state.bufferedReasoning
        ..startAt = startAt
        ..finishedAt = now
        ..expanded = !autoCollapse;
      if (mounted && _currentConversation?.id == conversationId) setState(() {});
    }

    await _conversationStreams.remove(conversationId)?.cancel();

    // Ensure reasoning is finished
    final r = _reasoning[messageId];
    if (r != null && r.finishedAt == null) {
      r.finishedAt = DateTime.now();
      await _chatService.updateMessage(
        messageId,
        reasoningText: r.text,
        reasoningFinishedAt: r.finishedAt,
      );
    }
  }

  /// Finish streaming and persist final state.
  Future<void> _finishStreaming(stream_ctrl.StreamingState state, {bool generateTitle = true}) async {
    final messageId = state.messageId;
    final conversationId = state.conversationId;

    // Clean up stream throttle timer and flush final content
    _cleanupStreamTimers(messageId);

    final shouldGenerateTitle = generateTitle && state.ctx.generateTitleOnFinish && !state.titleQueued;
    if (state.finishHandled) {
      if (shouldGenerateTitle) {
        state.titleQueued = true;
        _maybeGenerateTitleFor(conversationId);
      }
      return;
    }
    state.finishHandled = true;
    if (shouldGenerateTitle) {
      state.titleQueued = true;
    }

    // Replace extremely long inline base64 images with local files to avoid jank
    final processedContent = _transformAssistantContent(state);
    final sanitizedContent = await MarkdownMediaSanitizer.replaceInlineBase64Images(processedContent);
    await _chatService.updateMessage(
      messageId,
      content: sanitizedContent,
      totalTokens: state.totalTokens,
      isStreaming: false,
    );
    if (!mounted) return;
    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          content: sanitizedContent,
          totalTokens: state.totalTokens,
          isStreaming: false,
        );
      }
    });
    _setConversationLoading(conversationId, false);

    // Use unified reasoning completion method
    await _streamController.finishReasoningAndPersist(
      messageId,
      updateReasoningInDb: (
        String messageId, {
        String? reasoningText,
        DateTime? reasoningFinishedAt,
        String? reasoningSegmentsJson,
      }) async {
        await _chatService.updateMessage(
          messageId,
          reasoningText: reasoningText,
          reasoningFinishedAt: reasoningFinishedAt,
          reasoningSegmentsJson: reasoningSegmentsJson,
        );
      },
    );

    if (shouldGenerateTitle) {
      _maybeGenerateTitleFor(conversationId);
    }
  }

  /// Handle stream error.
  Future<void> _handleStreamError(dynamic e, stream_ctrl.StreamingState state) async {
    final messageId = state.messageId;
    final conversationId = state.conversationId;

    _cleanupStreamTimers(messageId);
    final errText = '${AppLocalizations.of(context)!.generationInterrupted}: $e';
    final processed = _transformAssistantContent(state);
    final displayContent = processed.isNotEmpty ? processed : errText;
    await _chatService.updateMessage(
      messageId,
      content: displayContent,
      totalTokens: state.totalTokens,
      isStreaming: false,
    );

    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            content: displayContent,
            isStreaming: false,
            totalTokens: state.totalTokens,
          );
        }
      });
    }
    _setConversationLoading(conversationId, false);

    // Use unified reasoning completion method on error
    await _streamController.finishReasoningAndPersist(
      messageId,
      updateReasoningInDb: (
        String messageId, {
        String? reasoningText,
        DateTime? reasoningFinishedAt,
        String? reasoningSegmentsJson,
      }) async {
        await _chatService.updateMessage(
          messageId,
          reasoningText: reasoningText,
          reasoningFinishedAt: reasoningFinishedAt,
          reasoningSegmentsJson: reasoningSegmentsJson,
        );
      },
    );

    await _conversationStreams.remove(conversationId)?.cancel();
    showAppSnackBar(
      context,
      message: '${AppLocalizations.of(context)!.generationInterrupted}: $e',
      type: NotificationType.error,
    );
  }

  /// Handle stream done callback.
  Future<void> _handleStreamDone(stream_ctrl.StreamingState state) async {
    final conversationId = state.conversationId;

    _cleanupStreamTimers(state.messageId);
    if (_loadingConversationIds.contains(conversationId)) {
      await _finishStreaming(state, generateTitle: state.ctx.generateTitleOnFinish);
    }
    try {
      final sp = context.read<SettingsProvider>();
      if (PlatformUtils.isAndroid && !_appInForeground && sp.androidBackgroundChatMode == AndroidBackgroundChatMode.onNotify) {
        await NotificationService.showChatCompleted(
          title: AppLocalizations.of(context)!.notificationChatCompletedTitle,
          body: AppLocalizations.of(context)!.notificationChatCompletedBody,
        );
      }
    } catch (_) {}
    await _conversationStreams.remove(conversationId)?.cancel();
  }

  /// Dispatch stream chunk to appropriate handler.
  Future<void> _handleStreamChunk(ChatStreamChunk chunk, stream_ctrl.StreamingState state) async {
    final chunkContent = chunk.content.isNotEmpty
        ? _captureGeminiThoughtSignature(chunk.content, state.messageId)
        : '';

    // Handle reasoning
    if ((chunk.reasoning ?? '').isNotEmpty && state.ctx.supportsReasoning) {
      await _handleReasoningChunk(chunk, state);
    }

    // Handle tool calls
    if ((chunk.toolCalls ?? const []).isNotEmpty) {
      await _handleToolCallsChunk(chunk, state);
    }

    // Handle tool results
    if ((chunk.toolResults ?? const []).isNotEmpty) {
      await _handleToolResultsChunk(chunk, state);
    }

    // Handle finish or content
    if (chunk.isDone) {
      await _handleStreamFinish(chunk, state, chunkContent);
    } else {
      await _handleContentChunk(chunk, state, chunkContent);
    }
  }

  // ===========================================================================
  // END REGION: Streaming Chunk Handlers
  // ===========================================================================

  /// Execute generation with the given context. This is the shared streaming logic used by both _sendMessage and _regenerateAtMessage.

  /// - _handleStreamChunk: Main dispatcher for stream chunks
  /// - _handleReasoningChunk: Handle reasoning content
  /// - _handleToolCallsChunk: Handle MCP tool call placeholders
  /// - _handleToolResultsChunk: Handle MCP tool results
  /// - _handleContentChunk: Handle regular content chunks
  /// - _handleStreamFinish: Handle stream completion (isDone)
  /// - _handleStreamError: Handle stream errors
  /// - _handleStreamDone: Handle stream done callback
  /// - _finishStreaming: Finalize streaming and persist state
  Future<void> _executeGeneration(stream_ctrl.GenerationContext ctx) async {
    final state = stream_ctrl.StreamingState(ctx);
    final assistant = ctx.assistant;
    final conversationId = state.conversationId;

    try {
      final stream = ChatApiService.sendMessageStream(
        config: ctx.config,
        modelId: ctx.modelId,
        messages: ctx.apiMessages,
        userImagePaths: ctx.userImagePaths,
        thinkingBudget: assistant?.thinkingBudget ?? ctx.settings.thinkingBudget,
        temperature: assistant?.temperature,
        topP: assistant?.topP,
        maxTokens: assistant?.maxTokens,
        tools: ctx.toolDefs.isEmpty ? null : ctx.toolDefs,
        onToolCall: ctx.onToolCall,
        extraHeaders: ctx.extraHeaders,
        extraBody: ctx.extraBody,
        stream: ctx.streamOutput,
      );

      await _conversationStreams[conversationId]?.cancel();
      final sub = stream.listen(
        (chunk) => _handleStreamChunk(chunk, state),
        onError: (e) => _handleStreamError(e, state),
        onDone: () => _handleStreamDone(state),
        cancelOnError: true,
      );
      _conversationStreams[conversationId] = sub;
    } catch (e) {
      await _handleStreamError(e, state);
    }
  }

  // ===========================================================================
  // END REGION: Message Generation Helpers
  // ===========================================================================

}

class _SidebarResizeHandle extends StatefulWidget {
  const _SidebarResizeHandle({required this.visible, required this.onDrag, this.onDragEnd});
  final bool visible;
  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;

  @override
  State<_SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<_SidebarResizeHandle> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!widget.visible) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
      onHorizontalDragEnd: (_) => widget.onDragEnd?.call(),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Container(
          width: 6,
          height: double.infinity,
          color: Colors.transparent,
          alignment: Alignment.center,
          child: Container(
            width: 1,
            height: double.infinity,
            color: (_hovered ? cs.primary.withOpacity(0.28) : cs.outlineVariant.withOpacity(0.10)),
          ),
        ),
      ),
    );
  }
}

// NOTE: GenerationContext, StreamingState, ReasoningData, ReasoningSegmentData
// have been moved to stream_controller.dart

class _TranslationData {
  bool expanded = true; // default to expanded when translation is added
}

class _CurrentModelIcon extends StatelessWidget {
  const _CurrentModelIcon({
    required this.providerKey,
    required this.modelId,
    this.size = 28,
    this.withBackground = true,
    this.backgroundColor,
  });
  final String? providerKey;
  final String? modelId;
  final double size; // outer diameter
  final bool withBackground; // whether to draw circular background
  final Color? backgroundColor; // override background color if provided


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (providerKey == null || modelId == null) return const SizedBox.shrink();
    String? asset = BrandAssets.assetForName(modelId!);
    asset ??= BrandAssets.assetForName(providerKey!);
    Widget inner;
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        final isColorful = asset.contains('color');
        final ColorFilter? tint = (Theme.of(context).brightness == Brightness.dark && !isColorful)
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : null;
        inner = SvgPicture.asset(
          asset,
          width: size * 0.5,
          height: size * 0.5,
          colorFilter: tint,
        );
      } else {
        inner = Image.asset(asset, width: size * 0.5, height: size * 0.5, fit: BoxFit.contain);
      }
    } else {
      inner = Text(
        modelId!.isNotEmpty ? modelId!.characters.first.toUpperCase() : '?',
        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: size * 0.43),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: withBackground
            ? (backgroundColor ?? (isDark ? Colors.white10 : cs.primary.withOpacity(0.1)))
            : Colors.transparent,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: size * 0.64,
        height: size * 0.64,
        child: Center(child: inner is SvgPicture || inner is Image ? inner : FittedBox(child: inner)),
      ),
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({required this.onCancel, required this.onConfirm});
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Use compact icon-only glass buttons to avoid taking too much width
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassCircleButtonSmall(
          icon: Lucide.X,
          color: cs.onSurface,
          onTap: onCancel,
          semanticLabel: AppLocalizations.of(context)!.homePageCancel,
        ),
        const SizedBox(width: 14),
        _GlassCircleButtonSmall(
          icon: Lucide.Check,
          color: cs.primary,
          onTap: onConfirm,
          semanticLabel: AppLocalizations.of(context)!.homePageDone,
        ),
      ],
    );
  }
}

// Animated container that slides/fades in/out like provider multi-select bar
class _AnimatedSelectionBar extends StatelessWidget {
  const _AnimatedSelectionBar({required this.visible, required this.child});
  final bool visible;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: IgnorePointer(ignoring: !visible, child: child),
      ),
    );
  }
}

// iOS-style glass capsule button (no ripple), similar to providers multi-select style
class _GlassCapsuleButton extends StatefulWidget {
  const _GlassCapsuleButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_GlassCapsuleButton> createState() => _GlassCapsuleButtonState();
}

class _GlassCapsuleButtonState extends State<_GlassCapsuleButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    // Glass background, match providers' capsule taste
    final glassBase = isDark ? Colors.black.withOpacity(0.06) : Colors.white.withOpacity(0.65);
    final overlay = isDark ? Colors.black.withOpacity(0.06) : Colors.black.withOpacity(0.05);
    final tileColor = _pressed ? Color.alphaBlend(overlay, glassBase) : glassBase;
    final borderColor = cs.outlineVariant.withOpacity(isDark ? 0.35 : 0.40);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Haptics.light();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: tileColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1.0),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 16, color: widget.color),
                  const SizedBox(width: 6),
                  Text(
                    widget.label,
                    style: TextStyle(color: widget.color, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glassy scroll navigation button with backdrop blur effect.
///
/// Used for scroll-to-bottom and scroll-to-previous-question buttons.
/// Includes fade and scale animation support via [visible] parameter.
class _GlassyScrollButton extends StatelessWidget {
  const _GlassyScrollButton({
    required this.icon,
    required this.onTap,
    required this.bottomOffset,
    required this.visible,
    this.iconSize = 16,
    this.padding = 6,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double bottomOffset;
  final bool visible;
  final double iconSize;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.bottomRight,
      child: SafeArea(
        top: false,
        bottom: false,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedScale(
            scale: visible ? 1.0 : 0.9,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              opacity: visible ? 1 : 0,
              child: Padding(
                padding: EdgeInsets.only(right: 16, bottom: bottomOffset),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.06)
                            : Colors.white.withOpacity(0.07),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.10)
                              : Theme.of(context).colorScheme.outline.withOpacity(0.20),
                          width: 1,
                        ),
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onTap,
                          child: Padding(
                            padding: EdgeInsets.all(padding),
                            child: Icon(
                              icon,
                              size: iconSize,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Compact icon-only glass button to minimize width (like providers multi-select icons)
class _GlassCircleButtonSmall extends StatefulWidget {
  const _GlassCircleButtonSmall({
    required this.icon,
    required this.color,
    required this.onTap,
    this.semanticLabel,
    this.size = 40,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? semanticLabel;
  final double size; // diameter

  @override
  State<_GlassCircleButtonSmall> createState() => _GlassCircleButtonSmallState();
}

class _GlassCircleButtonSmallState extends State<_GlassCircleButtonSmall> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final glassBase = isDark ? Colors.black.withOpacity(0.06) : Colors.white.withOpacity(0.06);
    final overlay = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05);
    final tileColor = _pressed ? Color.alphaBlend(overlay, glassBase) : glassBase;
    final borderColor = cs.outlineVariant.withOpacity(isDark ? 0.10 : 0.10);

    final child = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(child: Icon(widget.icon, size: 18, color: widget.color)),
    );

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          Haptics.light();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: tileColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
