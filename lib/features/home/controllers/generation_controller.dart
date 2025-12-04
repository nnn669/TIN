import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/memory_provider.dart';
import '../../../core/providers/model_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/mcp/mcp_tool_service.dart';
import '../../../core/services/search/search_tool_service.dart';
import '../../../utils/assistant_regex.dart';
import '../../../core/models/assistant_regex.dart';
import '../services/message_builder_service.dart';
import 'chat_controller.dart';
import 'stream_controller.dart' as stream_ctrl;

/// Controller for coordinating message generation (send and regenerate).
///
/// This controller:
/// - Coordinates message sending and regeneration flows
/// - Uses MessageBuilderService to construct API messages
/// - Uses StreamController to handle streaming responses
/// - Manages tool definitions and handlers
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
  });

  final ChatService chatService;
  final ChatController chatController;
  final stream_ctrl.StreamController streamController;
  final MessageBuilderService messageBuilderService;

  /// Build context (used for accessing providers)
  final BuildContext contextProvider;

  /// Callback when state changes (trigger setState in the widget)
  final VoidCallback onStateChanged;

  /// Function to get localized title
  final String Function(BuildContext context) getTitleForLocale;

  // ============================================================================
  // Tool Schema Sanitization (moved from home_page.dart)
  // ============================================================================

  /// Sanitize/translate JSON Schema to each provider's accepted subset.
  static Map<String, dynamic> sanitizeToolParametersForProvider(
    Map<String, dynamic> schema,
    ProviderKind kind,
  ) {
    Map<String, dynamic> clone = _deepCloneMap(schema);
    clone = _sanitizeNode(clone, kind) as Map<String, dynamic>;
    return clone;
  }

  static dynamic _sanitizeNode(dynamic node, ProviderKind kind) {
    if (node is List) {
      return node.map((e) => _sanitizeNode(e, kind)).toList();
    }
    if (node is! Map) return node;

    final m = Map<String, dynamic>.from(node);
    m.remove(r'$schema');
    if (m.containsKey('const')) {
      final v = m['const'];
      if (v is String || v is num || v is bool) {
        m['enum'] = [v];
      }
      m.remove('const');
    }
    for (final key in ['anyOf', 'oneOf', 'allOf', 'any_of', 'one_of', 'all_of']) {
      if (m[key] is List && (m[key] as List).isNotEmpty) {
        final first = (m[key] as List).first;
        final flattened = _sanitizeNode(first, kind);
        m.remove(key);
        if (flattened is Map<String, dynamic>) {
          m
            ..remove('type')
            ..remove('properties')
            ..remove('items');
          m.addAll(flattened);
        }
      }
    }
    final t = m['type'];
    if (t is List && t.isNotEmpty) m['type'] = t.first.toString();
    final items = m['items'];
    if (items is List && items.isNotEmpty) m['items'] = items.first;
    if (m['items'] is Map) m['items'] = _sanitizeNode(m['items'], kind);
    if (m['properties'] is Map) {
      final props = Map<String, dynamic>.from(m['properties']);
      final norm = <String, dynamic>{};
      props.forEach((k, v) {
        norm[k] = _sanitizeNode(v, kind);
      });
      m['properties'] = norm;
    }
    Set<String> allowed;
    switch (kind) {
      case ProviderKind.google:
        allowed = {'type', 'description', 'properties', 'required', 'items', 'enum'};
        break;
      case ProviderKind.openai:
      case ProviderKind.claude:
        allowed = {'type', 'description', 'properties', 'required', 'items', 'enum'};
        break;
    }
    m.removeWhere((k, v) => !allowed.contains(k));
    return m;
  }

  static Map<String, dynamic> _deepCloneMap(Map<String, dynamic> input) {
    return jsonDecode(jsonEncode(input)) as Map<String, dynamic>;
  }

  // ============================================================================
  // Model Capability Checks
  // ============================================================================

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
    final inferred = ModelRegistry.infer(ModelInfo(id: modelId, displayName: modelId));
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
    final inferred = ModelRegistry.infer(ModelInfo(id: modelId, displayName: modelId));
    return inferred.abilities.contains(ModelAbility.tool);
  }

  bool isReasoningEnabled(int? budget) {
    if (budget == null) return true; // treat null as default/auto -> enabled
    if (budget == -1) return true; // auto
    return budget >= 1024;
  }

  // ============================================================================
  // Tool Definitions Builder
  // ============================================================================

  /// Prepare tool definitions for API call.
  List<Map<String, dynamic>> buildToolDefinitions(
    SettingsProvider settings,
    Assistant? assistant,
    String providerKey,
    String modelId,
    bool hasBuiltInSearch,
  ) {
    final List<Map<String, dynamic>> toolDefs = <Map<String, dynamic>>[];
    final supportsTools = isToolModel(providerKey, modelId);

    // Search tool (skip when Gemini built-in search is active)
    if (settings.searchEnabled && !hasBuiltInSearch && supportsTools) {
      toolDefs.add(SearchToolService.getToolDefinition());
    }

    // Memory tools
    if (assistant?.enableMemory == true && supportsTools) {
      toolDefs.addAll([
        {
          'type': 'function',
          'function': {
            'name': 'create_memory',
            'description': 'create a memory record',
            'parameters': {
              'type': 'object',
              'properties': {
                'content': {'type': 'string', 'description': 'The content of the memory record'}
              },
              'required': ['content']
            }
          }
        },
        {
          'type': 'function',
          'function': {
            'name': 'edit_memory',
            'description': 'update a memory record',
            'parameters': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer', 'description': 'The id of the memory record'},
                'content': {'type': 'string', 'description': 'The content of the memory record'}
              },
              'required': ['id', 'content']
            }
          }
        },
        {
          'type': 'function',
          'function': {
            'name': 'delete_memory',
            'description': 'delete a memory record',
            'parameters': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer', 'description': 'The id of the memory record'}
              },
              'required': ['id']
            }
          }
        },
      ]);
    }

    // MCP tools
    final mcp = contextProvider.read<McpProvider>();
    final toolSvc = contextProvider.read<McpToolService>();
    final tools = toolSvc.listAvailableToolsForAssistant(mcp, contextProvider.read<AssistantProvider>(), assistant?.id);
    if (supportsTools && tools.isNotEmpty) {
      final providerCfg = settings.getProviderConfig(providerKey);
      final providerKind = ProviderConfig.classify(providerCfg.id, explicitType: providerCfg.providerType);
      toolDefs.addAll(tools.map((t) {
        Map<String, dynamic> baseSchema;
        if (t.schema != null && t.schema!.isNotEmpty) {
          baseSchema = Map<String, dynamic>.from(t.schema!);
        } else {
          final props = <String, dynamic>{for (final p in t.params) p.name: {'type': (p.type ?? 'string')}};
          final required = [for (final p in t.params.where((e) => e.required)) p.name];
          baseSchema = {'type': 'object', 'properties': props, if (required.isNotEmpty) 'required': required};
        }
        final sanitized = sanitizeToolParametersForProvider(baseSchema, providerKind);
        return {
          'type': 'function',
          'function': {
            'name': t.name,
            if ((t.description ?? '').isNotEmpty) 'description': t.description,
            'parameters': sanitized,
          }
        };
      }));
    }

    return toolDefs;
  }

  /// Build tool call handler function.
  Future<String> Function(String, Map<String, dynamic>)? buildToolCallHandler(
    SettingsProvider settings,
    Assistant? assistant,
  ) {
    final mcp = contextProvider.read<McpProvider>();
    final toolSvc = contextProvider.read<McpToolService>();

    return (name, args) async {
      // Search tool
      if (name == SearchToolService.toolName && settings.searchEnabled) {
        final q = (args['query'] ?? '').toString();
        return await SearchToolService.executeSearch(q, settings);
      }
      // Memory tools
      if (assistant?.enableMemory == true) {
        try {
          final mp = contextProvider.read<MemoryProvider>();
          if (name == 'create_memory') {
            final content = (args['content'] ?? '').toString();
            if (content.isEmpty) return '';
            final m = await mp.add(assistantId: assistant!.id, content: content);
            return m.content;
          } else if (name == 'edit_memory') {
            final id = (args['id'] as num?)?.toInt() ?? -1;
            final content = (args['content'] ?? '').toString();
            if (id <= 0 || content.isEmpty) return '';
            final m = await mp.update(id: id, content: content);
            return m?.content ?? '';
          } else if (name == 'delete_memory') {
            final id = (args['id'] as num?)?.toInt() ?? -1;
            if (id <= 0) return '';
            final ok = await mp.delete(id: id);
            return ok ? 'deleted' : '';
          }
        } catch (_) {}
      }
      // MCP tools
      final text = await toolSvc.callToolTextForAssistant(
        mcp,
        contextProvider.read<AssistantProvider>(),
        assistantId: assistant?.id,
        toolName: name,
        arguments: args,
      );
      return text;
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
          if ((e['name'] ?? '').trim().isNotEmpty) (e['name']!.trim()): (e['value'] ?? '')
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
            (e['key']!.trim()): (e['value'] ?? '')
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
      visual: false,
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
    required String providerKey,
    required String modelId,
    required Assistant? assistant,
    required SettingsProvider settings,
    required ProviderConfig config,
    required List<Map<String, dynamic>> toolDefs,
    Future<String> Function(String, Map<String, dynamic>)? onToolCall,
    Map<String, String>? extraHeaders,
    Map<String, dynamic>? extraBody,
    required bool supportsReasoning,
    required bool enableReasoning,
    required bool streamOutput,
    bool generateTitleOnFinish = true,
  }) {
    return stream_ctrl.GenerationContext(
      assistantMessage: assistantMessage,
      apiMessages: apiMessages,
      userImagePaths: userImagePaths,
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
      generateTitleOnFinish: generateTitleOnFinish,
    );
  }
}
