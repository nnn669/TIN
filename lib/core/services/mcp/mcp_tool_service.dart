import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:mcp_client/mcp_client.dart' as mcp;
import '../../providers/mcp_provider.dart';
import '../chat/chat_service.dart';
import '../../providers/assistant_provider.dart';
import '../../../utils/app_directories.dart';

class McpToolService extends ChangeNotifier {
  McpToolService();

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
    return _appendMcpErrorMarker(buf.toString().trim(), res.isError == true);
  }

  Future<String> callToolTextForAssistant(
    McpProvider mcpProvider,
    AssistantProvider assistants, {
    required String? assistantId,
    required String toolName,
    Map<String, dynamic> arguments = const {},
  }) async {
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
        return _appendMcpErrorMarker(
          buf.toString().trim(),
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