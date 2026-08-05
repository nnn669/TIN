import 'dart:convert';

/// Thrown when an assistant turn blows past the hard tool-call budget.
///
/// Reaching this point means the model kept requesting tools even after the
/// soft refusals below told it to stop, so the turn is aborted outright rather
/// than billed for another round.
class ToolLoopBudgetExceeded implements Exception {
  const ToolLoopBudgetExceeded(this.attemptCount);

  /// Total tool requests seen this turn, including refused ones.
  final int attemptCount;

  @override
  String toString() =>
      'ToolLoopBudgetExceeded: tool loop aborted after $attemptCount requests';
}

/// Reuses an in-flight or completed successful result for an identical call.
///
/// The key includes the tool name and the complete recursively normalized
/// argument map. Different URLs, pages, headers, or split subtasks therefore
/// remain independent. Results that represent tool errors, and thrown
/// exceptions, are removed so a later request can retry them.
class ToolCallResultCache {
  final Map<String, Future<String>> _results = <String, Future<String>>{};

  /// Returns an in-flight or completed result for [name] and [args].
  Future<String>? lookup(String name, Map<String, dynamic> args) {
    return _results[ToolLoopGuard.signatureOf(name, args)];
  }

  /// Executes [run] once for one signature while it is in flight, then reuses
  /// its successful result for the rest of the assistant turn.
  Future<String> run(
    String name,
    Map<String, dynamic> args,
    Future<String> Function() execute,
  ) {
    final signature = ToolLoopGuard.signatureOf(name, args);
    final cached = _results[signature];
    if (cached != null) return cached;

    late final Future<String> pending;
    pending = _runAndKeepSuccessfulResult(signature, execute);
    _results[signature] = pending;
    return pending;
  }

  Future<String> _runAndKeepSuccessfulResult(
    String signature,
    Future<String> Function() execute,
  ) async {
    try {
      final result = await execute();
      if (!ToolLoopGuard.isCacheableResult(result)) {
        _results.remove(signature);
      }
      return result;
    } catch (_) {
      _results.remove(signature);
      rethrow;
    }
  }
}

/// Bounds the multi-round tool-call loops that every provider runs.
///
/// All provider paths (`claude_official`, `google_common`, `google_vertex`,
/// `openai_common` chat-completions) drive tool calls with `while (true)` loops
/// that only exit when the model stops asking for tools. Each follow-up round
/// re-sends the whole conversation plus every prior tool result, so an
/// unbounded loop grows cost roughly quadratically and previously could only be
/// stopped by the user hitting stop.
///
/// The guard sits on the shared [ToolCallHandler]: executing a tool is the only
/// way a provider can obtain the payload for its next round, so a single
/// wrapper covers every provider and both the streaming and non-streaming
/// paths. One instance is created per assistant turn.
///
/// Budgets are sized against real usage: plain chat needs 0 calls, a single
/// web search 1-2, and even multi-step MCP file work normally finishes inside
/// 8-12. Crossing [softCallBudget] therefore means the model is almost
/// certainly looping.
///
/// Two counters are tracked on purpose. [softCallBudget] limits tools actually
/// executed, while [hardCallBudget] limits total requests including refused
/// ones -- otherwise a model that ignores every refusal would never trip the
/// hard limit, since refusals do not consume execution budget.
class ToolLoopGuard {
  /// Past this many executed calls the guard stops running tools and instead
  /// tells the model to finish with what it already gathered.
  static const int softCallBudget = 50;

  /// Absolute stop, counted over every request including refusals. Only
  /// reachable when the model keeps requesting tools after being refused.
  static const int hardCallBudget = 88;

  /// Identical consecutive calls that count as a stuck loop. This fires much
  /// earlier than the budgets in the common "model re-issues the exact same
  /// call forever" failure.
  static const int maxConsecutiveDupes = 3;

  int _calls = 0;
  int _attempts = 0;
  String? _lastSignature;
  int _consecutiveDupes = 0;

  /// Tools actually executed so far in this turn.
  int get callCount => _calls;

  /// Tool requests seen so far, including refused ones.
  int get attemptCount => _attempts;

  /// Builds a stable signature for one tool call so repeats can be detected.
  ///
  /// Map keys are sorted recursively because providers do not guarantee a
  /// stable key order across rounds, and an unstable signature would silently
  /// disable duplicate detection.
  static String signatureOf(String name, Map<String, dynamic> args) {
    return '$name\u0000${jsonEncode(_stableValue(args))}';
  }

  /// Returns whether a result is safe to reuse for an identical later call.
  ///
  /// Tool handlers encode their structured failures as JSON. Plain-text
  /// results remain cacheable because they are the normal form for search and
  /// MCP tool output.
  static bool isCacheableResult(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return true;
      if (decoded['type'] == 'tool_error' ||
          decoded['tool_error'] != null ||
          decoded['isError'] == true) {
        return false;
      }
    } catch (_) {
      // Plain text is a valid successful tool result.
    }
    return true;
  }

  /// Decides whether a tool call may run.
  ///
  /// [cached] is used for an already successful result. It counts the model's
  /// request toward the hard attempt budget, but does not consume execution
  /// budget or participate in consecutive duplicate detection.
  ///
  /// Returns null when the call is allowed (and counts it). Returns a
  /// tool-result payload describing the refusal when the model should wrap up;
  /// feeding this back lets it still answer with what it has. Throws
  /// [ToolLoopBudgetExceeded] once [hardCallBudget] requests have been seen.
  String? evaluate(
    String name,
    Map<String, dynamic> args, {
    bool cached = false,
  }) {
    if (_attempts >= hardCallBudget) {
      throw ToolLoopBudgetExceeded(_attempts);
    }
    _attempts += 1;
    if (cached) return null;

    final signature = signatureOf(name, args);
    if (signature == _lastSignature) {
      _consecutiveDupes += 1;
    } else {
      _lastSignature = signature;
      _consecutiveDupes = 1;
    }

    if (_consecutiveDupes >= maxConsecutiveDupes) {
      return _refusal(
        'repeated_tool_calls',
        'The tool "$name" was requested $maxConsecutiveDupes times in a row '
            'with identical arguments, which indicates a stuck loop. Stop '
            'calling tools and answer using the results already collected.',
      );
    }

    if (_calls >= softCallBudget) {
      return _refusal(
        'tool_budget_exhausted',
        'This turn has already run $softCallBudget tool calls, which is the '
            'limit. No further tools will be executed. Answer now using the '
            'results already collected.',
      );
    }

    _calls += 1;
    return null;
  }

  static Object? _stableValue(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      return <String, Object?>{for (final k in keys) k: _stableValue(value[k])};
    }
    if (value is Iterable) {
      return value.map(_stableValue).toList();
    }
    if (value is num || value is bool || value == null) return value;
    return value.toString();
  }

  static String _refusal(String reason, String message) {
    return jsonEncode(<String, Object?>{
      'tool_error': message,
      'reason': reason,
      'retry': false,
    });
  }
}