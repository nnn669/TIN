#!/usr/bin/env python3
"""Apply the two remaining UI integrations without rewriting large Dart files."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
MCP_PAGE = ROOT / "lib/features/mcp/pages/mcp_page.dart"
CHAT_WIDGET = ROOT / "lib/features/chat/widgets/chat_message_widget.dart"
OPENERS = "([{"
CLOSERS = ")] }".replace(" ", "")


class PatchError(RuntimeError):
    pass


def read_source(path: Path):
    raw = path.read_bytes().decode("utf-8")
    crlf = "\r\n" in raw
    return raw.replace("\r\n", "\n"), crlf


def write_source(path: Path, text: str, crlf: bool):
    if crlf:
        text = text.replace("\n", "\r\n")
    path.write_bytes(text.encode("utf-8"))


def skip_string(text: str, index: int) -> int:
    quote = text[index]
    index += 1
    while index < len(text):
        if text[index] == "\\":
            index += 2
        elif text[index] == quote:
            return index + 1
        else:
            index += 1
    raise PatchError("unterminated string literal")


def balanced_end(text: str, open_index: int) -> int:
    if text[open_index] not in OPENERS:
        raise PatchError("balanced_end called on a non-opening bracket")
    depth = 0
    index = open_index
    while index < len(text):
        char = text[index]
        if char in "'\"":
            index = skip_string(text, index)
            continue
        if char in OPENERS:
            depth += 1
        elif char in CLOSERS:
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    raise PatchError("unbalanced brackets")


def argument_end(text: str, value_start: int) -> int:
    """Find the comma ending a named argument, ignoring nested expressions."""
    depth = 0
    index = value_start
    while index < len(text):
        char = text[index]
        if char in "'\"":
            index = skip_string(text, index)
            continue
        if char in OPENERS:
            depth += 1
        elif char in CLOSERS:
            if depth == 0:
                return index
            depth -= 1
        elif char == "," and depth == 0:
            return index
        index += 1
    raise PatchError("could not find named argument terminator")


def ensure_import(text: str, anchor: str, statement: str) -> str:
    if statement in text:
        return text
    if text.count(anchor) != 1:
        raise PatchError(f"import anchor count is not one: {anchor!r}")
    return text.replace(anchor, anchor + "\n" + statement, 1)


AUTO_APPROVAL_TILE = r'''
/// Global MCP tool execution switch. The app-control gateway has its own
/// approval policy and is intentionally not affected by this switch.
class _McpAutoApprovalTile extends StatelessWidget {
  const _McpAutoApprovalTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final store = McpToolAutoApprovalStore.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: store.listenable,
      builder: (context, enabled, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.1 : 0.08),
              width: 0.6,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Lucide.Activity,
                  size: 20,
                  color: enabled ? cs.primary : cs.onSurface.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MCP 工具自动执行',
                      style: TextStyle(
                        fontWeight: AppFontWeights.emphasis,
                        color: cs.onSurface.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      enabled ? '所有工具直接执行，无需审批' : '按每个工具的配置逐个审批',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.58),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: enabled,
                onChanged: (value) {
                  Haptics.light();
                  store.setEnabled(value);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
'''


def patch_mcp_page() -> bool:
    text, crlf = read_source(MCP_PAGE)
    original = text
    text = ensure_import(
        text,
        "import '../../../theme/app_font_weights.dart';",
        "import '../../../core/services/mcp/mcp_tool_auto_approval.dart';",
    )

    if "_McpAutoApprovalTile()" not in text:
        scaffold = text.find("    return Scaffold(")
        body = text.find("\n      body:", scaffold)
        if scaffold < 0 or body < 0:
            raise PatchError("Scaffold body anchor not found")
        value_start = body + 1 + len("      body:")
        while value_start < len(text) and text[value_start].isspace():
            value_start += 1
        value_end = argument_end(text, value_start)
        expression = text[value_start:value_end].strip()
        wrapped = (
            "Column(\n"
            "        children: [\n"
            "          const Padding(\n"
            "            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),\n"
            "            child: _McpAutoApprovalTile(),\n"
            "          ),\n"
            "          Expanded(child: " + expression + "),\n"
            "        ],\n"
            "      )"
        )
        text = text[:value_start] + wrapped + text[value_end:]

    if "class _McpAutoApprovalTile" not in text:
        marker = "class _McpCallLogCard extends StatelessWidget {"
        if text.count(marker) != 1:
            raise PatchError("MCP call log class anchor count is not one")
        text = text.replace(marker, AUTO_APPROVAL_TILE + "\n" + marker, 1)

    if text == original:
        return False
    write_source(MCP_PAGE, text, crlf)
    return True


def patch_chat_widget() -> bool:
    text, crlf = read_source(CHAT_WIDGET)
    original = text
    text = ensure_import(
        text,
        "import 'token_display_widget.dart';",
        "import 'generation_timer_badge.dart';",
    )

    if "GenerationTimerBadge(" not in text:
        marker = "                    if (settings.showModelName)\n"
        marker_start = text.find(marker)
        if marker_start < 0:
            raise PatchError("model-name condition anchor not found")
        text_start = text.find("                      Text(", marker_start + len(marker))
        if text_start < 0 or text.count("                      Text(", marker_start) < 1:
            raise PatchError("model-name Text anchor not found")
        open_index = text_start + text[text_start:].find("(")
        text_end = balanced_end(text, open_index)
        old_expression = text[text_start:text_end].strip()
        replacement = (
            "                    Row(\n"
            "                      mainAxisSize: MainAxisSize.min,\n"
            "                      children: [\n"
            "                        Flexible(child: " + old_expression + "),\n"
            "                        const SizedBox(width: 6),\n"
            "                        GenerationTimerBadge(\n"
            "                          isStreaming: widget.message.isStreaming,\n"
            "                          startTime: widget.message.timestamp,\n"
            "                          durationMs: widget.message.durationMs,\n"
            "                        ),\n"
            "                      ],\n"
            "                    )"
        )
        text = text[:text_start] + replacement + text[text_end:]

    if text == original:
        return False
    write_source(CHAT_WIDGET, text, crlf)
    return True


def main() -> int:
    changed = []
    if patch_mcp_page():
        changed.append(str(MCP_PAGE.relative_to(ROOT)))
    if patch_chat_widget():
        changed.append(str(CHAT_WIDGET.relative_to(ROOT)))
    print("patched: " + (", ".join(changed) if changed else "already applied"))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as error:
        print(f"patch failed: {error}", file=sys.stderr)
        raise SystemExit(1)