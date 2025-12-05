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
import '../controllers/chat_controller.dart';
import '../controllers/stream_controller.dart' as stream_ctrl;
import '../controllers/generation_controller.dart';
import '../controllers/scroll_controller.dart' as scroll_ctrl;
import '../controllers/home_view_model.dart';
import '../services/message_builder_service.dart';
import '../services/ocr_service.dart';
import '../services/translation_service.dart';
import '../services/file_upload_service.dart';
import '../../model/widgets/model_select_sheet.dart';
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
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
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
import '../../../desktop/quick_phrase_popover.dart';
import '../../../desktop/instruction_injection_popover.dart';
import '../widgets/instruction_injection_sheet.dart';
import '../widgets/learning_prompt_sheet.dart';
import 'home_mobile_layout.dart';
import 'home_desktop_layout.dart';
import '../utils/model_display_helper.dart';
import '../widgets/scroll_nav_buttons.dart';
import '../widgets/selection_toolbar.dart';
import '../widgets/message_list_view.dart';
import '../widgets/chat_input_section.dart';
import '../services/message_generation_service.dart';


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
  late MessageGenerationService _messageGenerationService;
  late HomeViewModel _viewModel;
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
  McpProvider? _mcpProvider;
  late scroll_ctrl.ChatScrollController _scrollCtrl;

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
      // 平板 / 非桌面端使用 bottom sheet
      await showInstructionInjectionSheet(context, assistantId: assistantId);
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
    await showLearningPromptSheet(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = (state == AppLifecycleState.resumed);
  }

  // Selection mode state for export/share
  bool _selecting = false;
  final Set<String> _selectedItems = <String>{}; // selected message ids (collapsed view)

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

  /// Cancel the active streaming for the current conversation.
  /// Delegates to HomeViewModel for business logic.
  Future<void> _cancelStreaming() async {
    await _viewModel.cancelStreaming();
    if (mounted) {
      setState(() {}); // Refresh UI after cancellation
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

  /// Get clear context label based on current state.
  /// Delegates calculation to HomeViewModel.
  String _clearContextLabel() {
    final l10n = AppLocalizations.of(context)!;
    return _viewModel.getClearContextLabel(
      (actual, configured) => l10n.homePageClearContextWithCount(actual, configured),
      l10n.homePageClearContext,
    );
  }

  /// Clear context (toggle truncate at tail).
  /// Uses ViewModel for business logic.
  Future<void> _onClearContext() async {
    await _viewModel.clearContext();
    if (mounted) {
      setState(() {});
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
    // Initialize MessageGenerationService for orchestrating message generation
    _messageGenerationService = MessageGenerationService(
      chatService: _chatService,
      messageBuilderService: _messageBuilderService,
      generationController: _generationController,
      streamController: _streamController,
      contextProvider: context,
    );
    // Initialize HomeViewModel for combining actions + services
    _viewModel = HomeViewModel(
      chatService: _chatService,
      messageBuilderService: _messageBuilderService,
      messageGenerationService: _messageGenerationService,
      generationController: _generationController,
      streamController: _streamController,
      chatController: _chatController,
      contextProvider: context,
      getTitleForLocale: _titleForLocale,
    );
    // Wire up ViewModel callbacks
    _viewModel.onError = (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      showAppSnackBar(context, message: '${l10n.generationInterrupted}: $error', type: NotificationType.error);
    };
    _viewModel.onWarning = (warning) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      if (warning == 'no_model') {
        showAppSnackBar(context, message: l10n.homePagePleaseSelectModel, type: NotificationType.warning);
      }
    };
    _viewModel.onScrollToBottom = _scrollToBottomSoon;
    _viewModel.onHapticFeedback = () {
      try {
        final settings = context.read<SettingsProvider>();
        if (settings.hapticsOnGenerate) Haptics.light();
      } catch (_) {}
    };
    _viewModel.onScheduleImageSanitize = (messageId, content, {bool immediate = false}) {
      _scheduleInlineImageSanitize(messageId, latestContent: content, immediate: immediate);
    };
    _viewModel.onStreamFinished = () {
      // Show notification if in background - handled by _handleStreamDone
    };
    _viewModel.onConversationSwitched = () {
      _restoreMessageUiState();
      _scrollToBottom(animate: false);
    };
    // Initialize ChatScrollController for scroll behavior management
    _scrollCtrl = scroll_ctrl.ChatScrollController(
      scrollController: _scrollController,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
      getAutoScrollEnabled: () => context.read<SettingsProvider>().autoScrollEnabled,
      getAutoScrollIdleSeconds: () => context.read<SettingsProvider>().autoScrollIdleSeconds,
    );
    _initChat();
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
            _scrollCtrl.scrollToBottom();
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

  // NOTE: Scroll controller listener logic moved to ChatScrollController

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

  /// Switch to an existing conversation with animation.
  /// Uses ViewModel for business logic, handles animations in UI layer.
  Future<void> _switchConversationAnimated(String id) async {
    // Before switching, persist any in-flight reasoning/content of current conversation
    try { await _viewModel.flushCurrentConversationProgress(); } catch (_) {}
    if (_currentConversation?.id == id) return;
    if (!_isDesktopPlatform) {
      try {
        await _convoFadeController.reverse();
      } catch (_) {}
    } else {
      // Desktop: skip fade-out to switch instantly
      try { _convoFadeController.stop(); _convoFadeController.value = 1.0; } catch (_) {}
    }

    // Use ViewModel for conversation switching
    await _viewModel.switchConversation(id);
    if (mounted) {
      setState(() {});
      // Ensure list lays out, then jump to bottom while hidden
      try { await WidgetsBinding.instance.endOfFrame; } catch (_) {}
      _scrollToBottom(animate: false);
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

  /// Create a new conversation with animation.
  /// Uses ViewModel for business logic, handles animations in UI layer.
  Future<void> _createNewConversationAnimated() async {
    // Flush current conversation progress before creating a new one
    try { await _viewModel.flushCurrentConversationProgress(); } catch (_) {}
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

  /// Create a new conversation.
  /// Uses ViewModel for business logic.
  Future<void> _createNewConversation() async {
    _translations.clear();
    await _viewModel.createNewConversation();
    if (mounted) {
      setState(() {});
    }
    _scrollToBottomSoon(animate: false);
  }

  /// Send a new message and generate an assistant response.
  /// Delegates to HomeViewModel for business logic.
  Future<void> _sendMessage(ChatInputData input) async {
    final content = input.text.trim();
    if (content.isEmpty && input.imagePaths.isEmpty && input.documents.isEmpty) return;
    if (_currentConversation == null) await _createNewConversation();

    // Scroll to bottom before and after sending
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);

    final success = await _viewModel.sendMessage(input);
    if (success && mounted) {
      setState(() {}); // Refresh UI after message sent
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  /// Regenerate response at a specific message.
  /// Delegates to HomeViewModel for business logic.
  Future<void> _regenerateAtMessage(ChatMessage message, {bool assistantAsNewReply = false}) async {
    if (_currentConversation == null) return;

    // Calculate versioning to know which messages will be removed (for translation cleanup)
    final versioning = _messageGenerationService.calculateRegenerationVersioning(
      message: message,
      messages: _messages,
      assistantAsNewReply: assistantAsNewReply,
    );
    if (versioning.lastKeep >= 0 && versioning.lastKeep < _messages.length - 1) {
      // Pre-clear translations for messages that will be removed
      for (int i = versioning.lastKeep + 1; i < _messages.length; i++) {
        _translations.remove(_messages[i].id);
      }
    }

    final success = await _viewModel.regenerateAtMessage(
      message,
      assistantAsNewReply: assistantAsNewReply,
    );
    if (success && mounted) {
      setState(() {}); // Refresh UI after regeneration started
    }
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

  // ===========================================================================
  // REGION: Scroll Helpers (delegating to ChatScrollController)
  // ===========================================================================

  /// Scroll to the bottom of the message list.
  void _scrollToBottom({bool animate = true}) => _scrollCtrl.scrollToBottom(animate: animate);

  /// Force scroll to bottom when user explicitly clicks the button.
  void _forceScrollToBottom() => _scrollCtrl.forceScrollToBottom();

  /// Force scroll after rebuilds when switching topics/conversations.
  void _forceScrollToBottomSoon({bool animate = true}) => _scrollCtrl.forceScrollToBottomSoon(
    animate: animate,
    postSwitchDelay: _postSwitchScrollDelay,
  );

  /// Ensure scroll reaches bottom even after widget tree transitions.
  void _scrollToBottomSoon({bool animate = true}) => _scrollCtrl.scrollToBottomSoon(animate: animate);

  /// Auto-scroll to bottom if conditions are met.
  void _autoScrollToBottomIfNeeded() {
    if (!mounted) return;
    _scrollCtrl.autoScrollToBottomIfNeeded();
  }

  /// Get viewport bounds for scroll navigation.
  (double, double) _getViewportBounds() {
    final media = MediaQuery.of(context);
    final double listTop = kToolbarHeight + media.padding.top;
    final double listBottom = media.size.height - media.padding.bottom - _inputBarHeight - 8;
    return (listTop, listBottom);
  }

  /// Scroll to a specific message by ID (from mini map selection).
  Future<void> _scrollToMessageId(String targetId) async {
    if (!mounted) return;
    final messages = _collapseVersions(_messages);
    await _scrollCtrl.scrollToMessageId(
      targetId: targetId,
      messages: messages,
      messageKeys: _messageKeys,
      getViewportBounds: _getViewportBounds,
      getViewHeight: () => MediaQuery.of(context).size.height,
    );
  }

  /// Jump to the previous user message (question) above the current viewport.
  Future<void> _jumpToPreviousQuestion() async {
    if (!mounted) return;
    final messages = _collapseVersions(_messages);
    await _scrollCtrl.jumpToPreviousQuestion(
      messages: messages,
      messageKeys: _messageKeys,
      getViewportBounds: _getViewportBounds,
    );
  }

  // ===========================================================================
  // END REGION: Scroll Helpers
  // ===========================================================================

  String? _currentStreamingMessageId() {
    for (int i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.role == 'assistant' && m.isStreaming) return m.id;
    }
    return null;
  }

  bool _shouldPinStreamingIndicator(String? messageId) {
    if (messageId == null) return false;
    if (_scrollCtrl.isUserScrolling) return false;
    // Only pin when list is long enough to scroll; otherwise keep inline indicator
    if (!_scrollCtrl.hasEnoughContentToScroll(56.0)) return false;
    // Only pin when near bottom to avoid covering content mid-scroll
    if (!_scrollCtrl.isNearBottom(48)) return false;
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

  /// Builds the selection toolbar overlay (shared by mobile and tablet layouts).
  Widget _buildSelectionToolbarOverlay() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          // Move higher: 72 + 12 + 38
          padding: const EdgeInsets.only(bottom: 122),
          child: AnimatedSelectionBar(
            visible: _selecting,
            child: SelectionToolbar(
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
    );
  }

  /// Builds the scroll navigation buttons (shared by mobile and tablet layouts).
  Widget _buildScrollButtons() {
    return Builder(builder: (context) {
      final showSetting = context.watch<SettingsProvider>().showMessageNavButtons;
      if (!showSetting || _messages.isEmpty) return const SizedBox.shrink();
      return Stack(
        children: [
          // Scroll-to-bottom button (bottom-right, above input bar)
          GlassyScrollButton(
            icon: Lucide.ChevronDown,
            onTap: _forceScrollToBottom,
            bottomOffset: _inputBarHeight + 12,
            visible: _scrollCtrl.showJumpToBottom,
          ),
          // Scroll-to-previous-question button (stacked above the bottom button)
          GlassyScrollButton(
            icon: Lucide.ChevronUp,
            onTap: _jumpToPreviousQuestion,
            bottomOffset: _inputBarHeight + 12 + 52, // place above the bottom button with gap
            visible: _scrollCtrl.showJumpToBottom,
          ),
        ],
      );
    });
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
          _buildSelectionToolbarOverlay(),

          // Scroll navigation buttons (bottom-right, above input bar)
          _buildScrollButtons(),
        ],
      )),
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
  /// Uses ViewModel for business logic, handles animations in UI layer.
  Future<void> _handleForkConversation(BuildContext context, ChatMessage message) async {
    if (!mounted || _currentConversation == null) return;

    // Handle fade animation for mobile
    if (!_isDesktopPlatform) {
      await _convoFadeController.reverse();
    }

    // Use ViewModel to fork and switch
    await _viewModel.forkConversation(message);

    if (!mounted) return;
    setState(() {});
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

  /// Converts internal translation data to UI state for MessageListView.
  Map<String, TranslationUiState> _buildTranslationUiStates() {
    final result = <String, TranslationUiState>{};
    for (final entry in _translations.entries) {
      result[entry.key] = TranslationUiState(
        expanded: entry.value.expanded,
        onToggle: () {
          setState(() {
            entry.value.expanded = !entry.value.expanded;
          });
        },
      );
    }
    return result;
  }

  /// Builds the message list view shared by both mobile and tablet layouts.
  ///
  /// This method extracts the common ListView.builder logic to reduce code duplication.
  /// The [dividerPadding] parameter allows for slight styling differences between layouts.
  Widget _buildMessageListView(
    BuildContext context, {
    required EdgeInsetsGeometry dividerPadding,
  }) {
    final pinnedId = _currentStreamingMessageId();
    final pinActive = _shouldPinStreamingIndicator(pinnedId);

    return MessageListView(
      scrollController: _scrollController,
      messages: _messages,
      versionSelections: _versionSelections,
      currentConversation: _currentConversation,
      messageKeys: _messageKeys,
      reasoning: _reasoning,
      reasoningSegments: _reasoningSegments,
      toolParts: _toolParts,
      translations: _buildTranslationUiStates(),
      selecting: _selecting,
      selectedItems: _selectedItems,
      dividerPadding: dividerPadding,
      pinnedStreamingMessageId: pinnedId,
      isPinnedIndicatorActive: pinActive,
      onVersionChange: (groupId, version) async {
        _versionSelections[groupId] = version;
        await _chatService.setSelectedVersion(_currentConversation!.id, groupId, version);
        if (mounted) setState(() {});
      },
      onRegenerateMessage: (message) => _regenerateAtMessage(message),
      onResendMessage: (message) => _regenerateAtMessage(message),
      onTranslateMessage: (message) => _translateMessage(message),
      onEditMessage: (message) => _onEditMessage(message),
      onDeleteMessage: (message, byGroup) => _handleDeleteMessage(context, message, byGroup),
      onForkConversation: (message) => _handleForkConversation(context, message),
      onShareMessage: (index, messages) => _handleShareMessage(index, messages),
      onSpeakMessage: (message) => _handleSpeak(context, message),
      onToggleSelection: (messageId, selected) {
        setState(() {
          if (selected) {
            _selectedItems.add(messageId);
          } else {
            _selectedItems.remove(messageId);
          }
        });
      },
      onToggleReasoning: (messageId) {
        final r = _reasoning[messageId];
        if (r != null) {
          setState(() {
            r.expanded = !r.expanded;
          });
        }
      },
      onToggleTranslation: (messageId) {
        final t = _translations[messageId];
        if (t != null) {
          setState(() {
            t.expanded = !t.expanded;
          });
        }
      },
      onToggleReasoningSegment: (messageId, segmentIndex) {
        final segments = _reasoningSegments[messageId];
        if (segments != null && segmentIndex < segments.length) {
          setState(() {
            segments[segmentIndex].expanded = !segments[segmentIndex].expanded;
          });
        }
      },
      buildPinnedStreamingIndicator: () => _buildPinnedStreamingIndicator(),
    );
  }

  /// Builds the ChatInputBar widget with common parameters.
  /// [isTablet] determines whether to include tablet-specific features like
  /// mini map, learning mode, camera/photos pickers, and file upload.
  Widget _buildChatInputBar(BuildContext context, {required bool isTablet}) {
    return ChatInputSection(
      inputBarKey: _inputBarKey,
      inputFocus: _inputFocus,
      inputController: _inputController,
      mediaController: _mediaController,
      isTablet: isTablet,
      isLoading: _isCurrentConversationLoading,
      isToolModel: _isToolModel,
      isReasoningModel: _isReasoningModel,
      isReasoningEnabled: _isReasoningEnabled,
      onMore: _toggleTools,
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
      onOpenSearch: _openSearchSettings,
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
      onStop: _cancelStreaming,
      onQuickPhrase: _showQuickPhraseMenu,
      onLongPressQuickPhrase: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QuickPhrasesPage()),
        );
      },
      onToggleOcr: () async {
        final sp = context.read<SettingsProvider>();
        await sp.setOcrEnabled(!sp.ocrEnabled);
      },
      onOpenMiniMap: () async {
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
      },
      onPickCamera: _onPickCamera,
      onPickPhotos: _onPickPhotos,
      onUploadFiles: _onPickFiles,
      onToggleLearningMode: _openInstructionInjectionPopover,
      onLongPressLearning: _showLearningPromptSheet,
      onClearContext: _onClearContext,
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
                _buildSelectionToolbarOverlay(),

                // Scroll navigation buttons
                _buildScrollButtons(),
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
    // Dispose ChatScrollController (handles scroll listener and user scroll timer cleanup)
    _scrollCtrl.dispose();
    _scrollController.dispose();
    try { _chatActionSub?.cancel(); } catch (_) {}
    // Dispose ChatController (handles stream cleanup)
    _chatController.dispose();
    // Dispose StreamController (handles throttle timers cleanup)
    _streamController.dispose();
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

  // ===========================================================================
  // END REGION: Streaming Chunk Handlers
  // NOTE: All stream handling methods have been migrated to ChatActions.
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
