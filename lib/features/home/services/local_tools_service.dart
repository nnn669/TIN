import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:math_expressions/math_expressions.dart';

import '../../../core/models/assistant.dart';
import '../../../core/services/termux_command.dart';

typedef TextToSpeechStarter = Future<void> Function(String text);

class LocalToolNames {
  const LocalToolNames._();

  static const String timeInfo = 'get_time_info';
  static const String clipboard = 'clipboard_tool';
  static const String textToSpeech = 'text_to_speech';
  static const String askUser = 'ask_user_input_v0';
  static const String calculate = 'calculate';
  static const String termuxRunCommand = 'termux_run_command';
}

class LocalToolsService {
  const LocalToolsService._();

  static List<Map<String, dynamic>> buildToolDefinitions({
    required Assistant? assistant,
    required bool supportsTools,
  }) {
    if (!supportsTools || assistant == null) {
      return const <Map<String, dynamic>>[];
    }

    final tools = <Map<String, dynamic>>[];
    if (assistant.localToolIds.contains(LocalToolNames.timeInfo)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.timeInfo,
          'description': '从当前设备读取本地日期和时间信息。返回年、月、日、星期、ISO 日期时间、时区、UTC 偏移和时间戳。',
          'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.clipboard)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.clipboard,
          'description':
              '读取或写入设备剪贴板中的纯文本。action 可为 read 或 write；写入时必须提供 text。除非用户明确要求，否则不要写入剪贴板。',
          'parameters': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': ['read', 'write'],
                'description': '要执行的操作：read 表示读取，write 表示写入。',
              },
              'text': {
                'type': 'string',
                'description': '要写入剪贴板的文本。action 为 write 时必填。',
              },
            },
            'required': ['action'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.textToSpeech)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.textToSpeech,
          'description':
              '使用已配置的文字转语音功能向用户朗读文本。用户要求朗读或适合音频输出时使用；工具在发起播放后返回，音频可能在后台继续。请提供自然、易读、无 Markdown 格式的文本。',
          'parameters': {
            'type': 'object',
            'properties': {
              'text': {'type': 'string', 'description': '要朗读的文本。'},
            },
            'required': ['text'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.askUser)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.askUser,
          'description':
              '在继续前需要用户澄清、补充信息或做决定时，向用户提出一个或多个简短选择题。支持单选和多选。界面会自动提供“其它”和“跳过”选项，请不要自行加入这些选项。',
          'parameters': {
            'type': 'object',
            'properties': {
              'questions': {
                'type': 'array',
                'description': '要询问用户的 1 到 4 个问题。',
                'items': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'string', 'description': '该问题的唯一且稳定的标识符。'},
                    'question': {
                      'type': 'string',
                      'description': '展示给用户的完整问题文本。',
                    },
                    'type': {
                      'type': 'string',
                      'enum': ['single', 'multi'],
                      'description': '回答类型：single 为单选，multi 为多选。',
                    },
                    'options': {
                      'type': 'array',
                      'description': '提供给用户选择的建议选项。',
                      'items': {'type': 'string'},
                    },
                  },
                  'required': ['id', 'question'],
                },
              },
            },
            'required': ['questions'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.calculate)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.calculate,
          'description':
              '计算数学表达式。支持 + - * / ^ % !，sin() cos() tan() sqrt() ln() abs() floor() ceil() sgn()，log(base, value)，以及常量 pi、e。示例："5!"、"sin(pi/4)"、"log(2, 8)"、"floor(3.7)"。',
          'parameters': {
            'type': 'object',
            'properties': {
              'expression': {
                'type': 'string',
                'description':
                    '标准写法的数学表达式，例如 "(15 + 3) * 2"、"2^10"、"sqrt(144)"。',
              },
            },
            'required': ['expression'],
          },
        },
      });
    }
    if (assistant.localToolIds.contains(LocalToolNames.termuxRunCommand)) {
      tools.add(const {
        'type': 'function',
        'function': {
          'name': LocalToolNames.termuxRunCommand,
          'description':
              '通过本机 Termux 执行一个已安装的命令。仅在用户明确要求调用 Termux 时使用。命令和参数分开传递，不要拼接 shell 命令；调用只表示已交给 Termux，不返回命令输出。需要 Termux 开启 allow-external-apps。',
          'parameters': {
            'type': 'object',
            'properties': {
              'command': {
                'type': 'string',
                'description': 'Termux 可执行文件名，例如 python、git、pkg，不含路径。',
              },
              'arguments': {
                'type': 'array',
                'description': '按顺序传给命令的参数，每一项是一个独立参数。',
                'items': {'type': 'string'},
                'maxItems': 64,
              },
              'working_directory': {
                'type': 'string',
                'description':
                    '可选工作目录，必须位于 /data/data/com.termux/files/ 内。',
              },
              'background': {
                'type': 'boolean',
                'description': '是否在 Termux 后台执行，默认 false。',
                'default': false,
              },
            },
            'required': ['command'],
          },
        },
      });
    }
    return tools;
  }

  static Future<String?> tryHandleToolCall(
    String name,
    Map<String, dynamic> args,
    Assistant? assistant, {
    TextToSpeechStarter? onSpeakText,
  }) async {
    if (assistant == null || !assistant.localToolIds.contains(name)) {
      return null;
    }
    if (name == LocalToolNames.timeInfo) {
      return jsonEncode(_buildTimeInfoPayload(DateTime.now()));
    }
    if (name == LocalToolNames.clipboard) {
      return _handleClipboardTool(args);
    }
    if (name == LocalToolNames.textToSpeech) {
      return _handleTextToSpeechTool(args, onSpeakText);
    }
    if (name == LocalToolNames.calculate) {
      return _handleCalculateTool(args);
    }
    if (name == LocalToolNames.termuxRunCommand) {
      return _handleTermuxRunCommand(args);
    }
    return null;
  }

  static Future<String> _handleClipboardTool(Map<String, dynamic> args) async {
    final action = (args['action'] ?? '').toString();
    switch (action) {
      case 'read':
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        return jsonEncode({'text': data?.text ?? ''});
      case 'write':
        final text = args['text']?.toString();
        if (text == null) {
          throw ArgumentError('text is required for clipboard write');
        }
        await Clipboard.setData(ClipboardData(text: text));
        return jsonEncode({'success': true, 'text': text});
      default:
        throw ArgumentError('unknown clipboard action: $action');
    }
  }

  static Future<String> _handleTextToSpeechTool(
    Map<String, dynamic> args,
    TextToSpeechStarter? onSpeakText,
  ) async {
    final text = args['text']?.toString().trim();
    if (text == null || text.isEmpty) {
      throw ArgumentError('text is required for text_to_speech');
    }
    if (onSpeakText == null) {
      throw StateError('text-to-speech executor is unavailable');
    }
    await onSpeakText(text);
    return jsonEncode({'success': true});
  }

  static Future<String> _handleTermuxRunCommand(
    Map<String, dynamic> args,
  ) async {
    final rawArguments = args['arguments'];
    if (rawArguments != null && rawArguments is! List) {
      throw ArgumentError('arguments must be an array');
    }
    final result = await TermuxCommand.run(
      command: (args['command'] ?? '').toString(),
      arguments: rawArguments is List
          ? rawArguments.map((value) => value.toString()).toList()
          : const <String>[],
      workingDirectory: args['working_directory']?.toString(),
      background: args['background'] == true,
    );
    return jsonEncode(result);
  }

  static Map<String, dynamic> _buildTimeInfoPayload(DateTime now) {
    final offset = now.timeZoneOffset;
    final offsetSign = offset.isNegative ? '-' : '+';
    final offsetAbs = offset.abs();
    final offsetHours = offsetAbs.inHours.toString().padLeft(2, '0');
    final offsetMinutes = (offsetAbs.inMinutes % 60).toString().padLeft(2, '0');

    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    final weekdayEn = _englishWeekdayName(now.weekday);

    return <String, dynamic>{
      'year': now.year,
      'month': now.month,
      'day': now.day,
      'weekday': weekdayEn,
      'weekday_en': weekdayEn,
      'weekday_index': now.weekday,
      'date': '$year-$month-$day',
      'time': '$hour:$minute:$second',
      'datetime': now.toIso8601String(),
      'timezone': now.timeZoneName,
      'utc_offset': '$offsetSign$offsetHours:$offsetMinutes',
      'timestamp_ms': now.millisecondsSinceEpoch,
    };
  }

  static String _englishWeekdayName(int weekday) {
    return switch (weekday) {
      DateTime.monday => 'Monday',
      DateTime.tuesday => 'Tuesday',
      DateTime.wednesday => 'Wednesday',
      DateTime.thursday => 'Thursday',
      DateTime.friday => 'Friday',
      DateTime.saturday => 'Saturday',
      DateTime.sunday => 'Sunday',
      _ => 'Unknown',
    };
  }

  static String _handleCalculateTool(Map<String, dynamic> args) {
    final expression = (args['expression'] ?? '').toString().trim();
    if (expression.isEmpty) {
      return jsonEncode({
        'error': 'empty_expression',
        'message':
            'Expression is empty. Please provide a mathematical expression in standard notation, e.g. "(15 + 3) * 2".',
      });
    }

    try {
      final parsed = GrammarParser().parse(expression);
      final result = parsed.evaluate(EvaluationType.REAL, ContextModel());
      if (!result.isFinite) {
        return jsonEncode({
          'error': 'math_error',
          'message':
              'The result is not a finite number. Please check your expression (e.g. division by zero).',
        });
      }
      return jsonEncode({
        'expression': expression,
        'result': result.toString(),
      });
    } catch (e) {
      return jsonEncode({
        'error': 'parse_error',
        'message':
            'Could not parse the expression. Use standard notation, e.g. "(15 + 3) * 2".',
        'detail': e.toString(),
      });
    }
  }
}
