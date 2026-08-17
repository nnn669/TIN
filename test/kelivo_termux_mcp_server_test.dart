import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tin/core/services/mcp/kelivo_termux/kelivo_termux_server.dart';

void main() {
  group('KelivoTermuxMcpServerEngine', () {
    test('lists one controlled Termux command tool', () async {
      final engine = KelivoTermuxMcpServerEngine(isSupported: () => true);
      addTearDown(engine.close);

      final response =
          await engine.handleMessage({
                'jsonrpc': '2.0',
                'id': 1,
                'method': 'tools/list',
              })
              as Map<String, dynamic>;
      final tools = response['result']['tools'] as List;
      final tool = tools.single as Map;
      final schema = tool['inputSchema'] as Map;

      expect(tool['name'], 'termux_run_command');
      expect(schema['required'], const ['command']);
      expect(schema['properties']['arguments']['maxItems'], 64);
      expect(schema['properties']['timeout_seconds']['maximum'], 25);
    });

    test(
      'returns stdout and forces result-producing background mode',
      () async {
        late Map<String, dynamic> received;
        final engine = KelivoTermuxMcpServerEngine(
          isSupported: () => true,
          executor:
              ({
                required command,
                required arguments,
                required workingDirectory,
                required background,
                required timeoutSeconds,
              }) async {
                received = {
                  'command': command,
                  'arguments': arguments,
                  'workingDirectory': workingDirectory,
                  'background': background,
                  'timeoutSeconds': timeoutSeconds,
                };
                return {
                  'success': true,
                  'exitCode': 0,
                  'stdout': 'clean\n',
                  'stderr': '',
                };
              },
        );
        addTearDown(engine.close);

        final response =
            await engine.handleMessage({
                  'jsonrpc': '2.0',
                  'id': 2,
                  'method': 'tools/call',
                  'params': {
                    'name': 'termux_run_command',
                    'arguments': {
                      'command': 'git',
                      'arguments': ['status', '--short'],
                      'working_directory':
                          '/data/data/com.termux/files/home/project',
                      'timeout_seconds': 20,
                    },
                  },
                })
                as Map<String, dynamic>;
        final result = response['result'] as Map<String, dynamic>;
        final payload =
            jsonDecode(result['content'][0]['text'] as String) as Map;

        expect(received['background'], isTrue);
        expect(received['timeoutSeconds'], 20);
        expect(received['arguments'], const ['status', '--short']);
        expect(result['isError'], isFalse);
        expect(payload['exitCode'], 0);
        expect(payload['stdout'], 'clean\n');
      },
    );

    test('marks non-zero exit as an MCP error with stderr intact', () async {
      final engine = KelivoTermuxMcpServerEngine(
        isSupported: () => true,
        executor:
            ({
              required command,
              required arguments,
              required workingDirectory,
              required background,
              required timeoutSeconds,
            }) async => {
              'success': false,
              'exitCode': 2,
              'stdout': '',
              'stderr': 'bad option',
            },
      );
      addTearDown(engine.close);

      final response =
          await engine.handleMessage({
                'jsonrpc': '2.0',
                'id': 3,
                'method': 'tools/call',
                'params': {
                  'name': 'termux_run_command',
                  'arguments': {'command': 'git'},
                },
              })
              as Map<String, dynamic>;
      final result = response['result'] as Map<String, dynamic>;
      final payload = jsonDecode(result['content'][0]['text'] as String) as Map;

      expect(result['isError'], isTrue);
      expect(payload['exitCode'], 2);
      expect(payload['stderr'], 'bad option');
    });

    test('rejects invalid arguments without invoking Android', () async {
      var invoked = false;
      final engine = KelivoTermuxMcpServerEngine(
        isSupported: () => true,
        executor:
            ({
              required command,
              required arguments,
              required workingDirectory,
              required background,
              required timeoutSeconds,
            }) async {
              invoked = true;
              return <String, dynamic>{};
            },
      );
      addTearDown(engine.close);

      final response =
          await engine.handleMessage({
                'jsonrpc': '2.0',
                'id': 4,
                'method': 'tools/call',
                'params': {
                  'name': 'termux_run_command',
                  'arguments': {'command': 'echo', 'arguments': 'hello'},
                },
              })
              as Map<String, dynamic>;
      final result = response['result'] as Map<String, dynamic>;

      expect(invoked, isFalse);
      expect(result['isError'], isTrue);
      expect(result['content'][0]['text'], contains('invalid_arguments'));
    });

    test('rejects timeout outside the bounded result window', () async {
      var invoked = false;
      final engine = KelivoTermuxMcpServerEngine(
        isSupported: () => true,
        executor:
            ({
              required command,
              required arguments,
              required workingDirectory,
              required background,
              required timeoutSeconds,
            }) async {
              invoked = true;
              return <String, dynamic>{};
            },
      );
      addTearDown(engine.close);

      final response =
          await engine.handleMessage({
                'jsonrpc': '2.0',
                'id': 5,
                'method': 'tools/call',
                'params': {
                  'name': 'termux_run_command',
                  'arguments': {'command': 'sleep', 'timeout_seconds': 26},
                },
              })
              as Map<String, dynamic>;
      final result = response['result'] as Map<String, dynamic>;

      expect(invoked, isFalse);
      expect(result['isError'], isTrue);
      expect(result['content'][0]['text'], contains('invalid_arguments'));
    });

    test('returns explicit unsupported-platform failure', () async {
      final engine = KelivoTermuxMcpServerEngine(isSupported: () => false);
      addTearDown(engine.close);

      final response =
          await engine.handleMessage({
                'jsonrpc': '2.0',
                'id': 6,
                'method': 'tools/call',
                'params': {
                  'name': 'termux_run_command',
                  'arguments': {'command': 'pwd'},
                },
              })
              as Map<String, dynamic>;
      final result = response['result'] as Map<String, dynamic>;

      expect(result['isError'], isTrue);
      expect(result['content'][0]['text'], contains('unsupported_platform'));
    });

    test('turns executor timeout into a stable MCP error', () async {
      final engine = KelivoTermuxMcpServerEngine(
        isSupported: () => true,
        executor:
            ({
              required command,
              required arguments,
              required workingDirectory,
              required background,
              required timeoutSeconds,
            }) => throw TimeoutException('late'),
      );
      addTearDown(engine.close);

      final response =
          await engine.handleMessage({
                'jsonrpc': '2.0',
                'id': 7,
                'method': 'tools/call',
                'params': {
                  'name': 'termux_run_command',
                  'arguments': {'command': 'sleep'},
                },
              })
              as Map<String, dynamic>;
      final result = response['result'] as Map<String, dynamic>;

      expect(result['isError'], isTrue);
      expect(result['content'][0]['text'], contains('termux_timeout'));
    });
  });
}
