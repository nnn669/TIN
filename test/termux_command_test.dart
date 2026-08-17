import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tin/core/services/termux_command.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.termux.test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('sends a command and separate arguments to Android', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return <String, dynamic>{
            'success': true,
            'exitCode': 0,
            'stdout': 'hello\n',
            'stderr': '',
          };
        });

    final result = await TermuxCommand.run(
      command: 'python',
      arguments: const ['-c', 'print("hello")'],
      workingDirectory: '/data/data/com.termux/files/home/project',
      timeoutSeconds: 20,
      methodChannel: channel,
    );

    expect(received?.method, 'runCommand');
    expect(received?.arguments, <String, dynamic>{
      'command': 'python',
      'arguments': const ['-c', 'print("hello")'],
      'workingDirectory': '/data/data/com.termux/files/home/project',
      'background': false,
      'timeoutSeconds': 20,
    });
    expect(result['exitCode'], 0);
    expect(result['stdout'], 'hello\n');
  });

  test('rejects command paths so arguments cannot change the executable', () {
    expect(
      () =>
          TermuxCommand.run(command: '/system/bin/sh', methodChannel: channel),
      throwsArgumentError,
    );
    expect(
      () => TermuxCommand.run(command: 'git;rm', methodChannel: channel),
      throwsArgumentError,
    );
  });

  test('rejects working directories outside Termux storage', () {
    expect(
      () => TermuxCommand.run(
        command: 'pwd',
        workingDirectory: '/sdcard',
        methodChannel: channel,
      ),
      throwsArgumentError,
    );
  });

  test('rejects excessive arguments before invoking Android', () {
    expect(
      () => TermuxCommand.run(
        command: 'echo',
        arguments: List<String>.filled(TermuxCommand.maxArguments + 1, 'x'),
        methodChannel: channel,
      ),
      throwsArgumentError,
    );
  });

  test('rejects timeout outside the bounded result window', () {
    expect(
      () => TermuxCommand.run(
        command: 'pwd',
        timeoutSeconds: TermuxCommand.maxTimeoutSeconds + 1,
        methodChannel: channel,
      ),
      throwsArgumentError,
    );
  });

  test('surfaces a missing Termux plugin as a platform failure', () {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'termux_unavailable',
            message: 'Termux command service is unavailable.',
          );
        });

    expect(
      () => TermuxCommand.run(command: 'pwd', methodChannel: channel),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'termux_unavailable',
        ),
      ),
    );
  });
}
