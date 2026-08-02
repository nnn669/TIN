import 'dart:async';

/// Coalesces rapidly changing snapshots while keeping writes serialized.
///
/// [schedule] only queues the latest snapshot and returns immediately, so a
/// streaming response is never paused on storage latency. [flush] is used by
/// terminal paths to wait until the latest queued snapshot is durable.
class StreamingMessagePersistence<T> {
  final Map<String, _PendingWrite<T>> _writes = <String, _PendingWrite<T>>{};

  void schedule(
    String key,
    T snapshot,
    Future<void> Function(T snapshot) persist,
  ) {
    final write = _writes.putIfAbsent(key, _PendingWrite<T>.new);
    write
      ..latest = snapshot
      ..persist = persist
      ..error = null
      ..stackTrace = null;
    _startIfNeeded(write);
  }

  Future<void> flush(String key) async {
    final write = _writes[key];
    if (write == null) return;

    while (write.running != null) {
      await write.running;
    }

    final error = write.error;
    final stackTrace = write.stackTrace;
    if (error != null) {
      Error.throwWithStackTrace(error, stackTrace ?? StackTrace.current);
    }

    if (write.latest == null) {
      _writes.remove(key);
    }
  }

  Future<void> flushAll() async {
    for (final key in List<String>.of(_writes.keys)) {
      await flush(key);
    }
  }

  void _startIfNeeded(_PendingWrite<T> write) {
    if (write.running != null) return;
    final running = _drain(write);
    write.running = running;
    unawaited(running);
  }

  Future<void> _drain(_PendingWrite<T> write) async {
    try {
      while (write.latest != null) {
        final snapshot = write.latest as T;
        write.latest = null;
        await write.persist!(snapshot);
      }
    } catch (error, stackTrace) {
      write.error = error;
      write.stackTrace = stackTrace;
    } finally {
      write.running = null;
      if (write.latest != null && write.error == null) {
        _startIfNeeded(write);
      }
    }
  }
}

class _PendingWrite<T> {
  T? latest;
  Future<void> Function(T snapshot)? persist;
  Future<void>? running;
  Object? error;
  StackTrace? stackTrace;
}