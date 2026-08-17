import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/mcp/mcp_tool_service.dart';

void main() {
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