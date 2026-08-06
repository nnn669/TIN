import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tin/core/services/api/tool_loop_guard.dart';

Map<String, dynamic> _decodeRefusal(String raw) {
  return (jsonDecode(raw) as Map).cast<String, dynamic>();
}

void main() {
  group('ToolLoopGuard budget', () {
    test('allows exactly 100 tool calls in one assistant response', () {
      final guard = ToolLoopGuard();
      // Vary arguments so duplicate detection never fires.
      for (var i = 0; i < ToolLoopGuard.maxCallBudget; i++) {
        expect(
          guard.evaluate('search_web', {'q': 'query $i'}),
          isNull,
          reason: 'call ${i + 1} should be allowed',
        );
      }
      expect(guard.callCount, ToolLoopGuard.maxCallBudget);
    });

    test('throws on the 101st tool call', () {
      final guard = ToolLoopGuard();
      for (var i = 0; i < ToolLoopGuard.maxCallBudget; i++) {
        guard.evaluate('search_web', {'q': 'query $i'});
      }

      expect(
        () => guard.evaluate('search_web', {'q': 'call 101'}),
        throwsA(isA<ToolLoopBudgetExceeded>()),
      );
      expect(guard.callCount, ToolLoopGuard.maxCallBudget);
    });

    test('cache hits count toward the 100-call response limit', () {
      final guard = ToolLoopGuard();
      for (var i = 0; i < ToolLoopGuard.maxCallBudget; i++) {
        expect(
          guard.evaluate('fetch_txt', const {'url': 'https://example.com'}, cached: true),
          isNull,
        );
      }

      expect(
        () => guard.evaluate(
          'fetch_txt',
          const {'url': 'https://example.com'},
          cached: true,
        ),
        throwsA(isA<ToolLoopBudgetExceeded>()),
      );
    });

    test('a new guard starts a fresh 100-call response budget', () {
      final firstResponse = ToolLoopGuard();
      for (var i = 0; i < ToolLoopGuard.maxCallBudget; i++) {
        firstResponse.evaluate('search_web', {'q': 'first $i'});
      }

      final nextResponse = ToolLoopGuard();
      expect(nextResponse.callCount, 0);
      expect(nextResponse.evaluate('search_web', const {'q': 'next'}), isNull);
      expect(nextResponse.callCount, 1);
    });
  });

  group('ToolLoopGuard duplicate detection', () {
    test('refuses identical consecutive calls', () {
      final guard = ToolLoopGuard();
      final args = {'path': 'notes.txt'};

      for (var i = 0; i < ToolLoopGuard.maxConsecutiveDupes - 1; i++) {
        expect(guard.evaluate('read_file', args), isNull);
      }

      final refusal = guard.evaluate('read_file', args);
      expect(refusal, isNotNull);
      expect(_decodeRefusal(refusal!)['reason'], 'repeated_tool_calls');
    });

    test('a different call resets the duplicate streak', () {
      final guard = ToolLoopGuard();
      final args = {'path': 'notes.txt'};

      expect(guard.evaluate('read_file', args), isNull);
      expect(guard.evaluate('read_file', args), isNull);
      // Break the streak.
      expect(guard.evaluate('list_files', {'path': '.'}), isNull);
      // The streak restarted, so this repeat is allowed again.
      expect(guard.evaluate('read_file', args), isNull);
    });

    test('different arguments are not duplicates', () {
      final guard = ToolLoopGuard();
      for (var i = 0; i < ToolLoopGuard.maxConsecutiveDupes + 2; i++) {
        expect(guard.evaluate('read_file', {'path': 'file$i.txt'}), isNull);
      }
    });

    test('different tool names are not duplicates', () {
      final guard = ToolLoopGuard();
      final args = {'q': 'same'};
      expect(guard.evaluate('search_web', args), isNull);
      expect(guard.evaluate('fetch_page', args), isNull);
      expect(guard.evaluate('search_web', args), isNull);
    });
  });

  group('ToolLoopGuard signature stability', () {
    test('key order does not change the signature', () {
      final a = ToolLoopGuard.signatureOf('t', {'a': 1, 'b': 2});
      final b = ToolLoopGuard.signatureOf('t', {'b': 2, 'a': 1});
      expect(a, b);
    });

    test('nested key order does not change the signature', () {
      final a = ToolLoopGuard.signatureOf('t', {
        'outer': {'x': 1, 'y': 2},
      });
      final b = ToolLoopGuard.signatureOf('t', {
        'outer': {'y': 2, 'x': 1},
      });
      expect(a, b);
    });

    test('list order does change the signature', () {
      final a = ToolLoopGuard.signatureOf('t', {
        'items': [1, 2],
      });
      final b = ToolLoopGuard.signatureOf('t', {
        'items': [2, 1],
      });
      expect(a, isNot(b));
    });

    test('unstable key order still detects duplicates', () {
      final guard = ToolLoopGuard();
      expect(guard.evaluate('t', {'a': 1, 'b': 2}), isNull);
      expect(guard.evaluate('t', {'b': 2, 'a': 1}), isNull);
      final refusal = guard.evaluate('t', {'a': 1, 'b': 2});
      expect(refusal, isNotNull);
      expect(_decodeRefusal(refusal!)['reason'], 'repeated_tool_calls');
    });

    test('empty arguments are handled', () {
      final guard = ToolLoopGuard();
      expect(guard.evaluate('ping', const <String, dynamic>{}), isNull);
      expect(guard.evaluate('ping', const <String, dynamic>{}), isNull);
      expect(guard.evaluate('ping', const <String, dynamic>{}), isNotNull);
    });

    test('null values inside arguments are handled', () {
      final guard = ToolLoopGuard();
      expect(guard.evaluate('t', {'a': null}), isNull);
      expect(guard.evaluate('t', {'a': null}), isNull);
      expect(guard.evaluate('t', {'a': null}), isNotNull);
    });
  });

  group('ToolCallResultCache', () {
    test('reuses an in-flight and completed successful result', () async {
      final cache = ToolCallResultCache();
      var executions = 0;

      final first = cache.run('fetch_txt', {'url': 'https://example.com/a'}, () async {
        executions++;
        await Future<void>.delayed(Duration.zero);
        return 'page A';
      });
      final second = cache.run('fetch_txt', {'url': 'https://example.com/a'}, () async {
        executions++;
        return 'unexpected duplicate';
      });

      expect(identical(first, second), isTrue);
      expect(await first, 'page A');
      expect(
        await cache.run('fetch_txt', {'url': 'https://example.com/a'}, () async {
          executions++;
          return 'unexpected second duplicate';
        }),
        'page A',
      );
      expect(executions, 1);
    });

    test('keeps different parameters independent for split calls', () async {
      final cache = ToolCallResultCache();
      var executions = 0;

      final a = cache.run('fetch_txt', {'url': 'https://example.com/a'}, () async {
        executions++;
        return 'page A';
      });
      final b = cache.run('fetch_txt', {'url': 'https://example.com/b'}, () async {
        executions++;
        return 'page B';
      });

      expect(await a, 'page A');
      expect(await b, 'page B');
      expect(executions, 2);
    });

    test('does not cache structured tool errors and allows retry', () async {
      final cache = ToolCallResultCache();
      var executions = 0;
      final args = {'url': 'https://example.com/retry'};

      final failed = await cache.run('fetch_txt', args, () async {
        executions++;
        return jsonEncode({'type': 'tool_error', 'error': 'network'});
      });
      final retried = await cache.run('fetch_txt', args, () async {
        executions++;
        return 'recovered';
      });

      expect(jsonDecode(failed), isA<Map>());
      expect(retried, 'recovered');
      expect(executions, 2);
    });

    test('cached split calls do not trigger duplicate refusal', () async {
      final cache = ToolCallResultCache();
      final guard = ToolLoopGuard();
      final argsA = {'url': 'https://example.com/a'};
      final argsB = {'url': 'https://example.com/b'};

      Future<String> call(String name, Map<String, dynamic> args) async {
        final cached = cache.lookup(name, args);
        expect(guard.evaluate(name, args, cached: cached != null), isNull);
        if (cached != null) return cached;
        return cache.run(name, args, () async => 'ok:$name:${args['url']}');
      }

      expect(await call('fetch_txt', argsA), 'ok:fetch_txt:https://example.com/a');
      expect(await call('fetch_txt', argsB), 'ok:fetch_txt:https://example.com/b');
      expect(await call('fetch_txt', argsA), 'ok:fetch_txt:https://example.com/a');
      expect(await call('fetch_txt', argsA), 'ok:fetch_txt:https://example.com/a');
    });
  });

  group('ToolLoopBudgetExceeded', () {
    test('reports the call count', () {
      const err = ToolLoopBudgetExceeded(ToolLoopGuard.maxCallBudget);
      expect(err.callCount, ToolLoopGuard.maxCallBudget);
      expect(err.toString(), contains('${ToolLoopGuard.maxCallBudget}'));
    });
  });
}