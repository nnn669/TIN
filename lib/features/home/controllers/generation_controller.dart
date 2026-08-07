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
  final ToolHandlerService toolHandlerService;
  final BuildContext contextProvider;
  final VoidCallback onStateChanged;
  final String Function(BuildContext context) getTitleForLocale;

  static Map sanitizeToolParametersForProvider(
    Map schema,
    ProviderKind kind,
  ) {
    return ToolHandlerService.sanitizeToolParametersForProvider(schema, kind);
  }

  bool isReasoningModel(String providerKey, String modelId) {
    final settings = contextProvider.read<SettingsProvider>();
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
      final abilities = (ov['abilities'] as List?)
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
    if (budget == null) return true;
    if (budget == -1) return true;
    return budget >= 1024;
  }

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

  /// Build the guarded tool handler used by every provider path.
  ///
  /// Tool calls are unlimited within one assistant turn; the guard keeps a
  /// fresh per-turn counter so the next user message starts from zero. The
  /// read-only result cache reuses successful web/search results by their
  /// complete tool signature. Different arguments, split subtasks, and failed
  /// calls remain independent.
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
    final toolLoopGuard = ToolLoopGuard();
    final toolCallResultCache = ToolCallResultCache();
    return (
      String name,
      Map args, {
      String? toolCallId,
    }) async {
      // Tool calls are unlimited; the guard only tracks the per-response
      // call count for observability.
      toolLoopGuard.evaluate(name, args);
      final cached = toolCallResultCache.lookup(name, args);
      if (cached != null) return cached;
      return toolCallResultCache.run(
        name,
        args,
        () => inner(name, args, toolCallId: toolCallId),
      );
    };
  }

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

  String transformAssistantContent(String raw, Assistant? assistant) {
    return applyAssistantRegexes(
      raw,
      assistant: assistant,
      scope: AssistantRegexScope.assistant,
      target: AssistantRegexTransformTarget.persist,
    );
  }

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
    final bool ocrActive = settings.ocrEnabled &&
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