import 'dart:async';

import 'package:flutter/services.dart';

class TermuxCommand {
  const TermuxCommand._();

  static const MethodChannel channel = MethodChannel('app.termux');
  static const int maxArguments = 64;
  static const int maxArgumentLength = 4096;
  static const int maxTotalLength = 16384;
  static const int minTimeoutSeconds = 1;
  static const int maxTimeoutSeconds = 25;
  static const int defaultTimeoutSeconds = 15;
  static final RegExp _commandPattern = RegExp(
    r'^[a-zA-Z0-9][a-zA-Z0-9._+-]*$',
  );

  static Future<Map<String, dynamic>> run({
    required String command,
    List<String> arguments = const <String>[],
    String? workingDirectory,
    bool background = false,
    int timeoutSeconds = defaultTimeoutSeconds,
    MethodChannel methodChannel = channel,
  }) async {
    final normalizedCommand = command.trim();
    if (!_commandPattern.hasMatch(normalizedCommand)) {
      throw ArgumentError(
        'command must be a Termux executable name without path separators',
      );
    }
    if (arguments.length > maxArguments) {
      throw ArgumentError('arguments must contain at most $maxArguments items');
    }
    if (arguments.any((value) => value.length > maxArgumentLength)) {
      throw ArgumentError(
        'each argument must contain at most $maxArgumentLength characters',
      );
    }
    final totalLength = arguments.fold<int>(
      normalizedCommand.length,
      (total, value) => total + value.length,
    );
    if (totalLength > maxTotalLength) {
      throw ArgumentError(
        'command and arguments must contain at most $maxTotalLength characters',
      );
    }
    if (timeoutSeconds < minTimeoutSeconds ||
        timeoutSeconds > maxTimeoutSeconds) {
      throw ArgumentError(
        'timeout_seconds must be between $minTimeoutSeconds and '
        '$maxTimeoutSeconds',
      );
    }

    final normalizedWorkingDirectory = workingDirectory?.trim();
    if (normalizedWorkingDirectory != null &&
        normalizedWorkingDirectory.isNotEmpty &&
        !normalizedWorkingDirectory.startsWith('/data/data/com.termux/files/')) {
      throw ArgumentError(
        'working_directory must be inside /data/data/com.termux/files/',
      );
    }

    final result = await methodChannel
        .invokeMapMethod<String, dynamic>('runCommand', <String, dynamic>{
          'command': normalizedCommand,
          'arguments': arguments,
          if (normalizedWorkingDirectory?.isNotEmpty == true)
            'workingDirectory': normalizedWorkingDirectory,
          'background': background,
          'timeoutSeconds': timeoutSeconds,
        })
        .timeout(Duration(seconds: timeoutSeconds + 2));
    if (result == null) {
      throw StateError('Termux returned no command result');
    }
    return result;
  }
}
