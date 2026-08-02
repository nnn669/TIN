from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one match, found {count}')
    file.write_text(text.replace(old, new))


replace_once(
    'lib/features/chat/widgets/chat_message_widget.dart',
    "import 'token_display_widget.dart';\n",
    "import 'token_display_widget.dart';\nimport 'local_response_timer_badge.dart';\n",
)
replace_once(
    'lib/features/chat/widgets/chat_message_widget.dart',
    "                          ),\n                        ],\n                      ),\n                    Builder(\n",
    "                          ),\n                          const SizedBox(width: 6),\n                          LocalResponseTimerBadge(\n                            messageId: widget.message.id,\n                          ),\n                        ],\n                      ),\n                    Builder(\n",
)
replace_once(
    'lib/features/home/controllers/chat_actions.dart',
    "import '../../../core/services/chat/chat_service.dart';\n",
    "import '../../../core/services/chat/chat_service.dart';\nimport '../../../core/services/chat/local_response_timer.dart';\n",
)
replace_once(
    'lib/features/home/controllers/chat_actions.dart',
    "      final stream = ChatApiService.sendMessageStream(\n",
    "      LocalResponseTimer.start(state.messageId);\n      final stream = ChatApiService.sendMessageStream(\n",
)
replace_once(
    'lib/features/home/controllers/chat_actions.dart',
    "    // Handle reasoning\n",
    "    final hasFirstResponse =\n        chunkContent.isNotEmpty ||\n        (chunk.reasoning?.isNotEmpty ?? false) ||\n        (chunk.toolCalls?.isNotEmpty ?? false) ||\n        (chunk.toolResults?.isNotEmpty ?? false);\n    if (hasFirstResponse) {\n      LocalResponseTimer.stopOnFirstResponse(state.messageId);\n    }\n    // Handle reasoning\n",
)
replace_once(
    'lib/features/home/controllers/chat_actions.dart',
    "      streamController.markStreamingEnded(streaming.id);\n      streamController.cleanupTimers(streaming.id);\n",
    "      streamController.markStreamingEnded(streaming.id);\n      LocalResponseTimer.cancel(streaming.id);\n      streamController.cleanupTimers(streaming.id);\n",
)
replace_once(
    'lib/features/home/controllers/chat_actions.dart',
    "    streamController.markStreamingEnded(messageId);\n    streamController.cleanupTimers(messageId);\n    final rawContent = state.fullContentRaw.isNotEmpty\n",
    "    streamController.markStreamingEnded(messageId);\n    LocalResponseTimer.cancel(messageId);\n    streamController.cleanupTimers(messageId);\n    final rawContent = state.fullContentRaw.isNotEmpty\n",
)
replace_once(
    '.github/workflows/android-test-release.yml',
    "test/mcp_lifecycle_reconnect_test.dart test/provider_request_headers_test.dart\n",
    "test/mcp_lifecycle_reconnect_test.dart test/provider_request_headers_test.dart test/local_response_timer_test.dart\n",
)
