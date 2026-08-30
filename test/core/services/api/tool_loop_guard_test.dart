import 'package:flutter_test/flutter_test.dart';
import 'package:tin/core/services/api/tool_loop_guard.dart';

void main() {
  group('ToolLoopGuard unlimited calls', () {
    test('allows far more than the former 100-call budget', () {
      final guard = ToolLoopGuard();
      // Vary arguments; identical consecutive calls are also allowed.
      for (var i = 0; i < 150; i++) {
        expect(
          guard.evaluate('search_web', {'q': 'query $i'}),
          isNull,
          reason: 'call ${i + 1} should be allowed',
        );
      }
      expect(guard.callCount, 150);
    });

    test('cache hits also count toward the per-response counter', () {
      final guard = ToolLoopGuard();
      for (var i = 0; i < 120; i++) {
        expect(
          guard.evaluate('fetch_txt', const {
            'url': 'https://example.com',
          }, cached: true),
          isNull,
        );
      }
      expect(guard.callCount, 120);
    });

    test('a new guard starts a fresh per-response counter', () {
      final firstResponse = ToolLoopGuard();
      for (var i = 0; i < 50; i++) {
        firstResponse.evaluate('search_web', {'q': 'first $i'});
      }
      final nextResponse = ToolLoopGuard();
      expect(nextResponse.callCount, 0);
      expect(nextResponse.evaluate('search_web', const {'q': 'next'}), isNull);
      expect(nextResponse.callCount, 1);
    });
  });

  group('ToolLoopGuard unlimited duplicates', () {
    test('allows identical consecutive calls indefinitely', () {
      final guard = ToolLoopGuard();
      final args = {'path': 'notes.txt'};
      for (var i = 0; i < 10; i++) {
        expect(guard.evaluate('read_file', args), isNull);
      }
    });

    test('allows different arguments and tools without interference', () {
      final guard = ToolLoopGuard();
      for (var i = 0; i < 6; i++) {
        expect(guard.evaluate('read_file', {'path': 'file$i.txt'}), isNull);
      }
      expect(guard.evaluate('search_web', const {'q': 'same'}), isNull);
      expect(guard.evaluate('read_file', const {'path': 'notes.txt'}), isNull);
    });

    test('unstable key order does not restrict identical calls', () {
      final guard = ToolLoopGuard();
      expect(guard.evaluate('t', const {'a': 1, 'b': 2}), isNull);
      expect(guard.evaluate('t', const {'b': 2, 'a': 1}), isNull);
      expect(guard.evaluate('t', const {'a': 1, 'b': 2}), isNull);
    });

    test('empty arguments are handled', () {
      final guard = ToolLoopGuard();
      expect(guard.evaluate('ping', const {}), isNull);
      expect(guard.evaluate('ping', const {}), isNull);
      expect(guard.evaluate('ping', const {}), isNull);
    });

    test('null values inside arguments are handled', () {
      final guard = ToolLoopGuard();
      expect(guard.evaluate('t', const {'a': null}), isNull);
      expect(guard.evaluate('t', const {'a': null}), isNull);
      expect(guard.evaluate('t', const {'a': null}), isNull);
    });
  });

  group('ToolLoopGuard signature stability', () {
    test('key order does not change the signature', () {
      final a = ToolLoopGuard.signatureOf('t', const {'a': 1, 'b': 2});
      final b = ToolLoopGuard.signatureOf('t', const {'b': 2, 'a': 1});
      expect(a, b);
    });

    test('nested key order does not change the signature', () {
      final a = ToolLoopGuard.signatureOf('t', const {
        'outer': {'x': 1, 'y': 2},
      });
      final b = ToolLoopGuard.signatureOf('t', const {
        'outer': {'y': 2, 'x': 1},
      });
      expect(a, b);
    });

    test('list order does change the signature', () {
      final a = ToolLoopGuard.signatureOf('t', const {
        'items': [1, 2],
      });
      final b = ToolLoopGuard.signatureOf('t', const {
        'items': [2, 1],
      });
      expect(a, isNot(b));
    });
  });

  group('ToolCallResultCache', () {
    test('reuses an in-flight and completed successful result', () async {
      final cache = ToolCallResultCache();
      var executions = 0;
      final first = cache.run(
        'fetch_txt',
        const {'url': 'https://example.com/a'},
        () async {
          executions++;
          await Future<void>.delayed(Duration.zero);
          return 'page A';
        },
      );
      final second = cache.run(
        'fetch_txt',
        const {'url': 'https://example.com/a'},
        () async {
          executions++;
          return 'unexpected duplicate';
        },
      );
      expect(identical(first, second), isTrue);
      expect(await first, 'page A');
      expect(
        await cache.run(
          'fetch_txt',
          const {'url': 'https://example.com/a'},
          () async {
            executions++;
            return 'unexpected second duplicate';
          },
        ),
        'page A',
      );
      expect(executions, 1);
    });

    test('keeps different parameters independent for split calls', () async {
      final cache = ToolCallResultCache();
      var executions = 0;
      final a = cache.run(
        'fetch_txt',
        const {'url': 'https://example.com/a'},
        () async {
          executions++;
          return 'page A';
        },
      );
      final b = cache.run(
        'fetch_txt',
        const {'url': 'https://example.com/b'},
        () async {
          executions++;
          return 'page B';
        },
      );
      expect(await a, 'page A');
      expect(await b, 'page B');
      expect(executions, 2);
    });

    test('does not cache structured tool errors and allows retry', () async {
      final cache = ToolCallResultCache();
      var executions = 0;
      const args = {'url': 'https://example.com/retry'};
      final failed = await cache.run('fetch_txt', args, () async {
        executions++;
        return '{"type":"tool_error","error":"network"}';
      });
      final retried = await cache.run('fetch_txt', args, () async {
        executions++;
        return 'recovered';
      });
      expect(failed, contains('tool_error'));
      expect(retried, 'recovered');
      expect(executions, 2);
    });

    test('cached split calls are always allowed', () async {
      final cache = ToolCallResultCache();
      final guard = ToolLoopGuard();
      const argsA = {'url': 'https://example.com/a'};
      const argsB = {'url': 'https://example.com/b'};
      Future<String> call(String name, Map<String, dynamic> args) async {
        final cached = cache.lookup(name, args);
        expect(guard.evaluate(name, args, cached: cached != null), isNull);
        if (cached != null) return cached;
        return cache.run(name, args, () async => 'ok:$name:${args['url']}');
      }

      expect(
        await call('fetch_txt', argsA),
        'ok:fetch_txt:https://example.com/a',
      );
      expect(
        await call('fetch_txt', argsB),
        'ok:fetch_txt:https://example.com/b',
      );
      expect(
        await call('fetch_txt', argsA),
        'ok:fetch_txt:https://example.com/a',
      );
      expect(
        await call('fetch_txt', argsA),
        'ok:fetch_txt:https://example.com/a',
      );
    });
  });
}
