from pathlib import Path


def replace_once(path_name: str, old: str, new: str) -> None:
    path = Path(path_name)
    source = path.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise SystemExit(
            f"{path_name}: expected exactly one match, got {count}: {old[:80]!r}"
        )
    path.write_text(source.replace(old, new), encoding="utf-8")


manifest = "android/app/src/main/AndroidManifest.xml"
replace_once(
    manifest,
    '        <service\n'
    '            android:name="de.julianassmann.flutter_background.IsolateHolderService"\n'
    '            android:exported="false"\n'
    '            android:foregroundServiceType="dataSync" />\n',
    '        <service\n'
    '            android:name="de.julianassmann.flutter_background.IsolateHolderService"\n'
    '            android:exported="false"\n'
    '            android:foregroundServiceType="dataSync" />\n'
    '        <service\n'
    '            android:name=".TermuxCommandResultService"\n'
    '            android:exported="false" />\n',
)

local_tools_path = Path("lib/features/home/services/local_tools_service.dart")
local_tools = local_tools_path.read_text(encoding="utf-8")
local_tools = local_tools.replace(
    "import '../../../core/services/termux_command.dart';\n", "", 1
)
local_tools = local_tools.replace(
    "  static const String termuxRunCommand = 'termux_run_command';\n", "", 1
)
schema_start = (
    "    if (assistant.localToolIds.contains(LocalToolNames.termuxRunCommand)) {\n"
)
schema_end = "    return tools;\n"
start = local_tools.find(schema_start)
end = local_tools.find(schema_end, start)
if start < 0 or end < 0:
    raise SystemExit("local_tools_service.dart: Termux schema block not found")
local_tools = local_tools[:start] + local_tools[end:]
call_block = (
    "    if (name == LocalToolNames.termuxRunCommand) {\n"
    "      return _handleTermuxRunCommand(args);\n"
    "    }\n"
)
if local_tools.count(call_block) != 1:
    raise SystemExit("local_tools_service.dart: Termux call block not found")
local_tools = local_tools.replace(call_block, "")
handler_start = "  static Future<String> _handleTermuxRunCommand(\n"
handler_end = "  static Map<String, dynamic> _buildTimeInfoPayload(DateTime now) {\n"
start = local_tools.find(handler_start)
end = local_tools.find(handler_end, start)
if start < 0 or end < 0:
    raise SystemExit("local_tools_service.dart: Termux handler block not found")
local_tools_path.write_text(local_tools[:start] + local_tools[end:], encoding="utf-8")

provider = "lib/core/providers/mcp_provider.dart"
replace_once(
    provider,
    "import '../services/mcp/kelivo_images/kelivo_images_server.dart';\n",
    "import '../services/mcp/kelivo_images/kelivo_images_server.dart';\n"
    "import '../services/mcp/kelivo_termux/kelivo_termux_server.dart';\n",
)
replace_once(
    provider,
    "  static const String _builtinImagesName = '@kelivo/images';\n",
    "  static const String _builtinImagesName = '@kelivo/images';\n"
    "  static const String _builtinTermuxId = 'kelivo_termux';\n"
    "  static const String _builtinTermuxName = '@kelivo/termux';\n",
)
replace_once(
    provider,
    "    if (!_hasBuiltinServer(_builtinImagesId, _builtinImagesName)) {\n"
    "      next.add(\n"
    "        _builtinServer(_builtinImagesId, _builtinImagesName, enabled: false),\n"
    "      );\n"
    "    }\n",
    "    if (!_hasBuiltinServer(_builtinImagesId, _builtinImagesName)) {\n"
    "      next.add(\n"
    "        _builtinServer(_builtinImagesId, _builtinImagesName, enabled: false),\n"
    "      );\n"
    "    }\n"
    "    if (!_hasBuiltinServer(_builtinTermuxId, _builtinTermuxName)) {\n"
    "      next.add(\n"
    "        _builtinServer(_builtinTermuxId, _builtinTermuxName, enabled: false),\n"
    "      );\n"
    "    }\n",
)
replace_once(
    provider,
    "  bool _isLegacyBuiltinCopilotServer(McpServerConfig server) {\n",
    "  bool _isBuiltinTermuxServer(McpServerConfig server) {\n"
    "    return server.transport == McpTransportType.inmemory &&\n"
    "        (server.id == _builtinTermuxId || server.name == _builtinTermuxName);\n"
    "  }\n\n"
    "  bool _isLegacyBuiltinCopilotServer(McpServerConfig server) {\n",
)
replace_once(
    provider,
    "        _isBuiltinImagesServer(server);\n",
    "        _isBuiltinImagesServer(server) ||\n"
    "        _isBuiltinTermuxServer(server);\n",
)
replace_once(
    provider,
    "    return KelivoFetchMcpServerEngine();\n",
    "    if (_isBuiltinTermuxServer(server)) {\n"
    "      return KelivoTermuxMcpServerEngine();\n"
    "    }\n"
    "    return KelivoFetchMcpServerEngine();\n",
)
replace_once(
    provider,
    "            } else if (id == _builtinImagesId ||\n"
    "                name == _builtinImagesName) {\n"
    "              builtinEnabledById[_builtinImagesId] = enabled;\n"
    "            } else if (id == 'kelivo_copilot' ||\n",
    "            } else if (id == _builtinImagesId ||\n"
    "                name == _builtinImagesName) {\n"
    "              builtinEnabledById[_builtinImagesId] = enabled;\n"
    "            } else if (id == _builtinTermuxId ||\n"
    "                name == _builtinTermuxName) {\n"
    "              builtinEnabledById[_builtinTermuxId] = enabled;\n"
    "            } else if (id == 'kelivo_copilot' ||\n",
)
replace_once(
    provider,
    "          next.add(\n"
    "            _builtinServer(\n"
    "              _builtinImagesId,\n"
    "              _builtinImagesName,\n"
    "              enabled: false,\n"
    "            ).copyWith(enabled: builtinEnabledById[_builtinImagesId] ?? false),\n"
    "          );\n",
    "          next.add(\n"
    "            _builtinServer(\n"
    "              _builtinImagesId,\n"
    "              _builtinImagesName,\n"
    "              enabled: false,\n"
    "            ).copyWith(enabled: builtinEnabledById[_builtinImagesId] ?? false),\n"
    "          );\n"
    "          next.add(\n"
    "            _builtinServer(\n"
    "              _builtinTermuxId,\n"
    "              _builtinTermuxName,\n"
    "              enabled: false,\n"
    "            ).copyWith(enabled: builtinEnabledById[_builtinTermuxId] ?? false),\n"
    "          );\n",
)
replace_once(
    provider,
    "                    (_isBuiltinGithubServer(_servers[idx]) &&\n"
    "                        _builtinGithubWriteToolNames.contains(t.name)),\n",
    "                    (_isBuiltinGithubServer(_servers[idx]) &&\n"
    "                        _builtinGithubWriteToolNames.contains(t.name)) ||\n"
    "                    _isBuiltinTermuxServer(_servers[idx]),\n",
)

Path("test/termux_local_tool_test.dart").unlink()
