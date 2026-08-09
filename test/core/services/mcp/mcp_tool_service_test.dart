import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';

void main() {
  group('McpToolService.truncateToolResultForModel', () {
    test('short results pass through unchanged', () {
      const text = 'ok';
      expect(McpToolService.truncateToolResultForModel(text), text);
    });

    test('empty and tiny inputs are untouched', () {
      expect(McpToolService.truncateToolResultForModel(''), '');
      expect(
        McpToolService.truncateToolResultForModel('a' * 10),
        'a' * 10,
      );
    });

    test('result at exactly the limit is preserved', () {
      final limit = McpToolService.maxModelToolResultChars;
      final text = 'x' * limit;
      expect(McpToolService.truncateToolResultForModel(text), text);
    });

    test('oversized plain text keeps head and tail with a marker', () {
      final limit = McpToolService.maxModelToolResultChars;
      final text = 'HEAD${'x' * (limit + 500)}TAILEND';
      final result = McpToolService.truncateToolResultForModel(text);

      expect(result, startsWith('HEAD'));
      expect(result, contains('TAILEND'));
      expect(result, contains('[mcp_tool_result_truncated:'));
      expect(result.length, lessThan(text.length));
      expect(result.length, lessThan(limit + 400));
    });

    test('marker carries the original length for model diagnostics', () {
      final limit = McpToolService.maxModelToolResultChars;
      final text = 'y' * (limit + 500);
      final result = McpToolService.truncateToolResultForModel(text);
      expect(
        result,
        contains('${text.length} chars total'),
      );
    });

    test('oversized JSON array keeps complete leading items', () {
      final limit = McpToolService.maxModelToolResultChars;
      final items = List.generate(200, (i) => {'id': i, 'v': 'x' * 100});
      final text = jsonEncode(items);
      expect(text.length, greaterThan(limit));

      final result = McpToolService.truncateToolResultForModel(text);
      final marker = result.indexOf('\n\n[mcp_tool_result_truncated:');
      final kept = result.substring(0, marker);

      expect(kept, startsWith('['));
      expect(() => jsonDecode(kept), returnsNormally);
      expect(kept.length, lessThan(limit));
    });

    test('oversized JSON object keeps complete fields', () {
      final limit = McpToolService.maxModelToolResultChars;
      final map = {
        for (var i = 0; i < 200; i++) 'k$i': 'v${'x' * 100}',
      };
      final text = jsonEncode(map);
      expect(text.length, greaterThan(limit));

      final result = McpToolService.truncateToolResultForModel(text);
      final marker = result.indexOf('\n\n[mcp_tool_result_truncated:');
      final kept = result.substring(0, marker);

      expect(kept, startsWith('{'));
      expect(() => jsonDecode(kept), returnsNormally);
      expect(kept.length, lessThan(limit));
    });
  });

  group('McpToolService.summarizeToolResultForModel', () {
    test('empty text yields an empty marker line', () {
      final s = McpToolService.summarizeToolResultForModel('');
      expect(s, contains('[result_summary]'));
      expect(s, contains('empty'));
    });

    test('first meaningful line is used as preview', () {
      final s = McpToolService.summarizeToolResultForModel(
        '{\n  "a": 1\n}\nFound 42 results\nnext',
      );
      expect(s, contains('Found 42 results'));
      expect(s, contains('5 non-empty line(s)'));
    });

    test('long preview is capped', () {
      final s = McpToolService.summarizeToolResultForModel('x' * 500);
      expect(s, contains('Head: ${'x' * 157}...'));
    });
  });

  group('McpToolService.compactSchemaForModel', () {
    test('property names and required are extracted', () {
      final compact = McpToolService.compactSchemaForModel({
        'type': 'object',
        'properties': {'q': {}, 'limit': {}},
        'required': ['q'],
      });
      expect(compact['type'], 'object');
      expect(compact['propertyNames'], ['q', 'limit']);
      expect(compact['required'], ['q']);
    });

    test('falls back to type only without properties', () {
      final compact =
          McpToolService.compactSchemaForModel({'type': 'object'});
      expect(compact['type'], 'object');
      expect(compact.containsKey('propertyNames'), isFalse);
    });
  });
}