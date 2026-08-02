import 'package:flutter_test/flutter_test.dart';
import 'package:tin/core/services/chat/local_response_timer.dart';

void main() {
  tearDown(LocalResponseTimer.debugReset);

  test('stops on the first response and keeps the frozen duration', () {
    final start = DateTime(2026, 8, 2, 12);
    LocalResponseTimer.start('message', now: start);

    LocalResponseTimer.stopOnFirstResponse(
      'message',
      now: start.add(const Duration(milliseconds: 1250)),
    );
    LocalResponseTimer.stopOnFirstResponse(
      'message',
      now: start.add(const Duration(seconds: 9)),
    );

    final snapshot = LocalResponseTimer.listenable('message').value;
    expect(snapshot.running, isFalse);
    expect(snapshot.elapsed, const Duration(milliseconds: 1250));
  });

  test('cancel hides a timer that has no response', () {
    LocalResponseTimer.start('message');
    LocalResponseTimer.cancel('message');

    final snapshot = LocalResponseTimer.listenable('message').value;
    expect(snapshot.running, isFalse);
    expect(snapshot.elapsed, isNull);
  });
}
