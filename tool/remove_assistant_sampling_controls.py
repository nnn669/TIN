from pathlib import Path


def read(path):
    return Path(path).read_text(encoding='utf-8')


def write(path, text):
    Path(path).write_text(text, encoding='utf-8')


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one match, found {count}')
    return text.replace(old, new, 1)


def remove_braced(text, signature, label):
    start = text.find(signature)
    if start < 0:
        raise SystemExit(f'{label}: signature not found')
    brace = text.find('{', start)
    depth = 0
    quote = None
    escape = False
    for i in range(brace, len(text)):
        c = text[i]
        if quote:
            if escape:
                escape = False
            elif c == '\\':
                escape = True
            elif c == quote:
                quote = None
        elif c in ("'", '"'):
            quote = c
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                end = i + 1
                while end < len(text) and text[end] in ' \t\r\n':
                    end += 1
                return text[:start] + text[end:]
    raise SystemExit(f'{label}: closing brace not found')


path = 'lib/core/models/assistant.dart'
s = read(path)
for old in [
    '  final double? temperature; // null to disable; else 0.0 - 2.0\n',
    '  final double? topP; // null to disable; else 0.0 - 1.0\n',
    '    this.temperature,\n', '    this.topP,\n',
    '    double? temperature,\n', '    double? topP,\n',
    '    bool clearTemperature = false,\n', '    bool clearTopP = false,\n',
    '      temperature: clearTemperature ? null : (temperature ?? this.temperature),\n',
    '      topP: clearTopP ? null : (topP ?? this.topP),\n',
    "    'temperature': temperature,\n", "    'topP': topP,\n",
    "      temperature: (json['temperature'] as num?)?.toDouble(),\n",
    "      topP: (json['topP'] as num?)?.toDouble(),\n",
]:
    s = replace_once(s, old, '', f'assistant model {old.strip()}')
write(path, s)

path = 'lib/core/providers/assistant_provider.dart'
s = read(path)
for old in ['    temperature: 0.6,\n', '    topP: null,\n']:
    if s.count(old) != 3:
        raise SystemExit(f'assistant defaults: expected 3 {old.strip()}')
    s = s.replace(old, '')
write(path, s)

path = 'lib/features/assistant/pages/assistant_settings_edit_basic_tab.dart'
s = read(path)
start = s.find('              // Temperature\n')
end = s.find('              // Context messages\n', start)
if start < 0 or end < 0:
    raise SystemExit('sampling settings rows not found')
s = s[:start] + s[end:]
s = remove_braced(s, '  Future<void> _showTemperatureSheet(', 'temperature sheet')
s = remove_braced(s, '  Future<void> _showTopPSheet(', 'top p sheet')
s = replace_once(s, "    subtitle: '名称、模型、温度、上下文和搜索记忆开关',", "    subtitle: '名称、模型、上下文和搜索记忆开关',", 'gateway subtitle')
write(path, s)

path = 'lib/features/home/controllers/chat_actions.dart'
s = read(path)
for old in ['        temperature: assistant?.temperature,\n', '        topP: assistant?.topP,\n']:
    s = replace_once(s, old, '', f'chat request {old.strip()}')
write(path, s)

path = 'lib/core/services/backup/chatbox_importer.dart'
s = read(path)
for old in [
    "      final temperature = (sessionSettings['temperature'] as num?)?.toDouble();\n",
    "      final topP = (sessionSettings['topP'] as num?)?.toDouble();\n",
    "        'temperature': temperature,\n", "        'topP': topP,\n",
]:
    s = replace_once(s, old, '', f'chatbox {old.strip()}')
for field in ('temperature', 'topP'):
    block = f"        if (assistantJson['{field}'] != null) {{\n          local['{field}'] = assistantJson['{field}'];\n        }}\n"
    s = replace_once(s, block, '', f'chatbox merge {field}')
write(path, s)

path = 'lib/core/services/backup/cherry_importer.dart'
s = read(path)
for old in [
    "      final temperature = (settings?['temperature'] as num?)?.toDouble();\n",
    "      final topP = (settings?['topP'] as num?)?.toDouble();\n",
    "        'temperature': temperature,\n", "        'topP': topP,\n",
]:
    s = replace_once(s, old, '', f'cherry {old.strip()}')
write(path, s)

path = 'lib/core/services/app_control/app_control_service.dart'
s = read(path)
s = replace_once(s, 'context size, temperature, max tokens', 'context size, max tokens', 'gateway description')
for key, clear, setter, maximum in [('temperature', 'clearTemperature', 'temperature', '2.0'), ('top_p', 'clearTopP', 'topP', '1.0')]:
    block = f"    if (patch.containsKey('{key}')) {{\n      final value = patch['{key}'];\n      next = value == null || value.toString().trim().isEmpty\n          ? next.copyWith({clear}: true)\n          : next.copyWith({setter}: _doubleFrom(value).clamp(0.0, {maximum}));\n    }}\n"
    s = replace_once(s, block, '', f'gateway {key}')
write(path, s)

path = 'test/core/services/app_control_service_test.dart'
s = read(path)
s = replace_once(s, "                  'temperature': 0.7,\n", '', 'gateway test input')
s = replace_once(s, "    expect(updated.temperature, 0.7);\n", '', 'gateway test assertion')
write(path, s)

path = 'test/features/assistant/pages/assistant_settings_edit_page_mcp_test.dart'
s = read(path)
s = replace_once(s, "      Assistant(id: _assistantId, name: 'Test Assistant', temperature: 0.6),\n", "      Assistant(id: _assistantId, name: 'Test Assistant'),\n", 'assistant test seed')
write(path, s)

write('test/core/models/assistant_sampling_controls_removed_test.dart', """import 'package:flutter_test/flutter_test.dart';
import 'package:tin/core/models/assistant.dart';

void main() {
  test('legacy assistant sampling controls are discarded', () {
    final assistant = Assistant.fromJson({
      'id': 'legacy',
      'name': 'Legacy',
      'temperature': 0.7,
      'topP': 0.9,
    });
    final json = assistant.toJson();
    expect(json.containsKey('temperature'), isFalse);
    expect(json.containsKey('topP'), isFalse);
    expect(Assistant.fromJson(json).name, 'Legacy');
  });
}
""")

for file, needles in {
    'lib/core/models/assistant.dart': ['temperature', 'topP', 'clearTemperature', 'clearTopP'],
    'lib/core/providers/assistant_provider.dart': ['temperature:', 'topP:'],
    'lib/features/assistant/pages/assistant_settings_edit_basic_tab.dart': ['Temperature', 'Top P', '_showTemperatureSheet', '_showTopPSheet', 'a.temperature', 'a.topP'],
    'lib/features/home/controllers/chat_actions.dart': ['assistant?.temperature', 'assistant?.topP'],
    'lib/core/services/app_control/app_control_service.dart': ["patch.containsKey('temperature')", "patch.containsKey('top_p')", 'clearTemperature', 'clearTopP'],
}.items():
    found = [needle for needle in needles if needle in read(file)]
    if found:
        raise SystemExit(f'{file} still contains {found}')