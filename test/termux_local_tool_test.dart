import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tin/core/models/assistant.dart';
import 'package:tin/core/services/termux_command.dart';
import 'package:tin/features/home/services/local_tools_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const assistant = Assistant(
    id: 'termux-assistant',
    name: 'Termux assistant',
    localToolIds: [LocalToolNames.termuxRunCommand],
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TermuxCommand.channel, null);
  });

  test('exposes the Termux command schema only when explicitly enabled', () {
    final disabled = LocalToolsService.buildToolDefinitions(
      assistant: const Assistant(id: 'disabled', name: 'Disabled'),
      supportsTools: true,
    );
    final enabled = LocalToolsService.buildToolDefinitions(
      assistant: assistant,
      supportsTools: true,
    );

    expect(disabled, isEmpty);
    expect(enabled.single['function']['name'], LocalToolNames.termuxRunCommand);
    final parameters = enabled.single['function']['parameters'];
    expect(parameters['required'], const ['command']);
    expect(parameters['properties']['arguments']['items']['type'], 'string');
    expect(parameters['properties']['background']['default'], isFalse);
  });

  test('local tool launches Termux and returns the launch result', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TermuxCommand.channel, (call) async {
          received = call;
          return <String, dynamic>{
            'success': true,
            'launched': true,
            'command': 'git',
            'background': false,
          };
        });

    final encoded = await LocalToolsService.tryHandleToolCall(
      LocalToolNames.termuxRunCommand,
      const {
        'command': 'git',
        'arguments': ['status', '--short'],
      },
      assistant,
    );

    expect(received?.method, 'runCommand');
    expect(
      jsonDecode(encoded!) as Map<String, dynamic>,
      containsPair('launched', true),
    );
  });

  test('local tool rejects a non-array arguments value', () {
    expect(
      () => LocalToolsService.tryHandleToolCall(
        LocalToolNames.termuxRunCommand,
        const {'command': 'echo', 'arguments': 'hello'},
        assistant,
      ),
      throwsArgumentError,
    );
  });

  test('disabled assistant cannot invoke Termux', () async {
    expect(
      await LocalToolsService.tryHandleToolCall(
        LocalToolNames.termuxRunCommand,
        const {'command': 'pwd'},
        const Assistant(id: 'disabled', name: 'Disabled'),
      ),
      isNull,
    );
  });
}
