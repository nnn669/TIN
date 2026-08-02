import 'package:flutter_test/flutter_test.dart';
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
