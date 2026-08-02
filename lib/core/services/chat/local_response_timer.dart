import 'package:flutter/foundation.dart';

@immutable
class LocalResponseTimerSnapshot {
  const LocalResponseTimerSnapshot({
    this.startedAt,
    this.elapsed,
    this.running = false,
  });

  final DateTime? startedAt;
  final Duration? elapsed;
  final bool running;
}

/// Process-local timing for time-to-first-response.
///
/// This state is intentionally not persisted or serialized, so it can never be
/// included in chat history, exports, backups, or upstream model requests.
class LocalResponseTimer {
  LocalResponseTimer._();

  static final Map<String, ValueNotifier<LocalResponseTimerSnapshot>>
  _notifiers = <String, ValueNotifier<LocalResponseTimerSnapshot>>{};

  static ValueListenable<LocalResponseTimerSnapshot> listenable(
    String messageId,
  ) => _notifier(messageId);

  static void start(String messageId, {DateTime? now}) {
    final notifier = _notifier(messageId);
    notifier.value = LocalResponseTimerSnapshot(
      startedAt: now ?? DateTime.now(),
      running: true,
    );
  }

  static void stopOnFirstResponse(String messageId, {DateTime? now}) {
    final notifier = _notifiers[messageId];
    final current = notifier?.value;
    if (notifier == null ||
        current == null ||
        !current.running ||
        current.startedAt == null) {
      return;
    }
    final stoppedAt = now ?? DateTime.now();
    final elapsed = stoppedAt.difference(current.startedAt!);
    notifier.value = LocalResponseTimerSnapshot(
      startedAt: current.startedAt,
      elapsed: elapsed.isNegative ? Duration.zero : elapsed,
    );
  }

  /// Stops and hides a timer when generation ends before any model response.
  static void cancel(String messageId) {
    final notifier = _notifiers[messageId];
    if (notifier == null || !notifier.value.running) return;
    notifier.value = const LocalResponseTimerSnapshot();
  }

  @visibleForTesting
  static void debugReset() {
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
  }

  static ValueNotifier<LocalResponseTimerSnapshot> _notifier(
    String messageId,
  ) {
    return _notifiers.putIfAbsent(
      messageId,
      () => ValueNotifier<LocalResponseTimerSnapshot>(
        const LocalResponseTimerSnapshot(),
      ),
    );
  }
}
