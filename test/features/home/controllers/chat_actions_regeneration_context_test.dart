import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/features/home/controllers/chat_actions.dart';

ChatMessage _message({
  required String id,
  required String role,
  required String groupId,
  required int version,
}) {
  return ChatMessage(
    id: id,
    role: role,
    content: '$role-$id',
    conversationId: 'conversation-1',
    groupId: groupId,
    version: version,
  );
}

void main() {
  group('ChatActions.buildRegenerationMessages', () {
    test('重试 assistant 时不会把后续分组带入上下文', () {
      final messages = <ChatMessage>[
        _message(id: 'u1', role: 'user', groupId: 'u1', version: 0),
        _message(id: 'a1-v0', role: 'assistant', groupId: 'a1', version: 0),
        _message(id: 'u2', role: 'user', groupId: 'u2', version: 0),
        _message(id: 'a2-v0', role: 'assistant', groupId: 'a2', version: 0),
        _message(id: 'a1-v1', role: 'assistant', groupId: 'a1', version: 1),
      ];
      final placeholder = _message(
        id: 'a1-v2',
        role: 'assistant',
        groupId: 'a1',
        version: 2,
      ).copyWith(content: '', isStreaming: true);

      final result = ChatActions.buildRegenerationMessages(
        messages: messages,
        lastKeep: 1,
        targetGroupId: 'a1',
        assistantPlaceholder: placeholder,
      );

      expect(result.map((message) => message.id).toList(), [
        'u1',
        'a1-v0',
        'a1-v1',
        'a1-v2',
      ]);
    });

    test('重试 user 时只保留该用户消息之前的上下文并追加新的回复占位', () {
      final messages = <ChatMessage>[
        _message(id: 'u1', role: 'user', groupId: 'u1', version: 0),
        _message(id: 'a1-v0', role: 'assistant', groupId: 'a1', version: 0),
        _message(id: 'u2', role: 'user', groupId: 'u2', version: 0),
        _message(id: 'a2-v0', role: 'assistant', groupId: 'a2', version: 0),
        _message(id: 'u3', role: 'user', groupId: 'u3', version: 0),
        _message(id: 'a3-v0', role: 'assistant', groupId: 'a3', version: 0),
      ];
      final placeholder = _message(
        id: 'a2-v1',
        role: 'assistant',
        groupId: 'a2',
        version: 1,
      ).copyWith(content: '', isStreaming: true);

      final result = ChatActions.buildRegenerationMessages(
        messages: messages,
        lastKeep: 3,
        targetGroupId: 'a2',
        assistantPlaceholder: placeholder,
      );

      expect(result.map((message) => message.id).toList(), [
        'u1',
        'a1-v0',
        'u2',
        'a2-v0',
        'a2-v1',
      ]);
    });
  });
}
