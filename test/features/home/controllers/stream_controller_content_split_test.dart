import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/home/controllers/stream_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const {});

  StreamController buildController() {
    return StreamController(
      chatService: ChatService(),
      onStateChanged: () {},
      getSettingsProvider: () => SettingsProvider(),
      getCurrentConversationId: () => null,
    );
  }

  test('v2 reasoning payload preserves content split metadata', () {
    final controller = buildController();
    final segment = ReasoningSegmentData()
      ..text = 'thinking'
      ..expanded = false
      ..toolStartIndex = 0;

    final json = controller.serializeReasoningSegmentsWithSplits(
      [segment],
      contentSplitOffsets: const [12],
      reasoningCountAtSplit: const [1],
      toolCountAtSplit: const [2],
    );

    final restoredSegments = controller.deserializeReasoningSegments(json);
    final restoredSplits = controller.deserializeContentSplits(json);

    expect(restoredSegments, hasLength(1));
    expect(restoredSegments.single.text, 'thinking');
    expect(restoredSplits, isNotNull);
    expect(restoredSplits!.offsets, const [12]);
    expect(restoredSplits.reasoningCounts, const [1]);
    expect(restoredSplits.toolCounts, const [2]);
  });

  test('v1 reasoning payload remains compatible without content splits', () {
    final controller = buildController();
    final segment = ReasoningSegmentData()
      ..text = 'legacy'
      ..expanded = true
      ..toolStartIndex = 0;

    final json = controller.serializeReasoningSegments([segment]);

    expect(controller.deserializeReasoningSegments(json), hasLength(1));
    expect(controller.deserializeContentSplits(json), isNull);
  });

  test(
    'finishReasoningAndPersist writes v2 payload for tool-only splits',
    () async {
      final controller = buildController();
      const messageId = 'assistant-message';
      controller.setContentSplitData(
        messageId,
        const ContentSplitData(
          offsets: [8],
          reasoningCounts: [0],
          toolCounts: [1],
        ),
      );

      String? persistedJson;
      await controller.finishReasoningAndPersist(
        messageId,
        updateReasoningInDb:
            (
              messageId, {
              String? reasoningText,
              DateTime? reasoningFinishedAt,
              String? reasoningSegmentsJson,
            }) async {
              expect(messageId, 'assistant-message');
              persistedJson = reasoningSegmentsJson ?? persistedJson;
            },
      );

      expect(persistedJson, isNotNull);
      expect(controller.deserializeReasoningSegments(persistedJson), isEmpty);
      final restoredSplits = controller.deserializeContentSplits(persistedJson);
      expect(restoredSplits, isNotNull);
      expect(restoredSplits!.toolCounts, const [1]);
    },
  );

  test(
    'restoreMessageUiState restores tool parts and empty v2 split metadata',
    () {
      final controller = buildController();
      final message = ChatMessage(
        id: 'assistant-1',
        role: 'assistant',
        content: '让我帮你搜索一下',
        conversationId: 'conversation-1',
        reasoningSegmentsJson: controller.serializeReasoningSegmentsWithSplits(
          const [],
          contentSplitOffsets: const [],
          reasoningCountAtSplit: const [],
          toolCountAtSplit: const [],
        ),
      );

      controller.restoreMessageUiState(
        message,
        getToolEventsFromDb: (_) => const [
          {
            'id': 'tool-1',
            'name': 'search_web',
            'arguments': {'query': 'Kelivo'},
            'content': null,
          },
        ],
        getGeminiThoughtSigFromDb: (_) => null,
      );

      expect(controller.contentSplits[message.id], isNotNull);
      expect(controller.contentSplits[message.id]!.offsets, isEmpty);
      expect(controller.toolParts[message.id], hasLength(1));
      expect(controller.toolParts[message.id]!.single.loading, isTrue);
    },
  );
}
