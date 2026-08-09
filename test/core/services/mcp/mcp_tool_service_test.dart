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

    test('oversized result is truncated with a marker and kept head', () {
      final limit = McpToolService.maxModelToolResultChars;
      final text = 'HEAD${'x' * (limit + 1000)}';
      final result = McpToolService.truncateToolResultForModel(text);

      expect(result, startsWith('HEAD'));
      expect(result, contains('[mcp_tool_result_truncated:'));
      expect(result.length, lessThan(text.length));
      expect(result.length, greaterThan(limit));
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
  });
}