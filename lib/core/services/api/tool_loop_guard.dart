import 'dart:convert';

/// Soft budget: after this many tool calls in a single assistant turn, further
/// calls are refused with an instruction to answer using what has been gathered.
///
/// Every provider re-sends the whole conversation plus all prior tool results on
/// each follow-up request, so an unbounded tool loop makes token cost grow
/// quadratically with the round count. Normal multi-step tool tasks finish well
/// under ten calls; this leaves headroom while bounding a runaway loop.
const int kToolCallSoftBudget = 24;

/// Hard ceiling: exceeding this aborts the turn outright.
///
/// Only reachable when the model ignores the soft-budget refusals, which means
/// it is stuck rather than making progress.
const int kToolCallHardBudget = 32;

/// Consecutive identical calls (same name and arguments) treated as a loop.
const int kMaxConsecutiveDuplicateToolCalls = 3;

/// Thrown when a single assistant turn blows past the hard tool-call budget.
///
/// Propagates out of the provider's `await onToolCall(...)`, which terminates
/// the response stream. This is the last-resort hard stop; the soft budget is
/// expected to end the loop first.
class ToolCallBudgetExceededException implements Exception {
  const ToolCallBudgetExceededException(this.callCount, this.hardBudget);

  /// Tool calls attempted in this turn, including the one that was rejected.
  final int callCount;

  /// The ceiling that was exceeded.
  final int hardBudget;

  @override
  String toString() =>
      'ToolCallBudgetExceededException: the model attempted $callCount tool '
      'calls in a single turn (hard limit $hardBudget). The turn was aborted to '
      'avoid unbounded token cost.';
}

/// Bounds tool calls within one assistant turn.
///
/// Providers drive tool calls with an unbounded `while` loop that only exits
/// when the model stops requesting tools, so a model that keeps requesting
/// tools would bill every round until the user hits stop. Wrapping the shared
/// tool-call handler with this guard bounds every provider at once, including
/// the non-streaming paths, because the handler is the only way a provider can
/// reach its next round.
///
/// One instance belongs to one assistant turn; do not share across turns.
class ToolLoopGuard {
  ToolLoopGuard({
    this.softBudget = kToolCallSoftBudget,
    this.hardBudget = kToolCallHardBudget,
    this.maxConsecutiveDuplicates = kMaxConsecutiveDuplicateToolCalls,
  }) : assert(softBudget > 0),
       assert(hardBudget >= softBudget),
       assert(maxConsecutiveDuplicates > 0);

  /// Calls allowed before refusals start.
  final int softBudget;

  /// Calls allowed before the turn is aborted.
  final int hardBudget;

  /// Consecutive identical calls tolerated before refusing.
  final int maxConsecutiveDuplicates;

  int _callCount = 0;
  String? _lastSignature;
  int _duplicateStreak = 0;

  /// Tool calls seen so far in this turn.
  int get callCount => _callCount;

  /// Whether the soft budget has been used up.
  bool get softBudgetExhausted => _callCount > softBudget;

  /// Builds a stable signature for one call, used to detect repeats.
  ///
  /// Keys are sorted so that argument maps built in a different order still
  /// compare equal. Falls back to `toString` when the arguments are not
  /// JSON-encodable, so signature building never throws mid-stream.
  static String signatureFor(String name, Map<String, dynamic>? arguments) {
    var encoded = '';
    if (arguments != null && arguments.isNotEmpty) {
      try {
        final keys = arguments.keys.toList()..sort();
        encoded = jsonEncode(<String, dynamic>{
          for (final k in keys) k: arguments[k],
        });
      } catch (_) {
        encoded = arguments.toString();
      }
    }
    return '$name:$encoded';
  }

  /// Records a call and reports how it should be handled.
  ///
  /// Throws [ToolCallBudgetExceededException] once [hardBudget] is passed.
  ToolLoopDecision register(String name, Map<String, dynamic>? arguments) {
    _callCount++;

    if (_callCount > hardBudget) {
      throw ToolCallBudgetExceededException(_callCount, hardBudget);
    }

    final signature = signatureFor(name, arguments);
    if (signature == _lastSignature) {
      _duplicateStreak++;
    } else {
      _lastSignature = signature;
      _duplicateStreak = 1;
    }

    if (_callCount > softBudget) {
      return ToolLoopDecision.refuse(
        reason: 'tool_call_budget_exhausted',
        message:
            'Tool call budget for this turn is exhausted after $softBudget '
            'calls.',
        instruction:
            'Do not call any more tools. Answer the user now using the '
            'information already gathered, and say plainly which parts you '
            'could not verify.',
      );
    }

    if (_duplicateStreak >= maxConsecutiveDuplicates) {
      return ToolLoopDecision.refuse(
        reason: 'duplicate_tool_call',
        message:
            'The tool "$name" was called $_duplicateStreak times in a row with '
            'identical arguments.',
        instruction:
            'Repeating this call will keep returning the same result. Either '
            'call it with different arguments, use a different tool, or answer '
            'the user with what you already have.',
      );
    }

    return const ToolLoopDecision.allow();
  }
}

/// Outcome of [ToolLoopGuard.register].
class ToolLoopDecision {
  const ToolLoopDecision.allow()
    : allowed = true,
      reason = '',
      message = '',
      instruction = '';

  const ToolLoopDecision.refuse({
    required this.reason,
    required this.message,
    required this.instruction,
  }) : allowed = false;

  /// Whether the underlying tool should actually run.
  final bool allowed;

  /// Machine-readable refusal code; empty when allowed.
  final String reason;

  /// Human-readable refusal detail; empty when allowed.
  final String message;

  /// What the model should do instead; empty when allowed.
  final String instruction;

  /// Serializes the refusal in the same shape as other tool errors, so the
  /// model sees a familiar payload.
  String toToolErrorJson(String toolName) {
    return jsonEncode({
      'type': 'tool_error',
      'error': reason,
      'message': message,
      'tool': toolName,
      'instruction': instruction,
    });
  }
}
