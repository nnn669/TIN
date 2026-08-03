from pathlib import Path
import json
import re
import shutil


def read(path):
    return Path(path).read_text(encoding="utf-8")


def write(path, text):
    Path(path).write_text(text, encoding="utf-8")


def drop_imports(text):
    return "".join(line for line in text.splitlines(True) if "world_book" not in line.lower())


def block_end(text, brace):
    depth = 0
    quote = None
    triple = False
    escape = False
    i = brace
    while i < len(text):
        if quote:
            if triple:
                marker = quote * 3
                if text.startswith(marker, i):
                    quote = None
                    triple = False
                    i += 3
                    continue
                i += 1
                continue
            c = text[i]
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == quote:
                quote = None
            i += 1
            continue
        if text.startswith("'''", i) or text.startswith('\"\"\"', i):
            quote = text[i]
            triple = True
            i += 3
            continue
        c = text[i]
        if c in "'\"":
            quote = c
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise RuntimeError("Unbalanced Dart block")


def remove_braced(text, start, include_comma=False):
    line_start = text.rfind("\n", 0, start) + 1
    brace = text.find("{", start)
    if brace < 0:
        return text
    end = block_end(text, brace)
    if include_comma:
        while end < len(text) and text[end] in " \t":
            end += 1
        if end < len(text) and text[end] == ",":
            end += 1
    if end < len(text) and text[end] == "\r":
        end += 1
    if end < len(text) and text[end] == "\n":
        end += 1
    return text[:line_start] + text[end:]


def remove_function(text, name):
    pattern = re.compile(
        r"(?m)^\s*(?:Future(?:<[^\n]+>)?|void|Widget|String|bool|List<[^\n]+>|Map<[^\n]+>|WorldBook(?:Entry)?)\s+"
        + re.escape(name)
        + r"\s*\("
    )
    while True:
        match = pattern.search(text)
        if not match:
            return text
        text = remove_braced(text, match.start())


for item in [
    "lib/core/models/world_book.dart",
    "lib/core/providers/world_book_provider.dart",
    "lib/core/services/world_book_store.dart",
    "lib/desktop/world_book_popover.dart",
    "lib/desktop/setting/world_book_pane.dart",
    "lib/features/home/widgets/world_book_sheet.dart",
    "lib/features/world_book",
]:
    path = Path(item)
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()

p = "lib/main.dart"
s = drop_imports(read(p))
s = re.sub(r"(?m)^\s*ChangeNotifierProvider\(create: \(_\) => WorldBookProvider\(\)\),\s*\n", "", s)
write(p, s)

p = "lib/features/settings/pages/settings_page.dart"
s = drop_imports(read(p))
s = re.sub(r"(?ms)\s*_iosNavRow\(\s*context,\s*icon: Lucide\.BookOpen,\s*label: l10n\.settingsPageWorldBook,\s*onTap: \(\) \{.*?\s*\},\s*\),\s*_iosDivider\(context\),", "", s)
write(p, s)

p = "lib/desktop/desktop_settings_page.dart"
s = drop_imports(read(p))
s = re.sub(r"(?m)^\s*worldBook,\s*\n", "", s)
s = re.sub(r"(?ms)\s*case _SettingsMenuItem\.worldBook:\s*return const DesktopWorldBookPane\(.*?\);", "", s)
s = re.sub(r"(?ms)\s*\(\s*_SettingsMenuItem\.worldBook,\s*lucide\.Lucide\.BookOpen,\s*l10n\.settingsPageWorldBook,\s*\),", "", s)
write(p, s)

p = "lib/features/home/services/message_generation_service.dart"
s = read(p)
s = re.sub(r"(?ms)\n\s*await messageBuilderService\.injectWorldBookPrompts\(\s*apiMessages,\s*assistantId,\s*\);", "", s)
write(p, s)

p = "lib/features/home/services/message_builder_service.dart"
s = remove_function(drop_imports(read(p)), "injectWorldBookPrompts")
write(p, s)

p = "lib/features/home/pages/home_page.dart"
s = drop_imports(read(p))
s = re.sub(r"(?m)^\s*context\.read<WorldBookProvider>\(\)\.initialize\(\);\s*\n", "", s)
for name in ["_openWorldBook", "_openWorldBookPopover"]:
    s = remove_function(s, name)
s = re.sub(r"(?m)^\s*onOpenWorldBook:.*\n", "", s)
write(p, s)

p = "lib/features/chat/widgets/bottom_tools_sheet.dart"
s = drop_imports(read(p))
s = re.sub(r"(?ms)\n\s*@override\s*void initState\(\) \{\s*super\.initState\(\);\s*WidgetsBinding\.instance\.addPostFrameCallback\(\(_\) async \{\s*if \(!mounted\) return;\s*await context\.read<WorldBookProvider>\(\)\.initialize\(\);\s*\}\);\s*\}", "", s)
s = re.sub(r"(?m)^\s*final worldBookProvider =.*\n", "", s)
s = re.sub(r"(?m)^\s*final hasWorldBooks =.*\n", "", s)
s = re.sub(r"(?ms)\n\s*if \(hasWorldBooks\) \.\.\.\[.*?\n\s*\],", "", s)
write(p, s)

p = "lib/features/home/widgets/chat_input_section.dart"
s = drop_imports(read(p))
for pattern in [r"(?m)^\s*this\.onOpenWorldBook,\n", r"(?m)^\s*final VoidCallback\? onOpenWorldBook;\n", r"(?m)^\s*onOpenWorldBook:.*\n"]:
    s = re.sub(pattern, "", s)
s = re.sub(r"(?ms)\n\s*final hasWorldBooks =\s*isTablet && context\.watch<WorldBookProvider>\(\)\.books\.isNotEmpty;", "", s)
s = re.sub(r"(?ms)\n\s*worldBookActive: isTablet\s*\? context\s*\.watch<WorldBookProvider>\(\)\s*\.activeBookIdsFor\(assistantId\)\s*\.isNotEmpty\s*: false,", "", s)
write(p, s)

p = "lib/features/home/widgets/chat_input_bar.dart"
s = read(p)
for pattern in [r"(?m)^\s*this\.onOpenWorldBook,\n", r"(?m)^\s*this\.worldBookActive = false,\n", r"(?m)^\s*final VoidCallback\? onOpenWorldBook;\n", r"(?m)^\s*final bool worldBookActive;\n"]:
    s = re.sub(pattern, "", s)
s = re.sub(r"(?ms)\n\s*if \(widget\.onOpenWorldBook != null\) \{.*?\n\s*\}", "", s)
write(p, s)

p = "lib/core/models/app_control_policy.dart"
s = read(p)
s = re.sub(r"(?m)^\s*static const String worldBook =.*\n", "", s)
s = re.sub(r"(?m)^\s*worldBook,\s*\n", "", s)
write(p, s)

p = "lib/features/assistant/pages/assistant_settings_edit_basic_tab.dart"
s = read(p)
s = re.sub(r"(?ms)\n\s*_AppControlCapabilityMeta\(\s*target: AppControlPolicy\.worldBook,.*?\s*\),", "", s)
write(p, s)

p = "lib/core/services/app_control/app_control_service.dart"
s = drop_imports(read(p))
s = re.sub(r"(?m)^\s*static const String worldBook =.*\n", "", s)
s = s.replace("- `world_book`: create, update, delete, activate/deactivate, import/export books, and add/update/delete entries.\n", "")
s = s.replace("containing assistant settings, skills, world books, quick phrases", "containing assistant settings, skills, quick phrases")
s = s.replace("memory, instruction injection, or world book.", "memory or instruction injection.")
s = re.sub(r"(?ms)\n    \{\n      'target': AppControlTargets\.worldBook,.*?\n    \},", "", s)
s = re.sub(r"(?ms)\n\s*AppControlTargets\.worldBook => await _executeWorldBook\(.*?\n\s*\),", "", s)
s = re.sub(r"(?ms)^\s*case AppControlTargets\.worldBook:.*?(?=^\s*case AppControlTargets\.mcpServer:)", "", s)
for name in ["_executeWorldBook", "_patchWorldBook", "_worldBookEntryFromArgs", "_patchWorldBookEntry", "_worldBookSnapshot", "_restoreWorldBooks", "_bookIdArg"]:
    s = remove_function(s, name)
s = re.sub(r"(?m)^\s*AppControlTargets\.worldBook =>.*\n", "", s)
s = re.sub(r"(?ms)\n            'entry_id': \{.*?\n            \},", "", s)
s = re.sub(r"(?ms)\n            'book_id': \{.*?\n            \},", "", s)
token = "if (bundle['world_books'] is Map)"
if token in s:
    s = remove_braced(s, s.find(token))
s = re.sub(r"(?m)^\s*'world_books':.*\n", "", s)
write(p, s)

p = "test/core/services/app_control_service_test.dart"
s = drop_imports(read(p))
start = s.find("  testWidgets('神经权能网关 edits world book entries")
if start >= 0:
    end = s.find("  testWidgets('神经权能网关 records audit log'", start)
    if end >= 0:
        s = s[:start] + s[end:]
s = s.replace("        ChangeNotifierProvider<WorldBookProvider>(\n          create: (_) => WorldBookProvider(),\n        ),\n", "")
write(p, s)

for path in Path("lib/l10n").glob("*.arb"):
    data = json.loads(path.read_text(encoding="utf-8"))
    data = {key: value for key, value in data.items() if "worldbook" not in key.lower()}
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

write("PROGRESS.md", "TASK: 删除世界书功能及全部引用代码\nSTEP: 已实现，准备发布\nDONE: 已移除移动端和桌面端设置中的世界书入口；删除世界书模型、存储、Provider、管理页面、弹窗和聊天选择器；移除消息构建中的世界书提示注入；清理神经权能网关、应用迁移包和测试中的世界书能力；保留其它聊天、指令注入、技能、记忆、MCP、搜索及设置功能。\nNEXT: 更新补丁版本并创建 Release。")