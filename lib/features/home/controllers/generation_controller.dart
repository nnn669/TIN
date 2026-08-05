import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/providers/model_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/api/tool_loop_guard.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../utils/assistant_regex.dart';
import '../../../core/models/assistant_regex.dart';
import '../services/message_builder_service.dart';
import '../services/ask_user_interaction_service.dart';
import '../services/tool_handler_service.dart';
import '../services/tool_approval_service.dart';
import 'chat_controller.dart';
import 'stream_controller.dart' as stream_ctrl;

/// Controller for coordinating message generation (send and regenerate).
///
/// This controller:
/// - Coordinates message sending and regeneration flows
/// - Uses MessageBuilderService to construct API messages
/// - Uses StreamController to handle streaming responses
/// - Uses ToolHandlerService to manage tool definitions and handlers
/// - Manages generation state (loading, streaming)
class GenerationController {
  GenerationController({
    required this.chatService,
    required this.chatController,
    required this.streamController,
    required this.messageBuilderService,
    required this.contextProvider,
    required this.onStateChanged,
    required this.getTitleForLocale,
  }) : toolHandlerService = ToolHandlerService(
         contextProvider: contextProvider,
       );

  final ChatService chatService;
  final ChatController chatController;
  final stream_ctrl.StreamController streamController;
  final MessageBuilderService messageBuilderService;

  /// Service for handling tool definitions and tool call execution
  final ToolHandlerService toolHandlerService;

  /// Build context (used for accessing providers)
  final BuildContext contextProvider;

  /// Callback when state changes (trigger setState in the widget)
  final VoidCallback onStateChanged;

  /// Function to get localized title
  final String Function(BuildContext context) getTitleForLocale;

  // ============================================================================
  // Tool Schema Sanitization (delegated to ToolHandlerService)
  // ============================================================================

  /// Sanitize/translate JSON Schema to each provider's accepted subset.
  /// Delegates to ToolHandlerService.sanitizeToolParametersForProvider.
  static Map<String, dynamic> sanitizeToolParametersForProvider(
    Map<String, dynamic> schema,
    ProviderKind kind,
  ) {
    return ToolHandlerService.sanitizeToolParametersForProvider(schema, kind);
  }

  // ============================================================================
  // Model Capability Checks
  // ============================================================================

  bool isReasoningModel(String providerKey, String modelId) {
    final settings = contextProvider.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(providerKey);
    final ov = cfg.modelOverrides[modelId] as Map?;
    if (ov != null && ov.containsKey('abilities')) {
      final abilities =
          (ov['abilities'] as List?)
              ?.map((e) => e.toString().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [];
      return abilities.contains('reasoning');
    }
    final inferred = ModelRegistry.infer(
      ModelInfo(id: modelId, displayName: modelId),
    );
    return inferred.abilities.contains(ModelAbility.reasoning);
  }

  bool isToolModel(String providerKey, String modelId) {
    final settings = contextProvider.read<SettingsProvider>();
    final cfg = settings.getProviderConfig(providerKey);
    final ov = cfg.modelOverrides[modelId] as Map?;
    if (ov != null && ov.containsKey('abilities')) {
      final abilities =
          (ov['abilities'] as List?)
              ?.map((e) => e.toString().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [];
      return abilities.contains('tool');
    }
    final inferred = ModelRegistry.infer(
      ModelInfo(id: modelId, displayName: modelId),
    );
    return inferred.abilities.contains(ModelAbility.tool);
  }

  bool isReasoningEnabled(int? budget) {
    if (budget == null) return true; // treat null as default/auto -> enabled
    if (budget == -1) return true; // auto
    return budget >= 1024;
  }

  // ============================================================================
  // Tool Definitions Builder (delegated to ToolHandlerService)
  // ============================================================================

  /// Prepare tool definitions for API call.
  /// Delegates to ToolHandlerService.buildToolDefinitions.
  List<Map<String, dynamic>> buildToolDefinitions(
    SettingsProvider settings,
    Assistant? assistant,
    String providerKey,
    String modelId,
    bool hasBuiltInSearch,
  ) {
    return toolHandlerService.buildToolDefinitions(
      settings,
      assistant,
      providerKey,
      modelId,
      hasBuiltInSearch,
      isToolModel: isToolModel,
    );
  }

  /// Build tool call handler function.
  ///
  /// Delegates execution to ToolHandlerService.buildToolCallHandler, then wraps
  /// it in a [ToolLoopGuard] so a single assistant turn cannot spin forever.
  ///
  /// Providers drive tool calls with unbounded `while (true)` loops and re-send
  /// the entire conversation plus every prior tool result on each round, so an
  /// unguarded loop bills the user until they hit stop. Executing a tool is the
  /// only way a provider can build its next round, which makes this wrapper the
  /// single choke point covering every provider and both the streaming and
  /// non-streaming paths.
  ///
  /// A fresh guard is created per call, and this method is invoked once per
  /// generation, so budgets are scoped to one assistant turn.
  ToolCallHandler? buildToolCallHandler(
    SettingsProvider settings,
    Assistant? assistant, {
    ToolApprovalService? approvalService,
    AskUserInteractionService? askUserService,
  }) {
    final inner = toolHandlerService.buildToolCallHandler(
      settings,
      assistant,
      approvalService: approvalService,
      askUserService: askUserService,
    );
    if (inner == null) return null;

    final guard = ToolLoopGuard();
    return (
      String name,
      Map<String, dynamic> args, {
      String? toolCallId,
    }) async {
      // Throws ToolLoopBudgetExceeded at the hard budget, which aborts the turn
      // instead of paying for another round.
      final refusal = guard.evaluate(name, args);
      if (refusal != null) return refusal;
      return inner(name, args, toolCallId: toolCallId);
    };
  }

  // ============================================================================
  // Custom Headers/Body Builders
  // ============================================================================

  /// Build custom headers from assistant settings.
  Map<String, String>? buildCustomHeaders(Assistant? assistant) {
    if ((assistant?.customHeaders.isNotEmpty ?? false)) {
      final headers = <String, String>{
        for (final e in assistant!.customHeaders)
          if ((e['name'] ?? '').trim().isNotEmpty)
            (e['name']!.trim()): (e['value'] ?? ''),
      };
      return headers.isEmpty ? null : headers;
    }
    return null;
  }

  /// Build custom body from assistant settings.
  Map<String, dynamic>? buildCustomBody(Assistant? assistant) {
    if ((assistant?.customBody.isNotEmpty ?? false)) {
      final body = <String, dynamic>{
        for (final e in assistant!.customBody)
          if ((e['key'] ?? '').trim().isNotEmpty)
            (e['key']!.trim()): (e['value'] ?? ''),
      };
      return body.isEmpty ? null : body;
    }
    return null;
  }

  // ============================================================================
  // Assistant Content Transform
  // ============================================================================

  /// Transform raw content using assistant regexes.
  String transformAssistantContent(String raw, Assistant? assistant) {
    return applyAssistantRegexes(
      raw,
      assistant: assistant,
      scope: AssistantRegexScope.assistant,
      target: AssistantRegexTransformTarget.persist,
    );
  }

  // ============================================================================
  // Generation Context Builder
  // ============================================================================

  /// Build generation context with all necessary data for streaming.
  stream_ctrl.GenerationContext buildGenerationContext({
    required ChatMessage assistantMessage,
    required List<Map<String, dynamic>> apiMessages,
    required List<String> userImagePaths,
    required bool allowImagesApiRouting,
    required String providerKey,
    required String modelId,
    required Assistant? assistant,
    required SettingsProvider settings,
    required ProviderConfig config,
    required List<Map<String, dynamic>> toolDefs,
    ToolCallHandler? onToolCall,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
    required bool supportsReasoning,
    required bool enableReasoning,
    required bool streamOutput,
    bool generateTitleOnFinish = true,
  }) {
    final bool ocrActive =
        settings.ocrEnabled &&
        settings.ocrModelProvider != null &&
        settings.ocrModelId != null;

    return stream_ctrl.GenerationContext(
      assistantMessage: assistantMessage,
      apiMessages: apiMessages,
      userImagePaths: userImagePaths,
      allowImagesApiRouting: allowImagesApiRouting,
      providerKey: providerKey,
      modelId: modelId,
      assistant: assistant,
      settings: settings,
      config: config,
      toolDefs: toolDefs,
      onToolCall: onToolCall,
      extraHeaders: extraHeaders,
      extraBody: extraBody,
      supportsReasoning: supportsReasoning,
      enableReasoning: enableReasoning,
      streamOutput: streamOutput,
      ocrActive: ocrActive,
      generateTitleOnFinish: generateTitleOnFinish,
    );
  }
}