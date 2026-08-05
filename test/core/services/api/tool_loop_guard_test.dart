import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tin/core/services/api/tool_loop_guard.dart';

Map<String, dynamic> _decodeRefusal(String raw) {
  return (jsonDecode(raw) as Map).cast<String, dynamic>();
}

void main() {
  group('ToolLoopGuard budgets', () {
    test('allows calls up to the soft budget', () {
      final guard = ToolLoopGuard();
      // Vary arguments so duplicate detection never fires.
      for (var i = 0; i < ToolLoopGuard.softCallBudget; i++) {
        expect(
          guard.evaluate('search_web', {'q': 'query $i'}),
          isNull,
          reason: 'call ${i + 1} should be allowed',
        );
      }
      expect(guard.callCount, ToolLoopGuard.softCallBudget);
    });

    test('refuses past the soft budget without throwing', () {
      final guard = ToolLoopGuard();
      for (var i = 0; i < ToolLoopGuard.softCallBudget; i++) {
        guard.evaluate('search_web', {'q': 'query $i'});
      }

      final refusal = guard.evaluate('search_web', {'q': 'one more'});
      expect(refusal, isNotNull);

      final payload = _decodeRefusal(refusal!);
      expect(payload['reason'], 'tool_budget_exhausted');
      expect(payload['retry'], isFalse);
      expect(payload['tool_error'], contains('limit'));

      // Refused calls must not consume execution budget, but they are still
      // counted as attempts so the hard budget stays reachable.
      expect(guard.callCount, ToolLoopGuard.softCallBudget);
      expect(guard.attemptCount, ToolLoopGuard.softCallBudget + 1);
    });

    test('throws once the hard budget is reached', () {
      final guard = ToolLoopGuard();
      // Keep issuing distinct calls; soft refusals are ignored on purpose to
      // simulate a model that will not stop.
      for (var i = 0; i < ToolLoopGuard.hardCallBudget; i++) {
        guard.evaluate('search_web', {'q': 'query $i'});
      }
      expect(guard.attemptCount, ToolLoopGuard.hardCallBudget);

      expect(
        () => guard.evaluate('search_web', {'q': 'final'}),
        throwsA(isA<ToolLoopBudgetExceeded>()),
      );
    });

    test('hard budget counts refusals so it is always reachable', () {
      final guard = ToolLoopGuard();
      var thrown = false;
      // A model that ignores every refusal must still be cut off.
      for (var i = 0; i < ToolLoopGuard.hardCallBudget * 2; i++) {
        try {
          guard.evaluate('search_web', {'q': 'query $i'});
        } on ToolLoopBudgetExceeded {
          thrown = true;
          break;
        }
      }
      expect(thrown, isTrue);
    });

    test('hard budget is never reached before the soft budget refuses', () {
      expect(
        ToolLoopGuard.softCallBudget,
        lessThan(ToolLoopGuard.hardCallBudget),
      );
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

    test('fires well before the soft budget', () {
      final guard = ToolLoopGuard();
      final args = {'path': 'notes.txt'};
      String? refusal;
      var attempts = 0;
      while (refusal == null && attempts < ToolLoopGuard.softCallBudget) {
        refusal = guard.evaluate('read_file', args);
        attempts++;
      }
      expect(refusal, isNotNull);
      expect(attempts, lessThan(ToolLoopGuard.softCallBudget));
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
    test('reports the attempt count', () {
      const err = ToolLoopBudgetExceeded(ToolLoopGuard.hardCallBudget);
      expect(err.attemptCount, ToolLoopGuard.hardCallBudget);
      expect(err.toString(), contains('${ToolLoopGuard.hardCallBudget}'));
    });
  });
}