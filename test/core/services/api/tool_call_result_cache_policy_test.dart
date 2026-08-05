import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tin/core/services/api/tool_loop_guard.dart';

void main() {
  group('ToolCallResultCache read-only policy', () {
    test('caches only explicitly read-only web tools', () async {
      const readOnlyNames = [
        'search_web',
        'fetch_html',
        'fetch_markdown',
        'fetch_txt',
        'fetch_json',
        'tool_kelivo_fetch_html',
        'tool_kelivo_fetch_markdown',
        'tool_kelivo_fetch_txt',
        'tool_kelivo_fetch_json',
        'tool_kelivo-fetch_html',
      ];

      for (final name in readOnlyNames) {
        expect(ToolLoopGuard.isReadOnlyCacheTool(name), isTrue, reason: name);
      }
    });

    test('does not cache memory, gateway, local, or arbitrary MCP tools', () async {
      const sideEffectNames = [
        'create_memory',
        'edit_memory',
        'delete_memory',
        'kelivo_app_control',
        'clipboard_write',
        'arbitrary_mcp_tool',
      ];
      for (final name in sideEffectNames) {
        expect(ToolLoopGuard.isReadOnlyCacheTool(name), isFalse, reason: name);
      }

      final cache = ToolCallResultCache();
      var executions = 0;
      final args = {'content': 'same'};

      Future<String> execute() async {
        executions++;
        return 'result-$executions';
      }

      expect(await cache.run('create_memory', args, execute), 'result-1');
      expect(await cache.run('create_memory', args, execute), 'result-2');
      expect(cache.lookup('create_memory', args), isNull);
      expect(executions, 2);
    });

    test('recognizes mapped Kelivo Fetch names without broad prefix matching', () {
      expect(
        ToolLoopGuard.isReadOnlyCacheTool('tool_kelivo_fetch_json'),
        isTrue,
      );
      expect(
        ToolLoopGuard.isReadOnlyCacheTool('tool_kelivo_fetch_delete'),
        isFalse,
      );
      expect(
        ToolLoopGuard.isReadOnlyCacheTool('tool_kelivo_fetch_execute'),
        isFalse,
      );
    });

    test('does not cache JSON error-shaped search or MCP results', () async {
      final cache = ToolCallResultCache();
      var executions = 0;
      final args = {'url': 'https://example.com/retry'};

      final failed = await cache.run('fetch_txt', args, () async {
        executions++;
        return jsonEncode({'error': 'network'});
      });
      final recovered = await cache.run('fetch_txt', args, () async {
        executions++;
        return 'recovered';
      });

      expect(jsonDecode(failed), isA<Map>());
      expect(recovered, 'recovered');
      expect(executions, 2);
    });
  });
}