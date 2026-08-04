#!/usr/bin/env python3
"""One-time patcher: drop per-assistant temperature / topP sampling controls.

The Assistant model already lost `temperature` / `topP` (and their clear flags),
but several call sites still reference them, which breaks the release build.
This script removes those call sites. Every edit is anchored and asserted, so an
unexpected file layout aborts the run instead of producing a broken tree.

The script deletes itself and its workflow as part of the same commit.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

PAGE = "lib/features/assistant/pages/assistant_settings_edit_page.dart"
BASIC_TAB = "lib/features/assistant/pages/assistant_settings_edit_basic_tab.dart"
APP_CONTROL = "lib/core/services/app_control/app_control_service.dart"
CHAT_ACTIONS = "lib/features/home/controllers/chat_actions.dart"
APP_CONTROL_TEST = "test/core/services/app_control_service_test.dart"

SELF_PATH = "tools/apply_sampling_removal.py"
WORKFLOW_PATH = ".github/workflows/apply-sampling-removal.yml"

failures: list[str] = []


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def write(rel: str, text: str) -> None:
    (ROOT / rel).write_text(text, encoding="utf-8")


def drop_literal(rel: str, needle: str, *, expected: int = 1) -> None:
    """Delete an exact substring, asserting the occurrence count."""
    text = read(rel)
    found = text.count(needle)
    if found != expected:
        failures.append(
            f"{rel}: expected {expected} occurrence(s) of {needle[:70]!r}, found {found}"
        )
        return
    write(rel, text.replace(needle, "", expected))


def swap_literal(rel: str, needle: str, replacement: str) -> None:
    text = read(rel)
    found = text.count(needle)
    if found != 1:
        failures.append(
            f"{rel}: expected 1 occurrence of {needle[:70]!r}, found {found}"
        )
        return
    write(rel, text.replace(needle, replacement, 1))


def drop_between(rel: str, start: str, end: str) -> None:
    """Delete everything from `start` up to (but excluding) `end`.

    Both anchors must appear exactly once. `end` is preserved.
    """
    text = read(rel)
    if text.count(start) != 1 or text.count(end) != 1:
        failures.append(
            f"{rel}: anchors not unique (start={text.count(start)}, end={text.count(end)})"
        )
        return
    begin = text.index(start)
    finish = text.index(end)
    if finish <= begin:
        failures.append(f"{rel}: end anchor precedes start anchor")
        return
    write(rel, text[:begin] + text[finish:])


def drop_regex(rel: str, pattern: str, *, flags: int = 0) -> None:
    text = read(rel)
    matches = list(re.finditer(pattern, text, flags))
    if len(matches) != 1:
        failures.append(
            f"{rel}: expected 1 regex match for {pattern[:70]!r}, found {len(matches)}"
        )
        return
    match = matches[0]
    write(rel, text[: match.start()] + text[match.end() :])


def newline_of(rel: str) -> str:
    return "\r\n" if "\r\n" in read(rel) else "\n"


def patch_desktop_pane() -> None:
    nl = newline_of(PAGE)
    drop_between(
        PAGE,
        f"            // Temperature{nl}",
        f"            // Context messages{nl}",
    )


def patch_basic_tab() -> None:
    nl = newline_of(BASIC_TAB)
    # iOS section rows for Temperature / Top P.
    drop_between(
        BASIC_TAB,
        f"              // Temperature{nl}",
        f"              // Context messages{nl}",
    )
    # The two bottom sheets that edited those values.
    drop_between(
        BASIC_TAB,
        "  Future<void> _showTemperatureSheet(BuildContext context, Assistant a) async {",
        "  Future<void> _showContextMessagesSheet(",
    )
    # Capability copy no longer mentions the removed control.
    swap_literal(
        BASIC_TAB,
        "'名称、模型、温度、上下文和搜索记忆开关'",
        "'名称、模型、上下文和搜索记忆开关'",
    )


def patch_app_control() -> None:
    drop_literal(
        APP_CONTROL,
        """    if (patch.containsKey('temperature')) {
      final value = patch['temperature'];
      next = value == null || value.toString().trim().isEmpty
          ? next.copyWith(clearTemperature: true)
          : next.copyWith(temperature: _doubleFrom(value).clamp(0.0, 2.0));
    }
    if (patch.containsKey('top_p')) {
      final value = patch['top_p'];
      next = value == null || value.toString().trim().isEmpty
          ? next.copyWith(clearTopP: true)
          : next.copyWith(topP: _doubleFrom(value).clamp(0.0, 1.0));
    }
""",
    )
    swap_literal(
        APP_CONTROL,
        "context size, temperature, max tokens",
        "context size, max tokens",
    )


def patch_chat_actions() -> None:
    drop_literal(
        CHAT_ACTIONS,
        "        temperature: assistant?.temperature,\n        topP: assistant?.topP,\n",
    )


def patch_app_control_test() -> None:
    drop_regex(APP_CONTROL_TEST, r"\n[ \t]*'temperature': 0\.7,")
    drop_regex(APP_CONTROL_TEST, r"\n[ \t]*expect\(updated\.temperature, 0\.7\);")


LEFTOVER_PATTERNS = (
    ".temperature",
    "temperature:",
    "clearTemperature",
    "'temperature'",
    ".topP",
    "topP:",
    "clearTopP",
    "'top_p'",
)


def verify() -> None:
    for rel in (PAGE, BASIC_TAB, APP_CONTROL, CHAT_ACTIONS, APP_CONTROL_TEST):
        text = read(rel)
        for needle in LEFTOVER_PATTERNS:
            if needle in text:
                failures.append(f"{rel}: leftover reference {needle!r}")


def cleanup() -> None:
    for rel in (SELF_PATH, WORKFLOW_PATH):
        target = ROOT / rel
        if target.exists():
            target.unlink()


def main() -> int:
    patch_desktop_pane()
    patch_basic_tab()
    patch_app_control()
    patch_chat_actions()
    patch_app_control_test()

    if failures:
        for line in failures:
            print(f"FAIL: {line}", file=sys.stderr)
        return 1

    verify()
    if failures:
        for line in failures:
            print(f"FAIL: {line}", file=sys.stderr)
        return 1

    cleanup()
    print("Sampling controls removed; patcher self-removed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
