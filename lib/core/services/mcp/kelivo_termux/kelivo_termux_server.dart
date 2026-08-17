import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;

import '../../termux_command.dart';
import '../in_memory_mcp_server.dart';
import 'termux_builtin_tools.dart';

typedef TermuxCommandExecutor = Future<Map<String, dynamic>> Function({required String command, required List<String> arguments, required String? workingDirectory, required bool background, required int timeoutSeconds});

class KelivoTermuxMcpServerEngine implements KelivoInMemoryMcpServerEngine {
  KelivoTermuxMcpServerEngine({TermuxCommandExecutor? executor, bool Function()? isSupported}) : _executor = executor ?? _runCommand, _isSupported = isSupported ?? _isAndroid;
  final TermuxCommandExecutor _executor;
  final bool Function() _isSupported;
  bool _closed = false;

  static Future<Map<String, dynamic>> _runCommand({required String command, required List<String> arguments, required String? workingDirectory, required bool background, required int timeoutSeconds}) => TermuxCommand.run(command: command, arguments: arguments, workingDirectory: workingDirectory, background: background, timeoutSeconds: timeoutSeconds);
  static bool _isAndroid() => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<dynamic> handleMessage(dynamic message) async {
    if (_closed) return null;
    if (message is List) {
      final responses = <dynamic>[];
      for (final item in message) { responses.add(await _handleSingle(item)); }
      return responses;
    }
    return _handleSingle(message);
  }

  Future<Map<String, dynamic>> _handleSingle(dynamic raw) async {
    if (raw is! Map) return _error(null, code: -32600, message: 'Invalid Request');
    final request = raw.cast<String, dynamic>();
    final id = request['id'];
    final method = (request['method'] ?? '').toString();
    final params = request['params'] is Map ? (request['params'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    switch (method) {
      case mcp.McpProtocol.methodInitialize:
        return _ok(id, {'serverInfo': {'name': '@kelivo/termux', 'version': '1.0.0'}, 'protocolVersion': mcp.McpProtocol.defaultVersion, 'capabilities': {'tools': {'listChanged': false}}});
      case mcp.McpProtocol.methodListTools:
        return _ok(id, {'tools': <Map<String, dynamic>>[_toolDefinition, ...TermuxBuiltinTools.definitions]});
      case mcp.McpProtocol.methodCallTool:
        final name = (params['name'] ?? '').toString();
        if (name != 'termux_run_command' && !TermuxBuiltinTools.contains(name)) return _error(id, code: -32101, message: 'Tool not found: $name');
        return _ok(id, await _call(name, params['arguments']));
      default:
        if (id == null) return {'jsonrpc': '2.0'};
        return _error(id, code: -32601, message: 'Method not found: $method');
    }
  }

  Future<Map<String, dynamic>> _call(String toolName, dynamic rawArguments) async {
    if (!_isSupported()) return _toolResult(const {'success': false, 'error': 'unsupported_platform', 'message': 'Termux commands are only available on Android.'}, isError: true);
    if (rawArguments is! Map) return _invalidArguments('arguments must be an object');
    final args = rawArguments.cast<String, dynamic>();
    if (toolName != 'termux_run_command') return _callBuiltin(toolName, args);
    final command = args['command'];
    if (command is! String || command.trim().isEmpty) return _invalidArguments('command is required');
    final rawCommandArguments = args['arguments'];
    if (rawCommandArguments != null && (rawCommandArguments is! List || rawCommandArguments.any((value) => value is! String))) return _invalidArguments('arguments must be an array of strings');
    final workingDirectory = args['working_directory'];
    if (workingDirectory != null && workingDirectory is! String) return _invalidArguments('working_directory must be a string');
    final rawTimeout = args['timeout_seconds'];
    if (rawTimeout != null && rawTimeout is! int) return _invalidArguments('timeout_seconds must be an integer');
    final timeoutSeconds = rawTimeout as int? ?? TermuxCommand.defaultTimeoutSeconds;
    if (timeoutSeconds < TermuxCommand.minTimeoutSeconds || timeoutSeconds > TermuxCommand.maxTimeoutSeconds) return _invalidArguments('timeout_seconds must be between ${TermuxCommand.minTimeoutSeconds} and ${TermuxCommand.maxTimeoutSeconds}');
    try {
      final result = await _executor(command: command, arguments: rawCommandArguments is List ? rawCommandArguments.cast<String>() : const <String>[], workingDirectory: workingDirectory as String?, background: true, timeoutSeconds: timeoutSeconds);
      return _toolResult(result, isError: result['success'] != true);
    } on PlatformException catch (error) {
      return _toolResult({'success': false, 'error': error.code, 'message': error.message ?? 'Termux command failed.'}, isError: true);
    } on TimeoutException {
      return _toolResult(const {'success': false, 'error': 'termux_timeout', 'message': 'Termux command did not finish before the timeout.'}, isError: true);
    } on ArgumentError catch (error) {
      return _invalidArguments(error.message?.toString() ?? error.toString());
    } catch (error) {
      return _toolResult({'success': false, 'error': 'termux_command_failed', 'message': error.toString()}, isError: true);
    }
  }

  Future<Map<String, dynamic>> _callBuiltin(String toolName, Map<String, dynamic> arguments) async {
    try {
      final preparation = TermuxBuiltinTools.preparationFor(toolName, arguments);
      if (preparation != null) {
        final preparationResult = await _execute(preparation);
        if (preparationResult['success'] != true) return _toolResult(preparationResult, isError: true);
      }
      final invocation = TermuxBuiltinTools.invocationFor(toolName, arguments);
      final result = await _execute(invocation);
      _filterOutput(toolName, arguments, result);
      return _toolResult(result, isError: result['success'] != true);
    } on FormatException catch (error) {
      return _invalidArguments(error.message);
    } on PlatformException catch (error) {
      return _toolResult({'success': false, 'error': error.code, 'message': error.message ?? 'Termux command failed.'}, isError: true);
    } on TimeoutException {
      return _toolResult(const {'success': false, 'error': 'termux_timeout', 'message': 'Termux command did not finish before the timeout.'}, isError: true);
    } on ArgumentError catch (error) {
      return _invalidArguments(error.message?.toString() ?? error.toString());
    } catch (error) {
      return _toolResult({'success': false, 'error': 'termux_command_failed', 'message': error.toString()}, isError: true);
    }
  }

  Future<Map<String, dynamic>> _execute(TermuxToolInvocation invocation) => _executor(command: invocation.command, arguments: invocation.arguments, workingDirectory: invocation.workingDirectory, background: true, timeoutSeconds: invocation.timeoutSeconds);

  void _filterOutput(String toolName, Map<String, dynamic> arguments, Map<String, dynamic> result) {
    if (toolName != 'termux_list_installed_packages' && toolName != 'termux_list_processes') return;
    final filter = arguments['filter'];
    final stdout = result['stdout'];
    if (filter is! String || filter.trim().isEmpty || stdout is! String) return;
    final query = filter.toLowerCase();
    result['stdout'] = stdout.split('\n').where((line) => line.toLowerCase().contains(query)).join('\n');
  }

  Map<String, dynamic> _invalidArguments(String message) => _toolResult({'success': false, 'error': 'invalid_arguments', 'message': message}, isError: true);
  Map<String, dynamic> _toolResult(Map<String, dynamic> payload, {required bool isError}) => {'content': [{'type': 'text', 'text': jsonEncode(payload)}], 'isStreaming': false, 'isError': isError};
  Map<String, dynamic> _ok(dynamic id, Map<String, dynamic> result) => {'jsonrpc': '2.0', if (id != null) 'id': id, 'result': result};
  Map<String, dynamic> _error(dynamic id, {required int code, required String message}) => {'jsonrpc': '2.0', if (id != null) 'id': id, 'error': {'code': code, 'message': message}};

  static const Map<String, dynamic> _toolDefinition = {'name': 'termux_run_command', 'description': '通过外部 Termux 应用执行单个已安装命令并返回退出码、标准输出和标准错误。仅在用户明确要求调用 Termux 时使用；命令与参数必须分开传递，不支持 shell 拼接。', 'inputSchema': {'type': 'object', 'properties': {'command': {'type': 'string', 'description': 'Termux 可执行文件名，例如 python、git、pkg，不含路径。'}, 'arguments': {'type': 'array', 'description': '按顺序传给命令的独立参数。', 'items': {'type': 'string'}, 'maxItems': TermuxCommand.maxArguments}, 'working_directory': {'type': 'string', 'description': '可选工作目录，必须位于 Termux Home 或手机共享存储。'}, 'timeout_seconds': {'type': 'integer', 'description': '等待命令结果的秒数。', 'minimum': TermuxCommand.minTimeoutSeconds, 'maximum': TermuxCommand.maxTimeoutSeconds, 'default': TermuxCommand.defaultTimeoutSeconds}}, 'required': ['command']}};

  @override
  void close() { _closed = true; }
}
