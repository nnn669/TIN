import 'package:flutter_test/flutter_test.dart';

import 'package:tin/core/models/token_usage.dart';

void main() {
  group('TokenUsage', () {
    test(
      'merge preserves explicit total when split token fields are missing',
      () {
        final merged = const TokenUsage().merge(
          const TokenUsage(totalTokens: 895),
        );

        expect(merged.promptTokens, 0);
        expect(merged.completionTokens, 0);
        expect(merged.cachedTokens, 0);
        expect(merged.totalTokens, 895);
      },
    );

    test('merge replaces snapshots within one streaming round', () {
      final first = const TokenUsage(
        promptTokens: 100,
        completionTokens: 4,
        cachedTokens: 20,
      );
      final latest = first.merge(
        const TokenUsage(
          promptTokens: 100,
          completionTokens: 12,
          cachedTokens: 20,
        ),
      );

      expect(latest.promptTokens, 100);
      expect(latest.completionTokens, 12);
      expect(latest.cachedTokens, 20);
      expect(latest.totalTokens, 112);
    });

    test('merge accumulates when a tool follow-up increases the prompt', () {
      final firstRound = const TokenUsage(
        promptTokens: 100,
        completionTokens: 20,
        cachedTokens: 10,
      );
      final secondRound = firstRound.merge(
        const TokenUsage(
          promptTokens: 160,
          completionTokens: 8,
          cachedTokens: 30,
        ),
      );
      final secondRoundLatest = secondRound.merge(
        const TokenUsage(
          promptTokens: 160,
          completionTokens: 14,
          cachedTokens: 30,
        ),
      );

      expect(secondRoundLatest.promptTokens, 260);
      expect(secondRoundLatest.completionTokens, 34);
      expect(secondRoundLatest.cachedTokens, 40);
      expect(secondRoundLatest.totalTokens, 294);
    });

    test('merge replaces an already cumulative provider snapshot', () {
      final previous = const TokenUsage(
        promptTokens: 100,
        completionTokens: 20,
      );
      final cumulative = previous.merge(
        const TokenUsage(promptTokens: 160, completionTokens: 8),
      );
      final state = previous.merge(cumulative);

      expect(state.promptTokens, cumulative.promptTokens);
      expect(state.completionTokens, cumulative.completionTokens);
      expect(state.totalTokens, cumulative.totalTokens);
    });

    test('add explicitly accumulates completed rounds', () {
      final total = const TokenUsage(
        promptTokens: 100,
        completionTokens: 20,
      ).add(
        const TokenUsage(promptTokens: 160, completionTokens: 8),
      );

      expect(total.promptTokens, 260);
      expect(total.completionTokens, 28);
      expect(total.totalTokens, 288);
    });
  });
}
