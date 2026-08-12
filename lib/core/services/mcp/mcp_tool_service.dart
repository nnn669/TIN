import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:mcp_client/mcp_client.dart' as mcp;
import '../../providers/mcp_provider.dart';
import '../chat/chat_service.dart';
import '../../providers/assistant_provider.dart';
import '../../../utils/app_directories.dart';

class McpToolService extends ChangeNotifier {
  McpToolService();

  /// Maximum characters of a single MCP tool result that are replayed into
  /// the model context. Truncation is currently disabled per user request.
  @visibleForTesting
  static const int maxModelToolResultChars = 2147483647;

  /// Truncates a tool result for model consumption. Truncation is currently
  /// disabled; returns the input unchanged.
  @visibleForTesting
  static String truncateToolResultForModel(String text) {
    return text;
  }

  /// One-line summary of a tool result, injected above the full text so the
  /// model can decide whether the result is still worth reading in depth
  /// without paying to re-parse everything on every round.
  @visibleForTesting
  static String summarizeToolResultForModel(String text) {
    final lines = const LineSplitter()
        .convert(text)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '[result_summary] empty tool result.';
    String? preview;
    for (final l in lines) {
      if (l.length < 3 ||
          l.startsWith('{') ||
          l.startsWith('[') ||
          l.startsWith('}') ||
          l.startsWith(']') ||
          l.startsWith('"')) {
        continue;
      }
      preview = l;
      break;
    }
    preview ??= lines.first;
    if (preview.length > 160) {
      preview = '${preview.substring(0, 157)}...';
    }
    return '[result_summary] ${lines.length} non-empty line(s), '
        '${text.length} chars. Head: $preview';
  }

  /// Compacts a JSON-schema into a tiny field-name map for the model, instead
  /// of replaying the full (often large) schema on every argument error.
  @visibleForTesting
  static Map<String, dynamic> compactSchemaForModel(
    Map<String, dynamic> schema,
  ) {
    final props = schema['properties'];
    final names = (props is Map)
        ? props.keys.map((k) => k.toString()).toList()
        : const <String>[];
    final required = schema['required'];
    return <String, dynamic>{
      'type': schema['type'] ?? 'object',
      if (names.isNotEmpty) 'propertyNames': names,
      if (required is List && required.isNotEmpty) 'required': required,
      'note': 'full parameter schemas compacted to save context; use the '
          'listed property names for valid arguments.',
    };
  }

  static String _cutPreservingStructure(String text, int limit) {
    final trimmed = text.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      final structured = _cutStructuredJson(trimmed, limit);
      if (structured != null && structured.length < text.length) {
        return structured;
      }
    }
    final headChars = (limit * 0.6).round();
    final tailChars = (limit * 0.2).round();
    if (text.length <= headChars + tailChars) {
      return text.substring(0, limit);
    }
    final head = text.substring(0, headChars);
    final tail = text.substring(text.length - tailChars);
    final omitted = text.length - headChars - tailChars;
    return '$head\n[... $omitted chars omitted in the middle]\n$tail';
  }

  /// Keeps only structurally complete leading entries of a JSON document, so
  /// the model never receives a cut-off, unparseable JSON fragment. Returns
  /// null when the text is not JSON or nothing was dropped.
  static String? _cutStructuredJson(String text, int limit) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (decoded is List) {
      final buf = StringBuffer('[');
      var dropped = 0;
      for (final item in decoded) {
        final chunk = jsonEncode(item);
        final need = chunk.length + (buf.length > 1 ? 1 : 0) + 1;
        if (buf.length + need > limit) {
          dropped++;
          continue;
        }
        if (buf.length > 1) buf.write(',');
        buf.write(chunk);
      }
      if (dropped > 0) {
        final tail = ',"...${dropped} more item(s) omitted"]';
        if (buf.length + tail.length <= limit) {
          buf.write(tail);
        } else {
          buf.write(']');
        }
      } else {
        buf.write(']');
      }
      return buf.toString();
    }
    if (decoded is Map) {
      final buf = StringBuffer('{');
      var dropped = 0;
      for (final entry in decoded.entries) {
        final chunk = '"${entry.key}":${jsonEncode(entry.value)}';
        final need = chunk.length + (buf.length > 1 ? 1 : 0) + 1;
        if (buf.length + need > limit) {
          dropped++;
          continue;
        }
        if (buf.length > 1) buf.write(',');
        buf.write(chunk);
      }
      if (dropped > 0) {
        final tail = ',"...${dropped} more field(s) omitted"}';
        if (buf.length + tail.length <= limit) {
          buf.write(tail);
        } else {
          buf.write('}');
        }
      } else {
        buf.write('}');
      }
      return buf.toString();
    }
    return null;
  }

  List<McpToolConfig> listAvailableToolsForConversation(
    McpProvider mcpProvider,
    ChatService chat,
    String conversationId,
  ) {
    final selected = chat.getConversationMcpServers(conversationId).toSet();
    return mcpProvider.getEnabledToolsForServers(selected);
  }

  List<McpToolConfig> listAvailableToolsForAssistant(
    McpProvider mcpProvider,
    AssistantProvider assistants,
    String? assistantId,
  ) {
    final a = (assistantId != null)
        ? assistants.getById(assistantId)
        : assistants.currentAssistant;
    final selected = (a?.mcpServerIds ?? const <String>[]).toSet();
    return mcpProvider.getEnabledToolsForServers(selected);
  }

  Future<mcp.CallToolResult?> callToolForConversation(
    McpProvider mcpProvider,
    ChatService chat, {
    required String conversationId,
    required String toolName,
    Map<String, dynamic> arguments = const {},
  }) async {
    final selected = chat.getConversationMcpServers(conversationId).toSet();
    if (selected.isEmpty) return null;

    // Find a server that has this tool enabled
    final connected = mcpProvider.connectedServers
        .where((s) => selected.contains(s.id))
        .toList();
    for (final s in connected) {
      final has = s.tools.any((t) => t.enabled && t.name == toolName);
      if (has) {
        return await mcpProvider.callTool(s.id, toolName, arguments);
      }
    }
    return null;
  }

  // Convenience: call tool and flatten result contents to plain text
  Future<String> callToolTextForConversation(
    McpProvider mcpProvider,
    ChatService chat, {
    required String conversationId,
    required String toolName,
    Map<String, dynamic> arguments = const {},
  }) async {
    // Attempt call via selected server
    final selected = chat.getConversationMcpServers(conversationId).toSet();
    final connected = mcpProvider.connectedServers
        .where((s) => selected.contains(s.id))
        .toList();
    mcp.CallToolResult? res;
    McpServerConfig? usedServer;
    for (final s in connected) {
      final has = s.tools.any((t) => t.enabled && t.name == toolName);
      if (!has) continue;
      usedServer = s;
      res = await mcpProvider.callTool(s.id, toolName, arguments);
      break;
    }
    if (res == null) {
      if (usedServer != null) {
        final errMsg = mcpProvider.errorFor(usedServer.id) ?? 'Unknown error';
        final schema = usedServer.tools
            .firstWhere((t) => t.name == toolName)
            .schema;
        return _renderToolErrorForModel(
          serverName: usedServer.name,
          toolName: toolName,
          arguments: arguments,
          errorMessage: errMsg,
          schema: schema,
        );
      }
      return '';
    }
    final buf = StringBuffer();
    // Be liberal in what we accept: many servers return different content variants.
    for (final c in res.content) {
      try {
        // Known types from mcp_client
        if (c is mcp.TextContent) {
          if ((c.text).trim().isNotEmpty) buf.writeln(c.text);
          continue;
        }
        if (c is mcp.ResourceContent) {
          final t = (c.text ?? '').toString();
          if (t.trim().isNotEmpty) {
            buf.writeln(t);
          } else {
            final uri = (c.uri).toString();
            if (uri.isNotEmpty) buf.writeln('resource: $uri');
          }
          continue;
        }
        if (c is mcp.ImageContent) {
          final data = c.data.toString();
          final mime = c.mimeType.toString();
          if (data.isNotEmpty) {
            final savedPath = await AppDirectories.saveBase64Image(
              mime,
              data,
              prefix: 'mcp_img',
            );
            if (savedPath != null) {
              buf.writeln('[image:$savedPath]');
            }
          } else {
            final url = (c.url ?? '').toString();
            if (url.isNotEmpty) buf.writeln('[image:$url]');
          }
          continue;
        }
        // Try dynamic accessors that some adapters may expose
        final dyn = c as dynamic;
        try {
          final txt = (dyn.text as String?);
          if (txt != null && txt.trim().isNotEmpty) {
            buf.writeln(txt);
            continue;
          }
        } catch (_) {}
        try {
          final uri = (dyn.uri as String?);
          if (uri != null && uri.isNotEmpty) {
            buf.writeln('resource: $uri');
            continue;
          }
        } catch (_) {}
        // As a last resort, serialize to JSON if available
        try {
          final json = (dyn.toJson as dynamic).call();
          buf.writeln(const JsonEncoder.withIndent('  ').convert(json));
          continue;
        } catch (_) {}
        // Fallback to a readable string (avoid Instance of ... when possible)
        final s = c.toString();
        if (!s.startsWith('Instance of')) buf.writeln(s);
      } catch (_) {
        // ignore single content parse errors and continue
      }
    }
    final full = buf.toString().trim();
    if (full.isEmpty) {
      return _appendMcpErrorMarker(full, res.isError == true);
    }
    final summarized = '${summarizeToolResultForModel(full)}\n\n$full';
    return _appendMcpErrorMarker(
      truncateToolResultForModel(summarized),
      res.isError == true,
    );
  }

  Future<String> callToolTextForAssistant(
    McpProvider mcpProvider,
    AssistantProvider assistants, {
    required String? assistantId,
    required String toolName,
    Map<String, dynamic> arguments = const {},
  }) async {
    // try servers selected for the assistant
    final a = (assistantId != null)
        ? assistants.getById(assistantId)
        : assistants.currentAssistant;
    final selected = (a?.mcpServerIds ?? const <String>[]).toSet();
    if (selected.isEmpty) return '';
    for (final s in mcpProvider.connectedServers.where(
      (s) => selected.contains(s.id),
    )) {
      final has = s.tools.any((t) => t.enabled && t.name == toolName);
      if (has) {
        final res = await mcpProvider.callTool(s.id, toolName, arguments);
        if (res == null) {
          final errMsg = mcpProvider.errorFor(s.id) ?? 'Unknown error';
          final schema = s.tools.firstWhere((t) => t.name == toolName).schema;
          return _renderToolErrorForModel(
            serverName: s.name,
            toolName: toolName,
            arguments: arguments,
            errorMessage: errMsg,
            schema: schema,
          );
        }
        final buf = StringBuffer();
        for (final c in res.content) {
          try {
            if (c is mcp.TextContent) {
              if ((c.text).trim().isNotEmpty) buf.writeln(c.text);
              continue;
            }
            if (c is mcp.ResourceContent) {
              final t = (c.text ?? '').toString();
              if (t.trim().isNotEmpty) {
                buf.writeln(t);
              } else {
                final uri = (c.uri).toString();
                if (uri.isNotEmpty) buf.writeln('resource: $uri');
              }
              continue;
            }
            if (c is mcp.ImageContent) {
              final data = c.data.toString();
              final mime = c.mimeType.toString();
              if (data.isNotEmpty) {
                final savedPath = await AppDirectories.saveBase64Image(
                  mime,
                  data,
                  prefix: 'mcp_img',
                );
                if (savedPath != null) {
                  buf.writeln('[image:$savedPath]');
                }
              } else {
                final url = (c.url ?? '').toString();
                if (url.isNotEmpty) buf.writeln('[image:$url]');
              }
              continue;
            }
            final dyn = c as dynamic;
            try {
              final txt = (dyn.text as String?);
              if (txt != null && txt.trim().isNotEmpty) {
                buf.writeln(txt);
                continue;
              }
            } catch (_) {}
            try {
              final uri = (dyn.uri as String?);
              if (uri != null && uri.isNotEmpty) {
                buf.writeln('resource: $uri');
                continue;
              }
            } catch (_) {}
            try {
              final json = (dyn.toJson as dynamic).call();
              buf.writeln(const JsonEncoder.withIndent('  ').convert(json));
              continue;
            } catch (_) {}
            final s = c.toString();
            if (!s.startsWith('Instance of')) buf.writeln(s);
          } catch (_) {
            // ignore single content parse errors and continue
          }
        }
        final full = buf.toString().trim();
        if (full.isEmpty) {
          return _appendMcpErrorMarker(full, res.isError == true);
        }
        final summarized = '${summarizeToolResultForModel(full)}\n\n$full';
        return _appendMcpErrorMarker(
          truncateToolResultForModel(summarized),
          res.isError == true,
        );
      }
    }
    return '';
  }

  String _appendMcpErrorMarker(String text, bool isError) {
    if (!isError) return text;
    final payload = <String, dynamic>{
      'type': 'tool_error',
      'error': 'mcp_tool_error',
      'message': text.isEmpty ? 'MCP tool returned an error.' : text,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  String _renderToolErrorForModel({
    required String serverName,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String errorMessage,
    Map<String, dynamic>? schema,
  }) {
    // Provide a concise JSON for the model to self-correct and retry
    final map = <String, dynamic>{
      'type': 'tool_error',
      'error': 'invalid_arguments',
      'message': errorMessage,
      'tool': toolName,
      'server': serverName,
      'lastArguments': arguments,
      if (schema != null && schema.isNotEmpty)
        'parametersSchemaBrief': compactSchemaForModel(schema),
      'instruction':
          'Revise arguments to satisfy parametersSchemaBrief, then call the same tool again.',
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }
}