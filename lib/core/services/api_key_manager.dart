import 'dart:math';
import '../models/api_keys.dart';
import '../providers/settings_provider.dart';

class KeySelectionResult {
  final ApiKeyConfig? key;
  final String reason;
  const KeySelectionResult(this.key, this.reason);
}

/// Cooldown applied to keys that were rate limited (HTTP 429).
///
/// Rate limits usually clear much faster than a genuinely broken key, so this
/// is deliberately shorter than [KeyManagementConfig.failureRecoveryTimeMinutes].
const int _rateLimitCooldownMs = 60 * 1000;

/// Runtime health of a single API key.
///
/// This lives in memory only. A cold start therefore gives every key a fresh
/// chance instead of resurrecting a stale "error" verdict from disk.
class _KeyHealth {
  _KeyHealth({required this.status, required this.statusChangedAt});

  ApiKeyStatus status;
  int statusChangedAt;
  int consecutiveFailures = 0;
  int totalRequests = 0;
}

/// Binds a raw key value to the id and threshold needed to score its outcomes,
/// so the request layer does not have to thread provider context around.
class _KeyBinding {
  const _KeyBinding({
    required this.keyId,
    required this.maxFailuresBeforeDisable,
  });

  final String keyId;
  final int maxFailuresBeforeDisable;
}

class ApiKeyManager {
  static final ApiKeyManager _instance = ApiKeyManager._internal();
  factory ApiKeyManager() => _instance;
  ApiKeyManager._internal();

  static final Random _rng = Random();

  // providerId -> next round-robin index.
  // Deliberately in-memory: persisting this would mean a SharedPreferences
  // write on every single request, and restarting from 0 barely affects
  // balancing quality. KeyManagementConfig.roundRobinIndex is only ever read,
  // as a starting hint.
  final Map<String, int> _roundRobinIndexMap = {};

  // keyId -> runtime health overlay applied on top of the persisted config.
  final Map<String, _KeyHealth> _health = {};

  // Raw key value -> binding, registered when a key is handed out so that
  // [reportHttpOutcome] can attribute a status code back to it. When the same
  // key value is shared by several providers the most recent selection wins,
  // which is harmless because the health verdict is per key value anyway.
  final Map<String, _KeyBinding> _bindings = {};

  /// Runtime status for a key, or null when it has no runtime history yet.
  ApiKeyStatus? runtimeStatusFor(String keyId) => _health[keyId]?.status;

  /// Clears all runtime state. Intended for tests.
  void resetRuntimeState() {
    _health.clear();
    _bindings.clear();
    _roundRobinIndexMap.clear();
  }

  int _effectiveTotalRequests(ApiKeyConfig key) =>
      key.usage.totalRequests + (_health[key.id]?.totalRequests ?? 0);

  ApiKeyStatus _effectiveStatus(ApiKeyConfig key) =>
      _health[key.id]?.status ?? key.status;

  int _statusChangedAt(ApiKeyConfig key) =>
      _health[key.id]?.statusChangedAt ?? key.updatedAt;

  KeySelectionResult selectForProvider(ProviderConfig provider) {
    final keys = List<ApiKeyConfig>.from(
      (provider.apiKeys ?? const <ApiKeyConfig>[]).where((k) => k.isEnabled),
    );
    if (keys.isEmpty) return const KeySelectionResult(null, 'no_keys');

    final km = provider.keyManagement ?? const KeyManagementConfig();
    final now = DateTime.now().millisecondsSinceEpoch;
    final errorCooldownMs = km.failureRecoveryTimeMinutes * 60 * 1000;

    final available = keys.where((k) {
      final status = _effectiveStatus(k);
      if (status == ApiKeyStatus.active) return true;
      if (status == ApiKeyStatus.disabled) return false;
      // error / rateLimited: let the key back in on probation once its cooldown
      // has elapsed. Without auto recovery it stays out until the user runs a
      // manual detection pass.
      if (!km.enableAutoRecovery) return false;
      final cooldownMs = status == ApiKeyStatus.rateLimited
          ? _rateLimitCooldownMs
          : errorCooldownMs;
      return (now - _statusChangedAt(k)) >= cooldownMs;
    }).toList();

    if (available.isEmpty) {
      return const KeySelectionResult(null, 'no_available_keys');
    }

    ApiKeyConfig chosen;
    switch (km.strategy) {
      case LoadBalanceStrategy.priority:
        available.sort((a, b) => a.priority.compareTo(b.priority));
        chosen = available.first;
        break;
      case LoadBalanceStrategy.leastUsed:
        available.sort(
          (a, b) =>
              _effectiveTotalRequests(a).compareTo(_effectiveTotalRequests(b)),
        );
        chosen = available.first;
        break;
      case LoadBalanceStrategy.random:
        chosen = available[_rng.nextInt(available.length)];
        break;
      case LoadBalanceStrategy.roundRobin:
        final cur =
            _roundRobinIndexMap[provider.id] ?? (km.roundRobinIndex ?? 0);
        final idx = cur % available.length;
        chosen = available[idx];
        _roundRobinIndexMap[provider.id] = (idx + 1) % available.length;
        break;
    }

    if (chosen.key.trim().isNotEmpty) {
      _bindings[chosen.key] = _KeyBinding(
        keyId: chosen.id,
        maxFailuresBeforeDisable: km.maxFailuresBeforeDisable,
      );
    }

    return KeySelectionResult(chosen, 'strategy_${km.strategy.name}');
  }

  /// Attributes an HTTP status code to whichever managed key signed the
  /// request, based on the outbound auth headers.
  ///
  /// Requests that do not carry a key this manager handed out are ignored, so
  /// unrelated traffic (search, TTS, avatars) cannot pollute key health. Being
  /// called with a status code at all means the transport succeeded, so
  /// timeouts and cancellations never reach here and are never blamed on a key.
  void reportHttpOutcome(Map<String, String> requestHeaders, int statusCode) {
    if (_bindings.isEmpty) return;
    for (final candidate in _authCandidates(requestHeaders)) {
      final binding = _bindings[candidate];
      if (binding == null) continue;
      _applyOutcome(binding, statusCode);
      return;
    }
  }

  Iterable<String> _authCandidates(Map<String, String> headers) {
    final out = <String>[];
    void add(String raw) {
      final v = raw.trim();
      if (v.isEmpty) return;
      if (v.length > 7 && v.substring(0, 7).toLowerCase() == 'bearer ') {
        final token = v.substring(7).trim();
        if (token.isNotEmpty) out.add(token);
        return;
      }
      out.add(v);
    }

    for (final entry in headers.entries) {
      switch (entry.key.toLowerCase()) {
        case 'authorization':
        case 'x-api-key':
        case 'x-goog-api-key':
        case 'api-key':
          add(entry.value);
          break;
      }
    }
    return out;
  }

  void _applyOutcome(_KeyBinding binding, int statusCode) {
    if (statusCode >= 200 && statusCode < 300) {
      _recordSuccess(binding);
      return;
    }
    // Only blame the key for auth, quota and server failures. 400/404/422 and
    // friends are request problems, not key problems.
    final blamesKey =
        statusCode == 401 ||
        statusCode == 403 ||
        statusCode == 429 ||
        statusCode >= 500;
    if (!blamesKey) return;
    _recordFailure(binding, statusCode);
  }

  _KeyHealth _healthFor(String keyId) => _health.putIfAbsent(
    keyId,
    () => _KeyHealth(
      status: ApiKeyStatus.active,
      statusChangedAt: DateTime.now().millisecondsSinceEpoch,
    ),
  );

  void _recordSuccess(_KeyBinding binding) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final h = _healthFor(binding.keyId);
    h.totalRequests += 1;
    h.consecutiveFailures = 0;
    if (h.status != ApiKeyStatus.active) {
      h.status = ApiKeyStatus.active;
      h.statusChangedAt = now;
    }
  }

  void _recordFailure(_KeyBinding binding, int statusCode) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final h = _healthFor(binding.keyId);
    h.totalRequests += 1;
    h.consecutiveFailures += 1;

    if (statusCode == 429) {
      h.status = ApiKeyStatus.rateLimited;
      h.statusChangedAt = now;
      return;
    }
    if (h.consecutiveFailures >= binding.maxFailuresBeforeDisable) {
      h.status = ApiKeyStatus.error;
      h.statusChangedAt = now;
    }
  }

  /// Folds a request outcome into a persistable [ApiKeyConfig].
  ///
  /// Used by the manual detection flows that write results back to the provider
  /// config; the live request path relies on [reportHttpOutcome] instead.
  ApiKeyConfig updateKeyStatus(
    ProviderConfig provider,
    ApiKeyConfig key,
    bool success, {
    String? error,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final nextConsecutive = success ? 0 : (key.usage.consecutiveFailures + 1);
    final maxFailures = provider.keyManagement?.maxFailuresBeforeDisable ?? 3;
    final nextStatus = success
        ? ApiKeyStatus.active
        : (nextConsecutive >= maxFailures ? ApiKeyStatus.error : key.status);

    // Keep the runtime overlay in step with the manual verdict.
    final h = _healthFor(key.id);
    if (h.status != nextStatus) {
      h.status = nextStatus;
      h.statusChangedAt = now;
    }
    h.consecutiveFailures = nextConsecutive;

    return key.copyWith(
      usage: key.usage.copyWith(
        totalRequests: key.usage.totalRequests + 1,
        successfulRequests: key.usage.successfulRequests + (success ? 1 : 0),
        failedRequests: key.usage.failedRequests + (success ? 0 : 1),
        consecutiveFailures: nextConsecutive,
        lastUsed: now,
      ),
      status: nextStatus,
      lastError: success ? null : (error ?? key.lastError),
      updatedAt: now,
    );
  }
}
