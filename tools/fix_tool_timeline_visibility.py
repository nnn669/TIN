import io


def read(path):
    with io.open(path, encoding='utf-8') as handle:
        return handle.read()


def write(path, content):
    with io.open(path, 'w', encoding='utf-8', newline='') as handle:
        handle.write(content)


chat_path = 'lib/features/chat/widgets/chat_message_widget.dart'
chat = read(chat_path)
old = chat

old_standalone = """bool _toolPartNeedsStandaloneStep(
  ToolApprovalService approvalService,
  ToolUIPart part,
) {
  if (_pendingApprovalForToolPart(approvalService, part) != null) {
    return true;
  }
  if (part.toolName == LocalToolNames.askUser) {
    return part.loading || part.content?.trim().isNotEmpty != true;
  }
  return false;
}
"""
new_standalone = """bool _toolPartNeedsStandaloneStep(
  ToolApprovalService approvalService,
  ToolUIPart part,
) {
  if (_pendingApprovalForToolPart(approvalService, part) != null) {
    return true;
  }
  // Interactive local tools and ask-user cards must remain visible so their
  // controls and results are immediately available instead of being hidden in
  // a collapsed generic tool group.
  if (part.toolName == LocalToolNames.askUser ||
      part.toolName == LocalToolNames.timeInfo ||
      part.toolName == LocalToolNames.clipboard ||
      part.toolName == LocalToolNames.textToSpeech ||
      part.toolName == LocalToolNames.calculate) {
    return true;
  }
  return false;
}
"""
if old_standalone not in chat:
    raise SystemExit('standalone helper pattern not found')
chat = chat.replace(old_standalone, new_standalone, 1)

old_flush = """    void flushGroupedTools() {
      if (groupedTools.isEmpty) return;
      toolCount += groupedTools.length;
      steps.add(
        _TimelineStepData.toolGroup(
          toolGroup: List<ToolUIPart>.of(groupedTools),
          reasoningCountAfter: reasoningCount,
          toolCountAfter: toolCount,
        ),
      );
      groupedTools.clear();
    }
"""
new_flush = """    void flushGroupedTools() {
      if (groupedTools.isEmpty) return;
      if (groupedTools.length == 1) {
        final tool = groupedTools.single;
        groupedTools.clear();
        steps.add(
          _TimelineStepData.tool(
            tool: tool,
            reasoningCountAfter: reasoningCount,
            toolCountAfter: ++toolCount,
          ),
        );
        return;
      }
      toolCount += groupedTools.length;
      steps.add(
        _TimelineStepData.toolGroup(
          toolGroup: List<ToolUIPart>.of(groupedTools),
          reasoningCountAfter: reasoningCount,
          toolCountAfter: toolCount,
        ),
      );
      groupedTools.clear();
    }
"""
if old_flush not in chat:
    raise SystemExit('group flush pattern not found')
chat = chat.replace(old_flush, new_flush, 1)
if chat == old:
    raise SystemExit('chat file was not changed')
write(chat_path, chat)

layout_test_path = 'test/features/assistant/assistant_edit_tab_layout_test.dart'
layout_test = read(layout_test_path)
old_layout = """        'memory',
        'quickPhrase',
        'custom',
"""
new_layout = """        'memory',
        'quickPhrase',
        'skills',
        'custom',
"""
if old_layout not in layout_test:
    raise SystemExit('layout test pattern not found')
write(layout_test_path, layout_test.replace(old_layout, new_layout, 1))

print('updated interactive timeline visibility and assistant tab expectation')
