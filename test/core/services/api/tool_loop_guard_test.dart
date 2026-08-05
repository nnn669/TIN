import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tin/core/services/api/chat_api_service.dart';
import 'package:tin/core/services/api/tool_loop_guard.dart';
import 'package:tin/features/home/controllers/generation_controller.dart';

void main() {
  group('ToolLoopGuard.signatureFor', () {
    test('is stable regardless of argument insertion order', () {
      final a = ToolLoopGuard.signatureFor('search', {'q': 'x', 'page': 1});
      final b = ToolLoopGuard.signatureFor('search', {'page': 1, 'q': 'x'});
      expect(a, b);
    });

    test('distinguishes different tool names and arguments', () {
      final base = ToolLoopGuard.signatureFor('search', {'q': 'x'});
      expect(base, isNot(ToolLoopGuard.signatureFor('fetch', {'q': 'x'})));
      expect(base, isNot(ToolLoopGuard.signatureFor('search', {'q': 'y'})));
    });

    test('does not throw on non-encodable arguments', () {
      expect(
        () => ToolLoopGuard.signatureFor('t', {'bad': Object()}),
        returnsNormally,
      );
    });

    test('treats null and empty arguments alike', () {
      expect(
        ToolLoopGuard.signatureFor('t', null),
        ToolLoopGuard.signatureFor('t', const <String, dynamic>{}),
      );
    });
  });

  group('ToolLoopGuard duplicate detection', () {
    test('refuses after the configured consecutive identical calls', () {
      final guard = ToolLoopGuard(maxConsecutiveDuplicates: 3);
      expect(guard.register('search', {'q': 'x'}).allowed, isTrue);
      expect(guard.register('search', {'q': 'x'}).allowed, isTrue);

      final third = guard.register('search', {'q': 'x'});
      expect(third.allowed, isFalse);
      expect(third.reason, 'duplicate_tool_call');
      expect(third.instruction, isNotEmpty);
    });

    test('a differing call resets the duplicate streak', () {
      final guard = ToolLoopGuard(maxConsecutiveDuplicates: 3);
      guard.register('search', {'q': 'x'});
      guard.register('search', {'q': 'x'});
      expect(guard.register('search', {'q': 'y'}).allowed, isTrue);
      // Streak restarted, so the same call is allowed twice again.
      expect(guard.register('search', {'q': 'x'}).allowed, isTrue);
      expect(guard.register('search', {'q': 'x'}).allowed, isTrue);
      expect(guard.register('search', {'q': 'x'}).allowed, isFalse);
    });

    test('alternating calls never trip the duplicate limit', () {
      final guard = ToolLoopGuard(maxConsecutiveDuplicates: 3);
      for (var i = 0; i < 8; i++) {
        final decision = guard.register('search', {'q': i.isEven ? 'a' : 'b'});
        expect(decision.allowed, isTrue);
      }
    });

    test('same name with different arguments is not a duplicate', () {
      final guard = ToolLoopGuard(maxConsecutiveDuplicates: 2);
      expect(guard.register('search', {'q': 'a'}).allowed, isTrue);
      expect(guard.register('search', {'q': 'b'}).allowed, isTrue);
      expect(guard.register('search', {'q': 'c'}).allowed, isTrue);
    });
  });

  group('ToolLoopGuard budgets', () {
    test('allows exactly softBudget calls before refusing', () {
      // maxConsecutiveDuplicates is raised so only the budget can trip.
      final guard = ToolLoopGuard(
        softBudget: 4,
        hardBudget: 8,
        maxConsecutiveDuplicates: 1000,
      );
      for (var i = 0; i < 4; i++) {
        expect(
          guard.register('t', {'i': i}).allowed,
          isTrue,
          reason: 'call $i',
        );
      }
      expect(guard.softBudgetExhausted, isFalse);

      final refused = guard.register('t', {'i': 4});
      expect(refused.allowed, isFalse);
      expect(refused.reason, 'tool_call_budget_exhausted');
      expect(guard.softBudgetExhausted, isTrue);
      expect(guard.callCount, 5);
    });

    test('budget refusal takes precedence over duplicate refusal', () {
      final guard = ToolLoopGuard(
        softBudget: 1,
        hardBudget: 8,
        maxConsecutiveDuplicates: 2,
      );
      expect(guard.register('t', {'q': 'x'}).allowed, isTrue);
      // Both limits are now due; the budget reason must win.
      expect(
        guard.register('t', {'q': 'x'}).reason,
        'tool_call_budget_exhausted',
      );
    });

    test('throws once the hard budget is exceeded', () {
      final guard = ToolLoopGuard(
        softBudget: 2,
        hardBudget: 3,
        maxConsecutiveDuplicates: 1000,
      );
      guard.register('t', {'i': 0});
      guard.register('t', {'i': 1});
      guard.register('t', {'i': 2});
      expect(
        () => guard.register('t', {'i': 3}),
        throwsA(isA<ToolCallBudgetExceededException>()),
      );
    });

    test('hard budget exception reports the count and limit', () {
      final guard = ToolLoopGuard(
        softBudget: 1,
        hardBudget: 1,
        maxConsecutiveDuplicates: 1000,
      );
      guard.register('t', {'i': 0});
      try {
        guard.register('t', {'i': 1});
        fail('expected ToolCallBudgetExceededException');
      } on ToolCallBudgetExceededException catch (e) {
        expect(e.callCount, 2);
        expect(e.hardBudget, 1);
        expect(e.toString(), contains('2'));
      }
    });

    test('defaults keep the soft budget below the hard budget', () {
      final guard = ToolLoopGuard();
      expect(guard.softBudget, kToolCallSoftBudget);
      expect(guard.hardBudget, kToolCallHardBudget);
      expect(guard.softBudget, lessThanOrEqualTo(guard.hardBudget));
    });
  });

  group('ToolLoopDecision.toToolErrorJson', () {
    test('matches the shared tool_error payload shape', () {
      const decision = ToolLoopDecision.refuse(
        reason: 'duplicate_tool_call',
        message: 'called twice',
        instruction: 'stop',
      );
      final payload =
          jsonDecode(decision.toToolErrorJson('search'))
              as Map<String, dynamic>;
      expect(payload['type'], 'tool_error');
      expect(payload['error'], 'duplicate_tool_call');
      expect(payload['tool'], 'search');
      expect(payload['message'], 'called twice');
      expect(payload['instruction'], 'stop');
    });
  });

  group('GenerationController.guardToolCallHandler', () {
    test('forwards allowed calls untouched, including toolCallId', () async {
      final seen = <String>[];
      String? seenId;
      final handler = GenerationController.guardToolCallHandler((
        name,
        args, {
        toolCallId,
      }) async {
        seen.add(name);
        seenId = toolCallId;
        return 'ok:$name';
      });

      final result = await handler('search', {'q': 'x'}, toolCallId: 'call_1');
      expect(result, 'ok:search');
      expect(seen, ['search']);
      expect(seenId, 'call_1');
    });

    test('stops invoking the inner handler once refused', () async {
      var calls = 0;
      final handler = GenerationController.guardToolCallHandler(
        (name, args, {toolCallId}) async {
          calls++;
          return 'result';
        },
        guard: ToolLoopGuard(maxConsecutiveDuplicates: 2),
      );

      expect(await handler('search', {'q': 'x'}), 'result');
      final refused = await handler('search', {'q': 'x'});

      expect(calls, 1, reason: 'inner handler must not run when refused');
      final payload = jsonDecode(refused) as Map<String, dynamic>;
      expect(payload['type'], 'tool_error');
      expect(payload['error'], 'duplicate_tool_call');
      expect(payload['tool'], 'search');
    });

    test(
      'returns a refusal payload instead of throwing at the soft budget',
      () async {
        final handler = GenerationController.guardToolCallHandler(
          (name, args, {toolCallId}) async => 'result',
          guard: ToolLoopGuard(
            softBudget: 1,
            hardBudget: 99,
            maxConsecutiveDuplicates: 1000,
          ),
        );

        expect(await handler('t', {'i': 0}), 'result');
        final refused = await handler('t', {'i': 1});
        final payload = jsonDecode(refused) as Map<String, dynamic>;
        expect(payload['error'], 'tool_call_budget_exhausted');
      },
    );

    test('propagates the hard-budget exception to abort the turn', () async {
      final handler = GenerationController.guardToolCallHandler(
        (name, args, {toolCallId}) async => 'result',
        guard: ToolLoopGuard(
          softBudget: 1,
          hardBudget: 1,
          maxConsecutiveDuplicates: 1000,
        ),
      );

      await handler('t', {'i': 0});
      expect(
        () => handler('t', {'i': 1}),
        throwsA(isA<ToolCallBudgetExceededException>()),
      );
    });

    test('each wrapped handler gets an independent budget', () async {
      ToolCallHandler build() => GenerationController.guardToolCallHandler(
        (name, args, {toolCallId}) async => 'result',
        guard: ToolLoopGuard(maxConsecutiveDuplicates: 2),
      );

      final first = build();
      expect(await first('t', {'q': 'x'}), 'result');
      expect(
        (jsonDecode(await first('t', {'q': 'x'})) as Map)['error'],
        'duplicate_tool_call',
      );

      // A fresh turn starts with a clean slate.
      final second = build();
      expect(await second('t', {'q': 'x'}), 'result');
    });
  });
}
