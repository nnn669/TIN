import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tin/core/services/chat/local_response_timer.dart';
import 'package:tin/features/chat/widgets/local_response_timer_badge.dart';

void main() {
  tearDown(LocalResponseTimer.debugReset);

  testWidgets('shows a themed alarm badge after the first response', (
    tester,
  ) async {
    const messageId = 'assistant-message';
    final startedAt = DateTime(2026, 8, 2, 12);
    LocalResponseTimer.start(messageId, now: startedAt);
    LocalResponseTimer.stopOnFirstResponse(
      messageId,
      now: startedAt.add(const Duration(milliseconds: 1234)),
    );

    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: const Scaffold(
          body: LocalResponseTimerBadge(messageId: messageId),
        ),
      ),
    );

    expect(find.byIcon(Icons.alarm_rounded), findsOneWidget);
    expect(find.text('1.2s'), findsOneWidget);

    final badge = tester.widget<Container>(
      find.byKey(const ValueKey('local-response-timer:assistant-message')),
    );
    final decoration = badge.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(10));
    expect(decoration.border, isNotNull);
  });

  testWidgets('stays hidden when no local timing is available', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LocalResponseTimerBadge(messageId: 'missing')),
      ),
    );

    expect(find.byIcon(Icons.alarm_rounded), findsNothing);
    expect(
      find.byKey(const ValueKey('local-response-timer:missing')),
      findsNothing,
    );
  });
}
