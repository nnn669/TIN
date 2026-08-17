from pathlib import Path

path = Path("tools/patch_termux_mcp.py")
source = path.read_text(encoding="utf-8")
target = source.find("builtinEnabledById")
start = source.rfind("replace_once(\n    provider,\n", 0, target)
end = source.find("\nreplace_once(\n    provider,", target)
if start < 0 or end < 0:
    raise SystemExit("provider import branch replacement not found")
replacement = '''replace_once(
    provider,
    "            } else if (id == _builtinImagesId || name == _builtinImagesName) {\\n"
    "              builtinEnabledById[_builtinImagesId] = enabled;\\n"
    "            } else if (id == 'kelivo_copilot' || name == '@kelivo/copilot') {\\n",
    "            } else if (id == _builtinImagesId || name == _builtinImagesName) {\\n"
    "              builtinEnabledById[_builtinImagesId] = enabled;\\n"
    "            } else if (id == _builtinTermuxId || name == _builtinTermuxName) {\\n"
    "              builtinEnabledById[_builtinTermuxId] = enabled;\\n"
    "            } else if (id == 'kelivo_copilot' || name == '@kelivo/copilot') {\\n",
)'''
path.write_text(source[:start] + replacement + source[end:], encoding="utf-8")
