import 'package:path/path.dart' as path;

import '../../termux_command.dart';

class TermuxToolInvocation {
  const TermuxToolInvocation({required this.command, this.arguments = const <String>[], this.workingDirectory, this.timeoutSeconds = TermuxCommand.defaultTimeoutSeconds});
  final String command;
  final List<String> arguments;
  final String? workingDirectory;
  final int timeoutSeconds;
}

class TermuxBuiltinTools {
  const TermuxBuiltinTools._();
  static const String termuxHome = '/data/data/com.termux/files/home';
  static const String sharedStorage = '/storage/emulated/0';
  static final List<Map<String, dynamic>> definitions = <Map<String, dynamic>>[
    _tool('termux_get_system_info', '通过外部 Termux 应用读取 Android、内核、CPU 和 Termux 环境摘要。'),
    _tool('termux_check_commands', '批量检查命令是否已安装并返回可执行路径。', properties: {'commands': _strings('要检查的命令名。', 50)}, required: const ['commands']),
    _tool('termux_list_installed_packages', '列出 Termux 已安装软件包，可按关键词过滤。', properties: {'filter': _string('可选包名关键词。')}),
    _tool('termux_search_packages', '搜索 Termux 软件源中的软件包。', properties: {'query': _string('软件包搜索关键词。')}, required: const ['query']),
    _tool('termux_install_packages', '使用 pkg 安装一个或多个 Termux 软件包。', properties: {'packages': _strings('要安装的软件包名。', 20), 'timeout_seconds': _timeout(defaultValue: 25)}, required: const ['packages']),
    _tool('termux_list_processes', '列出当前 Termux 可见进程，可按关键词过滤。', properties: {'filter': _string('可选进程关键词。')}),
    _tool('termux_get_storage_usage', '查看指定路径或默认存储位置的目录占用。', properties: {'path': _path('目录路径。'), 'depth': _integer('目录统计深度。', minimum: 0, maximum: 4, defaultValue: 1)}),
    _tool('termux_get_network_info', '读取网络接口和路由配置。'),
    _tool('termux_download_file', '通过 curl 下载文件到 Termux Home 或手机共享存储。', properties: {'url': _string('HTTP 或 HTTPS 下载地址。'), 'destination': _path('目标文件绝对路径。'), 'overwrite': _boolean('是否覆盖已存在文件。'), 'timeout_seconds': _timeout(defaultValue: 25)}, required: const ['url', 'destination']),
    _gitTool('termux_git_status', '读取本地 Git 仓库分支、跟踪关系和工作区状态。'),
    _gitTool('termux_git_log', '读取本地 Git 提交历史。', extra: {'limit': _integer('提交数量。', minimum: 1, maximum: 100, defaultValue: 20), 'ref': _string('可选分支、标签或提交引用。')}),
    _gitTool('termux_git_diff', '读取本地 Git 工作区、暂存区或两个引用之间的差异。', extra: {'mode': _string('差异模式。', values: const ['working', 'staged', 'refs']), 'base': _string('refs 模式的基准引用。'), 'head': _string('refs 模式的目标引用。'), 'stat_only': _boolean('是否只返回统计。')}),
    _gitTool('termux_git_fetch', '从远端获取 Git 引用和对象。', extra: {'remote': _string('远端名称。'), 'prune': _boolean('是否清理失效远端引用。', defaultValue: true), 'timeout_seconds': _timeout()}),
    _gitTool('termux_git_pull', '以 fast-forward only 或 rebase 模式拉取 Git 分支。', extra: {'remote': _string('远端名称。'), 'branch': _string('可选远端分支。'), 'mode': _string('拉取模式。', values: const ['ff-only', 'rebase']), 'timeout_seconds': _timeout()}),
    _gitTool('termux_git_commit', '暂存指定文件并创建 Git 提交，不接受空提交。', extra: {'paths': _strings('仓库内要暂存的相对路径。', 62), 'message': _string('提交信息。')}, extraRequired: const ['paths', 'message']),
    _gitTool('termux_git_push', '推送当前或指定 Git 分支，可设置上游。', extra: {'remote': _string('远端名称。'), 'branch': _string('可选本地分支。'), 'set_upstream': _boolean('是否设置上游。'), 'timeout_seconds': _timeout()}),
    _tool('termux_adb_devices', '列出 ADB 设备及详细状态。'),
    _tool('termux_adb_shell', '在指定 ADB 设备执行单个 Android shell 命令。', properties: {'command': _string('Android shell 命令名。'), 'arguments': _strings('命令参数。', 60), 'serial': _string('可选设备序列号。'), 'timeout_seconds': _timeout()}, required: const ['command']),
    _tool('termux_run_python', '在受限目录中运行 Python 脚本文件及参数。', properties: {'script': _path('Python 脚本绝对路径。'), 'arguments': _strings('脚本参数。', 63), 'working_directory': _path('可选工作目录。'), 'timeout_seconds': _timeout()}, required: const ['script']),
  ];

  static bool contains(String name) => definitions.any((definition) => definition['name'] == name);
  static TermuxToolInvocation invocationFor(String name, Map<String, dynamic> arguments) {
    switch (name) {
      case 'termux_get_system_info': return const TermuxToolInvocation(command: 'termux-info');
      case 'termux_check_commands': return TermuxToolInvocation(command: 'which', arguments: _stringList(arguments, 'commands', required: true, maximum: 50));
      case 'termux_list_installed_packages': return const TermuxToolInvocation(command: 'pkg', arguments: ['list-installed'], timeoutSeconds: 25);
      case 'termux_search_packages': return TermuxToolInvocation(command: 'pkg', arguments: ['search', _requiredString(arguments, 'query')], timeoutSeconds: 25);
      case 'termux_install_packages':
        final packages = _stringList(arguments, 'packages', required: true, maximum: 20);
        if (packages.any((item) => item.startsWith('-') || item.contains('/'))) throw const FormatException('packages contains an invalid package name');
        return TermuxToolInvocation(command: 'pkg', arguments: ['install', '-y', ...packages], timeoutSeconds: _timeoutValue(arguments, defaultValue: 25));
      case 'termux_list_processes': return const TermuxToolInvocation(command: 'ps', arguments: ['-A']);
      case 'termux_get_storage_usage':
        final target = _safePath(arguments['path'] ?? sharedStorage);
        final depth = _integerValue(arguments, 'depth', defaultValue: 1, minimum: 0, maximum: 4);
        return TermuxToolInvocation(command: 'du', arguments: ['-h', '--max-depth=$depth', target]);
      case 'termux_get_network_info': return const TermuxToolInvocation(command: 'ip', arguments: ['address']);
      case 'termux_download_file':
        final url = _requiredString(arguments, 'url');
        if (!url.startsWith('https://') && !url.startsWith('http://')) throw const FormatException('url must use http or https');
        final destination = _safePath(_requiredString(arguments, 'destination'));
        return TermuxToolInvocation(command: 'curl', arguments: ['--fail', '--location', '--show-error', if (!_boolValue(arguments, 'overwrite')) '--no-clobber', '--output', destination, url], timeoutSeconds: _timeoutValue(arguments, defaultValue: 25));
      case 'termux_git_status': return _git(arguments, const ['status', '--short', '--branch']);
      case 'termux_git_log':
        final limit = _integerValue(arguments, 'limit', defaultValue: 20, minimum: 1, maximum: 100);
        return _git(arguments, ['log', '-$limit', '--date=iso-strict', '--pretty=format:%H%x09%ad%x09%an%x09%s', if (_optionalGitValue(arguments, 'ref') case final ref?) ref]);
      case 'termux_git_diff':
        final mode = _enumValue(arguments, 'mode', const {'working', 'staged', 'refs'}, 'working');
        final args = <String>['diff'];
        if (mode == 'staged') args.add('--cached');
        if (mode == 'refs') args.add('${_requiredString(arguments, 'base')}..${_requiredString(arguments, 'head')}');
        if (_boolValue(arguments, 'stat_only')) args.add('--stat');
        return _git(arguments, args);
      case 'termux_git_fetch': return _git(arguments, ['fetch', _optionalGitValue(arguments, 'remote') ?? 'origin', if (_boolValue(arguments, 'prune', defaultValue: true)) '--prune'], timeoutSeconds: _timeoutValue(arguments));
      case 'termux_git_pull':
        final mode = _enumValue(arguments, 'mode', const {'ff-only', 'rebase'}, 'ff-only');
        return _git(arguments, ['pull', mode == 'ff-only' ? '--ff-only' : '--rebase', _optionalGitValue(arguments, 'remote') ?? 'origin', if (_optionalGitValue(arguments, 'branch') case final branch?) branch], timeoutSeconds: _timeoutValue(arguments));
      case 'termux_git_commit':
        final paths = _stringList(arguments, 'paths', required: true, maximum: 62);
        _validateGitPaths(paths);
        return _git(arguments, ['commit', '-m', _requiredString(arguments, 'message')], timeoutSeconds: 25);
      case 'termux_git_push': return _git(arguments, ['push', if (_boolValue(arguments, 'set_upstream')) '--set-upstream', _optionalGitValue(arguments, 'remote') ?? 'origin', if (_optionalGitValue(arguments, 'branch') case final branch?) branch], timeoutSeconds: _timeoutValue(arguments));
      case 'termux_adb_devices': return const TermuxToolInvocation(command: 'adb', arguments: ['devices', '-l']);
      case 'termux_adb_shell': return TermuxToolInvocation(command: 'adb', arguments: [if (_optionalString(arguments, 'serial') case final serial?) ...['-s', serial], 'shell', _requiredString(arguments, 'command'), ..._stringList(arguments, 'arguments', maximum: 60)], timeoutSeconds: _timeoutValue(arguments));
      case 'termux_run_python':
        final script = _safePath(_requiredString(arguments, 'script'));
        if (!script.endsWith('.py')) throw const FormatException('script must end with .py');
        return TermuxToolInvocation(command: 'python', arguments: [script, ..._stringList(arguments, 'arguments', maximum: 63)], workingDirectory: _safePath(arguments['working_directory'] ?? path.dirname(script)), timeoutSeconds: _timeoutValue(arguments));
      default: throw FormatException('unknown Termux tool: $name');
    }
  }

  static TermuxToolInvocation? preparationFor(String name, Map<String, dynamic> arguments) {
    if (name != 'termux_git_commit') return null;
    final paths = _stringList(arguments, 'paths', required: true, maximum: 62);
    _validateGitPaths(paths);
    return _git(arguments, ['add', '--', ...paths], timeoutSeconds: 25);
  }
  static void _validateGitPaths(List<String> paths) {
    if (paths.any((item) => path.isAbsolute(item) || path.split(item).contains('..'))) throw const FormatException('paths must be repository-relative and cannot traverse parents');
  }
  static TermuxToolInvocation _git(Map<String, dynamic> arguments, List<String> commandArguments, {int timeoutSeconds = TermuxCommand.defaultTimeoutSeconds}) => TermuxToolInvocation(command: 'git', arguments: commandArguments, workingDirectory: _safePath(_requiredString(arguments, 'repository')), timeoutSeconds: timeoutSeconds);
  static String _safePath(dynamic value) {
    if (value is! String || value.trim().isEmpty || !path.isAbsolute(value)) throw const FormatException('path must be an absolute path');
    final normalized = path.normalize(value.trim());
    final allowed = normalized == termuxHome || path.isWithin(termuxHome, normalized) || normalized == sharedStorage || path.isWithin(sharedStorage, normalized) || normalized == '/sdcard' || path.isWithin('/sdcard', normalized);
    if (!allowed) throw const FormatException('path must be inside Termux Home or shared storage');
    return normalized;
  }
  static String _requiredString(Map<String, dynamic> values, String key) { final value = _optionalString(values, key); if (value == null) throw FormatException('$key is required'); return value; }
  static String? _optionalString(Map<String, dynamic> values, String key) { final value = values[key]; if (value == null) return null; if (value is! String || value.trim().isEmpty) throw FormatException('$key must be a non-empty string'); return value.trim(); }
  static String? _optionalGitValue(Map<String, dynamic> values, String key) { final value = _optionalString(values, key); if (value?.startsWith('-') == true) throw FormatException('$key cannot start with a hyphen'); return value; }
  static List<String> _stringList(Map<String, dynamic> values, String key, {bool required = false, int maximum = TermuxCommand.maxArguments}) { final value = values[key]; if (value == null && !required) return const []; if (value is! List || value.isEmpty || value.any((item) => item is! String || item.trim().isEmpty)) throw FormatException('$key must be a non-empty array of strings'); if (value.length > maximum) throw FormatException('$key must contain at most $maximum items'); return value.cast<String>(); }
  static int _timeoutValue(Map<String, dynamic> values, {int defaultValue = TermuxCommand.defaultTimeoutSeconds, int maximum = TermuxCommand.maxTimeoutSeconds}) => _integerValue(values, 'timeout_seconds', defaultValue: defaultValue, minimum: TermuxCommand.minTimeoutSeconds, maximum: maximum);
  static int _integerValue(Map<String, dynamic> values, String key, {required int defaultValue, required int minimum, required int maximum}) { final value = values[key] ?? defaultValue; if (value is! int || value < minimum || value > maximum) throw FormatException('$key must be between $minimum and $maximum'); return value; }
  static bool _boolValue(Map<String, dynamic> values, String key, {bool defaultValue = false}) { final value = values[key] ?? defaultValue; if (value is! bool) throw FormatException('$key must be a boolean'); return value; }
  static String _enumValue(Map<String, dynamic> values, String key, Set<String> allowed, String defaultValue) { final value = values[key] ?? defaultValue; if (value is! String || !allowed.contains(value)) throw FormatException('$key must be one of ${allowed.join(', ')}'); return value; }
  static Map<String, dynamic> _gitTool(String name, String description, {Map<String, dynamic> extra = const {}, List<String> extraRequired = const []}) => _tool(name, description, properties: {'repository': _path('Git 仓库绝对路径。'), ...extra}, required: ['repository', ...extraRequired]);
  static Map<String, dynamic> _tool(String name, String description, {Map<String, dynamic> properties = const {}, List<String> required = const []}) => {'name': name, 'description': description, 'inputSchema': {'type': 'object', 'properties': properties, if (required.isNotEmpty) 'required': required}};
  static Map<String, dynamic> _string(String description, {List<String>? values}) => {'type': 'string', 'description': description, if (values != null) 'enum': values};
  static Map<String, dynamic> _path(String description) => _string(description);
  static Map<String, dynamic> _strings(String description, int maximum) => {'type': 'array', 'description': description, 'items': const {'type': 'string'}, 'maxItems': maximum};
  static Map<String, dynamic> _boolean(String description, {bool defaultValue = false}) => {'type': 'boolean', 'description': description, 'default': defaultValue};
  static Map<String, dynamic> _integer(String description, {required int minimum, required int maximum, required int defaultValue}) => {'type': 'integer', 'description': description, 'minimum': minimum, 'maximum': maximum, 'default': defaultValue};
  static Map<String, dynamic> _timeout({int maximum = TermuxCommand.maxTimeoutSeconds, int defaultValue = TermuxCommand.defaultTimeoutSeconds}) => _integer('超时秒数。', minimum: TermuxCommand.minTimeoutSeconds, maximum: maximum, defaultValue: defaultValue);
}
