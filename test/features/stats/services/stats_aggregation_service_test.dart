import 'package:flutter_test/flutter_test.dart';
import 'package:tin/core/models/chat_message.dart';
import 'package:tin/core/models/conversation.dart';
import 'package:tin/features/stats/models/stats_models.dart';
import 'package:tin/features/stats/services/stats_aggregation_service.dart';

void main() {
  group('StatsAggregationService', () {
    final now = DateTime(2026, 5, 3, 12);

    Conversation conversation(
      String id, {
      required DateTime createdAt,
      String title = 'Topic',
    }) {
      return Conversation(
        id: id,
        title: title,
        createdAt: createdAt,
        updatedAt: createdAt,
        messageIds: const [],
      );
    }

    ChatMessage message(
      String id, {
      required String conversationId,
      required DateTime timestamp,
      int? totalTokens,
      int? promptTokens,
      int? completionTokens,
      int? cachedTokens,
      String? providerId,
    }) {
      return ChatMessage(
        id: id,
        role: 'assistant',
        content: id,
        timestamp: timestamp,
        conversationId: conversationId,
        totalTokens: totalTokens,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        cachedTokens: cachedTokens,
        providerId: providerId,
      );
    }

    test('builds a 30-day heatmap ending on the supplied system date', () {
      final yesterday = DateTime(2026, 5, 2, 9);
      final conversations = [
        conversation('c1', createdAt: yesterday),
      ];
      final messages = {
        'c1': [
          message(
            'm1',
            conversationId: 'c1',
            timestamp: yesterday,
            promptTokens: 10,
            completionTokens: 20,
            cachedTokens: 3,
            providerId: 'openai',
          ),
          message(
            'm2',
            conversationId: 'c1',
            timestamp: yesterday,
            promptTokens: 7,
            completionTokens: 11,
            providerId: 'openai',
          ),
        ],
      };

      final snapshot = StatsAggregationService.buildSnapshot(
        now: now,
        range: StatsDateRange.allTime(now),
        conversations: conversations,
        messagesByConversation: messages,
        launchCount: 1,
        unknownProviderLabel: 'Unknown provider',
        unknownTopicLabel: 'Untitled topic',
      );

      expect(snapshot.heatmap, hasLength(30));
      expect(snapshot.heatmap.first.date, DateTime(2026, 4, 4));
      expect(snapshot.heatmap.last.date, DateTime(2026, 5, 3));
      final lastActiveDay = snapshot.heatmap.singleWhere(
        (day) => day.date == DateTime(2026, 5, 2),
      );
      expect(lastActiveDay.count, 2);
      expect(lastActiveDay.tokens, 48);
      expect(lastActiveDay.tokenCount, 48);
    });

    test('uses legacy totalTokens when categorized values are absent', () {
      final day = DateTime(2026, 5, 2);
      final snapshot = StatsAggregationService.buildSnapshot(
        now: now,
        range: StatsDateRange.allTime(now),
        conversations: [conversation('legacy', createdAt: day)],
        messagesByConversation: {
          'legacy': [
            message(
              'legacy-message',
              conversationId: 'legacy',
              timestamp: day,
              totalTokens: 42,
            ),
          ],
        },
        launchCount: 1,
        unknownProviderLabel: 'Unknown provider',
        unknownTopicLabel: 'Untitled topic',
      );

      expect(
        snapshot.heatmap.singleWhere((item) => item.date == day).tokens,
        42,
      );
    });

    test('keeps date normalization stable across time components', () {
      final snapshot = StatsAggregationService.buildSnapshot(
        now: DateTime(2026, 3, 10, 12),
        range: StatsDateRange.last30Days(DateTime(2026, 3, 10, 12)),
        conversations: [
          conversation('dst', createdAt: DateTime(2026, 3, 8, 9)),
        ],
        messagesByConversation: {
          'dst': [
            message(
              'dst-message',
              conversationId: 'dst',
              timestamp: DateTime(2026, 3, 8, 23),
              promptTokens: 3,
              completionTokens: 5,
            ),
          ],
        },
        launchCount: 1,
        unknownProviderLabel: 'Unknown provider',
        unknownTopicLabel: 'Untitled topic',
      );

      expect(snapshot.heatmap, hasLength(30));
      expect(snapshot.heatmap.last.date, DateTime(2026, 3, 10));
      expect(
        snapshot.heatmap.singleWhere(
          (day) => day.date == DateTime(2026, 3, 8),
        ).tokens,
        8,
      );
    });
  });
}