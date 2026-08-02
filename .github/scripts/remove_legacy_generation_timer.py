from __future__ import annotations

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str = "") -> None:
    content = read(path)
    count = content.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, found {count}: {old!r}")
    write(path, content.replace(old, new, 1))


# Stop computing and forwarding whole-generation duration.
path = "lib/features/home/controllers/chat_actions.dart"
replace_once(path, "    state.streamStartedAt ??= DateTime.now();\n")
replace_once(
    path,
    "        durationMs: state.streamStartedAt != null\n"
    "            ? DateTime.now().difference(state.streamStartedAt!).inMilliseconds\n"
    "            : null,\n",
)
replace_once(
    path,
    "    // Compute final duration\n"
    "    final finalDurationMs = state.streamStartedAt != null\n"
    "        ? DateTime.now().difference(state.streamStartedAt!).inMilliseconds\n"
    "        : null;\n",
)
content = read(path)
count = content.count("      durationMs: finalDurationMs,\n")
if count != 3:
    raise RuntimeError(f"{path}: expected 3 final duration writes, found {count}")
write(path, content.replace("      durationMs: finalDurationMs,\n", ""))

# Remove duration from stream throttling and state.
path = "lib/features/home/controllers/stream_controller.dart"
for old in (
    "    int? durationMs,\n",
    "      ..durationMs = durationMs\n",
    "      durationMs: state.durationMs,\n",
    "  DateTime? streamStartedAt;\n",
    "  int? durationMs;\n",
):
    replace_once(path, old)

# Remove duration from lightweight streaming snapshots.
path = "lib/features/home/controllers/streaming_content_notifier.dart"
content = read(path)
for old, expected in (
    ("    int? durationMs,\n", 1),
    ("        durationMs: durationMs ?? current.durationMs,\n", 1),
    ("        durationMs: current.durationMs,\n", 3),
    ("    this.durationMs,\n", 1),
    ("  final int? durationMs;\n", 1),
    ("        durationMs == other.durationMs;\n", 1),
    ("      durationMs.hashCode;\n", 1),
):
    count = content.count(old)
    if count != expected:
        raise RuntimeError(f"{path}: expected {expected}, found {count}: {old!r}")
    content = content.replace(old, "")
write(path, content)

# Remove persisted/model duration. Old Hive field 19 remains safely ignored on read.
path = "lib/core/models/chat_message.dart"
for old in (
    "  @HiveField(19)\n  final int? durationMs;\n\n",
    "    this.durationMs,\n",
    "    int? durationMs,\n",
    "      durationMs: durationMs ?? this.durationMs,\n",
    "      'durationMs': durationMs,\n",
    "      durationMs: json['durationMs'] as int?,\n",
):
    replace_once(path, old)

path = "lib/core/models/chat_message.g.dart"
replace_once(path, "      durationMs: fields[19] is int ? fields[19] as int : null,\n")
replace_once(path, "      ..writeByte(20)\n", "      ..writeByte(19)\n")
replace_once(
    path,
    "      ..writeByte(18)\n"
    "      ..write(obj.cachedTokens)\n"
    "      ..writeByte(19)\n"
    "      ..write(obj.durationMs);\n",
    "      ..writeByte(18)\n"
    "      ..write(obj.cachedTokens);\n",
)

path = "lib/core/services/chat/chat_service.dart"
content = read(path)
for old, expected in (
    ("    int? durationMs,\n", 2),
    ("      durationMs: durationMs ?? message.durationMs,\n", 2),
):
    count = content.count(old)
    if count != expected:
        raise RuntimeError(f"{path}: expected {expected}, found {count}: {old!r}")
    content = content.replace(old, "")
write(path, content)

# Remove duration/speed UI while keeping token counts.
path = "lib/features/chat/widgets/chat_message_widget.dart"
replace_once(path, "                            durationMs: widget.message.durationMs,\n")

path = "lib/features/chat/widgets/token_display_widget.dart"
for old in (
    "    this.durationMs,\n",
    "  final int? durationMs;\n",
    "      (widget.completionTokens != null && widget.completionTokens! > 0) ||\n"
    "      (widget.durationMs != null && widget.durationMs! > 0);\n",
    "                durationMs: widget.durationMs,\n",
):
    replace_once(
        path,
        old,
        "      (widget.completionTokens != null && widget.completionTokens! > 0);\n"
        if old.startswith("      (widget.completionTokens")
        else "",
    )

path = "lib/features/chat/widgets/token_detail_popup.dart"
replace_once(
    path,
    "/// Shows up to 4 rows (hidden when data is null/0):\n"
    "/// - ArrowUp: prompt tokens (with cached count if > 0)\n"
    "/// - ArrowDown: completion tokens\n"
    "/// - Zap: tok/s (completionTokens / durationSeconds)\n"
    "/// - Timer: duration in seconds\n",
    "/// Shows prompt and completion token counts when available.\n",
)
for old in ("    this.durationMs,\n", "  final int? durationMs;\n"):
    replace_once(path, old)
replace_once(
    path,
    "    // tok/s row\n"
    "    if (completionTokens != null &&\n"
    "        completionTokens! > 0 &&\n"
    "        durationMs != null &&\n"
    "        durationMs! > 0) {\n"
    "      final durationSec = durationMs! / 1000.0;\n"
    "      final tokPerSec = completionTokens! / durationSec;\n"
    "      rows.add(_buildRow(\n"
    "        icon: Lucide.Zap,\n"
    "        text: l10n.tokenDetailSpeed(tokPerSec.toStringAsFixed(1)),\n"
    "        cs: cs,\n"
    "      ));\n"
    "    }\n\n"
    "    // Duration row\n"
    "    if (durationMs != null && durationMs! > 0) {\n"
    "      final durationSec = (durationMs! / 1000.0).toStringAsFixed(1);\n"
    "      rows.add(_buildRow(\n"
    "        icon: Lucide.clock,\n"
    "        text: l10n.tokenDetailDuration(durationSec),\n"
    "        cs: cs,\n"
    "      ));\n"
    "    }\n\n",
)

# Remove now-unused localization keys; flutter gen-l10n regenerates Dart APIs.
for arb in (ROOT / "lib/l10n").glob("*.arb"):
    data = json.loads(arb.read_text(encoding="utf-8"))
    changed = False
    for key in (
        "tokenDetailSpeed",
        "@tokenDetailSpeed",
        "tokenDetailDuration",
        "@tokenDetailDuration",
    ):
        changed = data.pop(key, None) is not None or changed
    if changed:
        arb.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

# Add compatibility regression coverage.
write(
    "test/legacy_generation_timer_removal_test.dart",
    """import 'package:flutter_test/flutter_test.dart';
import 'package:tin/core/models/chat_message.dart';

void main() {
  test('legacy whole-generation duration is ignored during JSON import', () {
    final message = ChatMessage.fromJson(<String, dynamic>{
      'id': 'assistant-message',
      'role': 'assistant',
      'content': 'done',
      'timestamp': '2026-08-02T12:00:00.000',
      'conversationId': 'conversation',
      'durationMs': 4321,
    });

    expect(message.toJson(), isNot(contains('durationMs')));
  });
}
""",
)

# Ensure formal PR checks cover this timing work.
workflow = ".github/workflows/android-test-release.yml"
replace_once(
    workflow,
    "      - name: Analyze changed API identity code\n"
    "        run: flutter analyze lib/core/services/api/provider_request_headers.dart test/provider_request_headers_test.dart\n",
    "      - name: Analyze changed code\n"
    "        run: >-\n"
    "          flutter analyze\n"
    "          lib/core/models/chat_message.dart\n"
    "          lib/core/services/api/provider_request_headers.dart\n"
    "          lib/core/services/chat/chat_service.dart\n"
    "          lib/core/services/chat/local_response_timer.dart\n"
    "          lib/features/chat/widgets/chat_message_widget.dart\n"
    "          lib/features/chat/widgets/local_response_timer_badge.dart\n"
    "          lib/features/chat/widgets/token_detail_popup.dart\n"
    "          lib/features/chat/widgets/token_display_widget.dart\n"
    "          lib/features/home/controllers/chat_actions.dart\n"
    "          lib/features/home/controllers/stream_controller.dart\n"
    "          lib/features/home/controllers/streaming_content_notifier.dart\n"
    "          test/legacy_generation_timer_removal_test.dart\n"
    "          test/local_response_timer_test.dart\n"
    "          test/provider_request_headers_test.dart\n",
)
replace_once(
    workflow,
    "        run: flutter test test/features/chat/widgets/reasoning_budget_sheet_test.dart test/kelivo_github_mcp_server_test.dart test/sse_buffer_flush_test.dart test/mcp_lifecycle_reconnect_test.dart test/provider_request_headers_test.dart\n",
    "        run: >-\n"
    "          flutter test\n"
    "          test/features/chat/widgets/reasoning_budget_sheet_test.dart\n"
    "          test/kelivo_github_mcp_server_test.dart\n"
    "          test/sse_buffer_flush_test.dart\n"
    "          test/mcp_lifecycle_reconnect_test.dart\n"
    "          test/provider_request_headers_test.dart\n"
    "          test/local_response_timer_test.dart\n"
    "          test/legacy_generation_timer_removal_test.dart\n",
)

# No functional references to the removed timer may remain outside generated
# localization files (which are regenerated immediately after this script).
for path in ROOT.glob("lib/**/*.dart"):
    text = path.read_text(encoding="utf-8")
    for needle in ("durationMs", "streamStartedAt"):
        if needle in text:
            raise RuntimeError(f"legacy timer reference {needle!r} remains in {path}")
