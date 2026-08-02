import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tin/core/services/chat/streaming_message_persistence.dart';

void main() {
  group('StreamingMessagePersistence', () {
    test('schedule does not wait for storage and coalesces queued snapshots', () async {
      final persistence = StreamingMessagePersistence<String>();
      final firstWriteStarted = Completer<void>();
      final allowFirstWrite = Completer<void>();
      final written = <String>[];

      Future<void> persist(String snapshot) async {
        written.add(snapshot);
        if (snapshot == 'first') {
          firstWriteStarted.complete();
          await allowFirstWrite.future;
        }
      }

      persistence.schedule('message', 'first', persist);
      await firstWriteStarted.future;

      persistence.schedule('message', 'second', persist);
      persistence.schedule('message', 'latest', persist);
      await Future<void>.delayed(Duration.zero);

      expect(written, const ['first']);

      allowFirstWrite.complete();
      await persistence.flush('message');

      expect(written, const ['first', 'latest']);
    });

    test('flush waits for the latest queued snapshot', () async {
      final persistence = StreamingMessagePersistence<int>();
      final allowWrite = Completer<void>();
      var flushed = false;

      persistence.schedule('message', 1, (_) => allowWrite.future);
      final flush = persistence.flush('message').then((_) => flushed = true);
      await Future<void>.delayed(Duration.zero);

      expect(flushed, isFalse);

      allowWrite.complete();
      await flush;
      expect(flushed, isTrue);
    });

    test('flush surfaces a background persistence failure', () async {
      final persistence = StreamingMessagePersistence<String>();

      persistence.schedule(
        'message',
        'snapshot',
        (_) async => throw StateError('write failed'),
      );

      await expectLater(
        persistence.flush('message'),
        throwsA(isA<StateError>()),
      );
    });

    test('a newer snapshot retries after a failed background write', () async {
      final persistence = StreamingMessagePersistence<String>();
      var fail = true;
      final written = <String>[];

      Future<void> persist(String snapshot) async {
        if (fail) throw StateError('write failed');
        written.add(snapshot);
      }

      persistence.schedule('message', 'failed', persist);
      await expectLater(
        persistence.flush('message'),
        throwsA(isA<StateError>()),
      );

      fail = false;
      persistence.schedule('message', 'recovered', persist);
      await persistence.flush('message');

      expect(written, const ['recovered']);
    });
  });
}