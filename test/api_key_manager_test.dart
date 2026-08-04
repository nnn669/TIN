import 'package:flutter_test/flutter_test.dart';

import 'package:tin/core/models/api_keys.dart';
import 'package:tin/core/providers/settings_provider.dart';
import 'package:tin/core/services/api_key_manager.dart';

ApiKeyConfig _key(String id, String value) {
  return ApiKeyConfig(id: id, key: value, createdAt: 1, updatedAt: 1);
}

ApiKeyConfig _usedKey(String id, String value, int totalRequests) {
  return _key(
    id,
    value,
  ).copyWith(usage: ApiKeyUsage(totalRequests: totalRequests));
}

ProviderConfig _provider({
  required String id,
  required List<ApiKeyConfig> keys,
  LoadBalanceStrategy strategy = LoadBalanceStrategy.roundRobin,
  int maxFailuresBeforeDisable = 3,
  bool enableAutoRecovery = true,
}) {
  return ProviderConfig(
    id: id,
    enabled: true,
    name: id,
    apiKey: '',
    baseUrl: 'https://example.test/v1',
    providerType: ProviderKind.openai,
    multiKeyEnabled: true,
    apiKeys: keys,
    keyManagement: KeyManagementConfig(
      strategy: strategy,
      maxFailuresBeforeDisable: maxFailuresBeforeDisable,
      enableAutoRecovery: enableAutoRecovery,
    ),
  );
}

Map<String, String> _bearer(String key) => {'Authorization': 'Bearer $key'};

void main() {
  setUp(() => ApiKeyManager().resetRuntimeState());

  group('ApiKeyManager', () {
    test('round robin consumes keys in configured list order', () {
      final provider = _provider(
        id: 'round-robin-list-order',
        keys: [
          _key('key_z', 'first'),
          _key('key_a', 'second'),
          _key('key_m', 'third'),
        ],
      );
      final manager = ApiKeyManager();

      final selected = [
        manager.selectForProvider(provider).key?.key,
        manager.selectForProvider(provider).key?.key,
        manager.selectForProvider(provider).key?.key,
        manager.selectForProvider(provider).key?.key,
      ];

      expect(selected, ['first', 'second', 'third', 'first']);
    });

    test(
      'round robin skips disabled keys without reordering remaining keys',
      () {
        final provider = _provider(
          id: 'round-robin-disabled-skip',
          keys: [
            _key('key_m', 'disabled').copyWith(isEnabled: false),
            _key('key_z', 'second'),
            _key('key_a', 'third'),
          ],
        );
        final manager = ApiKeyManager();

        final selected = [
          manager.selectForProvider(provider).key?.key,
          manager.selectForProvider(provider).key?.key,
          manager.selectForProvider(provider).key?.key,
        ];

        expect(selected, ['second', 'third', 'second']);
      },
    );

    test('returns no available keys when all configured keys are disabled', () {
      final provider = _provider(
        id: 'round-robin-no-available',
        keys: [
          _key('key_a', 'first').copyWith(isEnabled: false),
          _key('key_b', 'second').copyWith(status: ApiKeyStatus.disabled),
        ],
      );

      final result = ApiKeyManager().selectForProvider(provider);

      expect(result.key, isNull);
      expect(result.reason, 'no_available_keys');
    });

    test('priority strategy still selects the lowest priority value', () {
      final provider = _provider(
        id: 'priority-strategy',
        strategy: LoadBalanceStrategy.priority,
        keys: [
          _key('key_a', 'normal').copyWith(priority: 5),
          _key('key_b', 'preferred').copyWith(priority: 1),
        ],
      );

      final result = ApiKeyManager().selectForProvider(provider);

      expect(result.key?.key, 'preferred');
    });

    test('least used strategy still selects the key with fewer requests', () {
      final provider = _provider(
        id: 'least-used-strategy',
        strategy: LoadBalanceStrategy.leastUsed,
        keys: [_usedKey('key_a', 'busy', 5), _usedKey('key_b', 'idle', 1)],
      );

      final result = ApiKeyManager().selectForProvider(provider);

      expect(result.key?.key, 'idle');
    });
  });

  group('ApiKeyManager runtime health', () {
    test('repeated auth failures trip the key out of rotation', () {
      final provider = _provider(
        id: 'health-auth-failures',
        keys: [_key('key_a', 'first'), _key('key_b', 'second')],
        maxFailuresBeforeDisable: 3,
      );
      final manager = ApiKeyManager();

      expect(manager.selectForProvider(provider).key?.key, 'first');
      for (var i = 0; i < 3; i++) {
        manager.reportHttpOutcome(_bearer('first'), 401);
      }
      expect(manager.runtimeStatusFor('key_a'), ApiKeyStatus.error);

      final selected = [
        manager.selectForProvider(provider).key?.key,
        manager.selectForProvider(provider).key?.key,
      ];
      expect(selected, ['second', 'second']);
    });

    test('a single 429 marks the key rate limited and pauses it', () {
      final provider = _provider(
        id: 'health-rate-limited',
        keys: [_key('key_a', 'first'), _key('key_b', 'second')],
      );
      final manager = ApiKeyManager();

      expect(manager.selectForProvider(provider).key?.key, 'first');
      manager.reportHttpOutcome(_bearer('first'), 429);

      expect(manager.runtimeStatusFor('key_a'), ApiKeyStatus.rateLimited);
      expect(manager.selectForProvider(provider).key?.key, 'second');
    });

    test('request-level failures are never blamed on the key', () {
      final provider = _provider(
        id: 'health-client-errors',
        keys: [_key('key_a', 'first')],
        maxFailuresBeforeDisable: 2,
      );
      final manager = ApiKeyManager();

      manager.selectForProvider(provider);
      for (final code in [400, 404, 422]) {
        manager.reportHttpOutcome(_bearer('first'), code);
      }

      expect(manager.runtimeStatusFor('key_a'), isNull);
      expect(manager.selectForProvider(provider).key?.key, 'first');
    });

    test('a success resets the consecutive failure streak', () {
      final provider = _provider(
        id: 'health-success-reset',
        keys: [_key('key_a', 'first')],
        maxFailuresBeforeDisable: 3,
      );
      final manager = ApiKeyManager();

      manager.selectForProvider(provider);
      manager.reportHttpOutcome(_bearer('first'), 401);
      manager.reportHttpOutcome(_bearer('first'), 401);
      manager.reportHttpOutcome(_bearer('first'), 200);
      manager.reportHttpOutcome(_bearer('first'), 401);
      manager.reportHttpOutcome(_bearer('first'), 401);

      expect(manager.runtimeStatusFor('key_a'), ApiKeyStatus.active);
      expect(manager.selectForProvider(provider).key?.key, 'first');
    });

    test('a 5xx response counts against the key', () {
      final provider = _provider(
        id: 'health-server-errors',
        keys: [_key('key_a', 'first')],
        maxFailuresBeforeDisable: 2,
      );
      final manager = ApiKeyManager();

      manager.selectForProvider(provider);
      manager.reportHttpOutcome(_bearer('first'), 500);
      manager.reportHttpOutcome(_bearer('first'), 503);

      expect(manager.runtimeStatusFor('key_a'), ApiKeyStatus.error);
    });

    test('outcomes for unmanaged keys are ignored', () {
      final provider = _provider(
        id: 'health-unmanaged',
        keys: [_key('key_a', 'first')],
        maxFailuresBeforeDisable: 1,
      );
      final manager = ApiKeyManager();

      manager.selectForProvider(provider);
      manager.reportHttpOutcome(_bearer('some-unrelated-token'), 401);

      expect(manager.runtimeStatusFor('key_a'), isNull);
    });

    test('x-api-key and x-goog-api-key headers are attributed too', () {
      final provider = _provider(
        id: 'health-alt-headers',
        keys: [_key('key_a', 'claude-key'), _key('key_b', 'gemini-key')],
        maxFailuresBeforeDisable: 1,
      );
      final manager = ApiKeyManager();

      manager.selectForProvider(provider);
      manager.selectForProvider(provider);
      manager.reportHttpOutcome({'x-api-key': 'claude-key'}, 401);
      manager.reportHttpOutcome({'x-goog-api-key': 'gemini-key'}, 429);

      expect(manager.runtimeStatusFor('key_a'), ApiKeyStatus.error);
      expect(manager.runtimeStatusFor('key_b'), ApiKeyStatus.rateLimited);
    });

    test('a persisted error status recovers once the cooldown has passed', () {
      final provider = _provider(
        id: 'health-cooldown-recovery',
        keys: [
          _key('key_a', 'stale-error').copyWith(status: ApiKeyStatus.error),
        ],
      );

      // updatedAt sits 1ms after the epoch, so the recovery window has long
      // since elapsed and the key should get another chance.
      final result = ApiKeyManager().selectForProvider(provider);

      expect(result.key?.key, 'stale-error');
    });

    test('a rate limited key is not excluded forever', () {
      final provider = _provider(
        id: 'health-rate-limited-recovery',
        keys: [
          _key(
            'key_a',
            'stale-limited',
          ).copyWith(status: ApiKeyStatus.rateLimited),
        ],
      );

      final result = ApiKeyManager().selectForProvider(provider);

      expect(result.key?.key, 'stale-limited');
    });

    test('auto recovery disabled keeps a failed key out indefinitely', () {
      final provider = _provider(
        id: 'health-no-auto-recovery',
        keys: [
          _key('key_a', 'stale-error').copyWith(status: ApiKeyStatus.error),
        ],
        enableAutoRecovery: false,
      );

      final result = ApiKeyManager().selectForProvider(provider);

      expect(result.key, isNull);
      expect(result.reason, 'no_available_keys');
    });

    test('least used strategy accounts for runtime request counts', () {
      final provider = _provider(
        id: 'health-least-used',
        strategy: LoadBalanceStrategy.leastUsed,
        keys: [_usedKey('key_a', 'fresh', 0), _usedKey('key_b', 'warm', 2)],
      );
      final manager = ApiKeyManager();

      expect(manager.selectForProvider(provider).key?.key, 'fresh');

      // Three recorded outcomes push the runtime count past the other key's
      // persisted total, so the balancer has to switch.
      for (var i = 0; i < 3; i++) {
        manager.reportHttpOutcome(_bearer('fresh'), 200);
      }

      expect(manager.selectForProvider(provider).key?.key, 'warm');
    });
  });
}
