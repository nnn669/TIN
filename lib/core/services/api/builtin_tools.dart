import '../../providers/settings_provider.dart';

/// Built-in tool name constants for API integrations.
/// Use these constants instead of raw strings to ensure consistency.
abstract class BuiltInToolNames {
  // Common
  static const search = 'search';

  // Google/Gemini specific
  static const urlContext = 'url_context';
  static const codeExecution = 'code_execution';
  static const youtube = 'youtube';

  // OpenAI specific
  static const codeInterpreter = 'code_interpreter';
  static const imageGeneration = 'image_generation';

  /// Normalize a tool name to snake_case format.
  /// Handles legacy camelCase formats for backward compatibility.
  static String normalize(String name) {
    final lower = name.trim().toLowerCase();
    switch (lower) {
      case 'urlcontext':
        return urlContext;
      case 'codeexecution':
        return codeExecution;
      case 'codeinterpreter':
        return codeInterpreter;
      case 'imagegeneration':
        return imageGeneration;
      default:
        return lower;
    }
  }

  /// Parse a list of tool names and normalize them.
  static Set<String> parseAndNormalize(List<dynamic>? list) {
    if (list == null || list.isEmpty) return const <String>{};
    return list
        .map((e) => normalize(e.toString()))
        .where((e) => e.isNotEmpty)
        .toSet();
  }
}

/// Utility class for checking provider-specific built-in tool support.
abstract class BuiltInToolsHelper {
  /// Check if a provider supports built-in tools configuration.
  static bool supportsBuiltInTools(ProviderKind kind) {
    return kind == ProviderKind.google || kind == ProviderKind.openai;
  }

  /// Check if the provider/model combination supports search tool.
  static bool supportsSearch({
    required ProviderKind kind,
    required bool useResponseApi,
    String? modelId,
  }) {
    switch (kind) {
      case ProviderKind.google:
        return true;
      case ProviderKind.claude:
        return true;
      case ProviderKind.openai:
        // OpenAI requires Responses API, or Grok models
        if (useResponseApi) return true;
        if (modelId != null && modelId.toLowerCase().contains('grok')) return true;
        return false;
    }
  }

  /// Get active built-in tools from model overrides.
  static BuiltInToolsState getActiveTools({
    required ProviderConfig? cfg,
    required String? modelId,
  }) {
    if (cfg == null || modelId == null) {
      return const BuiltInToolsState();
    }

    final kind = ProviderConfig.classify(cfg.id, explicitType: cfg.providerType);
    final ov = cfg.modelOverrides[modelId] as Map?;
    final list = (ov?['builtInTools'] as List?) ?? const <dynamic>[];
    final builtInSet = BuiltInToolNames.parseAndNormalize(list);

    bool searchActive = builtInSet.contains(BuiltInToolNames.search);
    bool codeExecutionActive = false;
    bool urlContextActive = false;
    bool youtubeActive = false;
    bool codeInterpreterActive = false;
    bool imageGenerationActive = false;

    if (kind == ProviderKind.google) {
      codeExecutionActive = builtInSet.contains(BuiltInToolNames.codeExecution);
      urlContextActive = builtInSet.contains(BuiltInToolNames.urlContext);
      youtubeActive = builtInSet.contains(BuiltInToolNames.youtube);
    } else if (kind == ProviderKind.openai) {
      codeInterpreterActive = builtInSet.contains(BuiltInToolNames.codeInterpreter);
      imageGenerationActive = builtInSet.contains(BuiltInToolNames.imageGeneration);
    }

    return BuiltInToolsState(
      searchActive: searchActive,
      codeExecutionActive: codeExecutionActive,
      urlContextActive: urlContextActive,
      youtubeActive: youtubeActive,
      codeInterpreterActive: codeInterpreterActive,
      imageGenerationActive: imageGenerationActive,
    );
  }
}

/// State class representing active built-in tools.
class BuiltInToolsState {
  final bool searchActive;
  final bool codeExecutionActive;
  final bool urlContextActive;
  final bool youtubeActive;
  final bool codeInterpreterActive;
  final bool imageGenerationActive;

  const BuiltInToolsState({
    this.searchActive = false,
    this.codeExecutionActive = false,
    this.urlContextActive = false,
    this.youtubeActive = false,
    this.codeInterpreterActive = false,
    this.imageGenerationActive = false,
  });

  /// Returns true if any Gemini-specific built-in tool is active.
  bool get anyGeminiToolActive => codeExecutionActive || urlContextActive || youtubeActive;

  /// Returns true if any built-in tool that conflicts with MCP is active.
  bool get anyMcpConflictingToolActive => searchActive || codeExecutionActive || urlContextActive;
}
