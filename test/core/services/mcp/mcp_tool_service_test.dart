import 'package:flutter_test/flutter_test.dart';
import 'package:tin/core/providers/mcp_provider.dart';
import 'package:tin/core/services/mcp/mcp_tool_service.dart';

void main() {
  group('McpToolService effective assistant servers', () {
    test('adds Termux for every Android assistant', () {
      final selected = McpToolService.effectiveAssistantServerIds(
        const <String>['custom-server'],
        includeBuiltinTermux: true,
      );

      expect(
        selected,
        containsAll(<String>['custom-server', McpProvider.builtinTermuxId]),
      );
    });

    test('does not add Termux outside Android', () {
      final selected = McpToolService.effectiveAssistantServerIds(
        const <String>['custom-server'],
        includeBuiltinTermux: false,
      );

      expect(selected, isNot(contains(McpProvider.builtinTermuxId)));
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
      final compact = McpToolService.compactSchemaForModel({'type': 'object'});
      expect(compact['type'], 'object');
      expect(compact.containsKey('propertyNames'), isFalse);
    });
  });
}
