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
  ///
  /// Only explicitly read-only web/search tools are eligible. This prevents
  /// memory, app-control, local, and arbitrary MCP mutations from being
  /// replayed from a previous result.
  Future<String>? lookup(String name, Map<String, dynamic> args) {
    if (!ToolLoopGuard.isReadOnlyCacheTool(name)) return null;
    return _results[ToolLoopGuard.signatureOf(name, args)];
  }

  /// Executes [run] once for one signature while it is in flight, then reuses
  /// its successful result for the rest of the assistant turn.
  Future<String> run(
    String name,
    Map<String, dynamic> args,
    Future<String> Function() execute,
  ) {
    if (!ToolLoopGuard.isReadOnlyCacheTool(name)) return execute();

    final signature = ToolLoopGuard.signatureOf(name, args);
    final cached = _results[signature];
    if (cached != null) return cached;

    late final Future<String> pending;
    pending = _runAndKeepSuccessfulResult(
      signature,
      execute,
      () => pending,
    );
    _results[signature] = pending;
    return pending;
  }

  Future<String> _runAndKeepSuccessfulResult(
    String signature,
    Future<String> Function() execute,
    Future<String> Function() current,
  ) async {
    try {
      final result = await execute();
      if (!ToolLoopGuard.isCacheableResult(result) &&
          identical(_results[signature], current())) {
        _results.remove(signature);
      }
      return result;
    } catch (_) {
      if (identical(_results[signature], current())) {
        _results.remove(signature);
      }
      rethrow;
    }
  }
}

/// Bounds the multi-round tool-call loops that every provider runs.
class ToolLoopGuard {
  /// Past this many executed calls the guard stops running tools and instead
  /// tells the model to finish with what it already gathered.
  static const int softCallBudget = 50;

  /// Absolute stop, counted over every request including refusals.
  static const int hardCallBudget = 88;

  /// Identical consecutive calls that count as a stuck loop.
  static const int maxConsecutiveDupes = 3;

  static const Set<String> _readOnlyCacheTools = <String>{
    'search_web',
    'fetch_html',
    'fetch_markdown',
    'fetch_txt',
    'fetch_json',
    'tool_kelivo_fetch_html',
    'tool_kelivo_fetch_markdown',
    'tool_kelivo_fetch_txt',
    'tool_kelivo_fetch_json',
  };

  int _calls = 0;
  int _attempts = 0;
  String? _lastSignature;
  int _consecutiveDupes = 0;

  /// Tools actually executed so far in this turn.
  int get callCount => _calls;

  /// Tool requests seen so far, including refused ones.
  int get attemptCount => _attempts;

  /// Builds a stable signature for one tool call.
  static String signatureOf(String name, Map<String, dynamic> args) {
    return '$name\u0000${jsonEncode(_stableValue(args))}';
  }

  /// Returns whether [name] is an explicitly read-only web/search tool.
  static bool isReadOnlyCacheTool(String name) {
    final normalized = name.trim().toLowerCase().replaceAll('-', '_');
    return _readOnlyCacheTools.contains(normalized);
  }

  /// Returns whether a result is safe to reuse for an identical later call.
  static bool isCacheableResult(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return true;
      if (decoded['type'] == 'tool_error' ||
          decoded['tool_error'] != null ||
          decoded['isError'] == true ||
          decoded['error'] != null) {
        return false;
      }
    } catch (_) {
      // Plain text is a valid successful tool result.
    }
    return true;
  }

  /// Clears the duplicate streak after a failed execution so a retry is not
  /// mistaken for a model loop. The request budget remains counted.
  void resetDuplicateStreak(String name, Map<String, dynamic> args) {
    if (signatureOf(name, args) != _lastSignature) return;
    _lastSignature = null;
    _consecutiveDupes = 0;
  }

  /// Decides whether a tool call may run.
  ///
  /// [cached] counts the request toward the hard budget, but does not consume
  /// execution budget or participate in consecutive duplicate detection.
  /// Returns null when allowed, a refusal payload when the model should stop,
  /// and throws once [hardCallBudget] requests have been seen.
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
    if (value is Iterable) return value.map(_stableValue).toList();
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