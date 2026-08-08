import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tin/core/providers/settings_provider.dart';
import 'package:tin/features/chat/utils/model_match_helper.dart';

group('normalizeModelTokens', () {
  test('splits by separators and lowercases', () {
    expect(
      normalizeModelTokens('DeepSeek-V4-Flash'),
      <String>['deepseek', 'v4', 'flash'],
    );
    expect(
      normalizeModelTokens('deepseek_v4_flash'),
      <String>['deepseek', 'v4', 'flash'],
    );
    expect(
      normalizeModelTokens('DeepSeek V4 Flash'),
      <String>['deepseek', 'v4', 'flash'],
    );
    expect(
      normalizeModelTokens('GLM-4.5-Air'),
      <String>['glm', '4', '5', 'air'],
    );
  });
});

group('isSameModel', () {
  test('matches same model with different separators', () {
    expect(isSameModel('DeepSeek-V4-Flash', 'deepseek v4 flash'), isTrue);
    expect(isSameModel('deepseek-v4-flash', 'deepseek_v4_flash'), isTrue);
    expect(isSameModel('GLM-4.5-Air', 'glm-4-5-air'), isTrue);
    expect(isSameModel('DeepSeek-V4', 'deepseek-v4'), isTrue);
  });

  test('matches pro / flash / sol suffix levels', () {
    expect(isSameModel('deepseek-v4-pro', 'deepseek-v4-pro'), isTrue);
    expect(isSameModel('kimi-sol', 'kimi-sol'), isTrue);
    expect(isSameModel('kimi-sol', 'kimi-flash'), isFalse);
    expect(isSameModel('deepseek-v4-pro', 'deepseek-v4-flash'), isFalse);
  });

  test('rejects different models', () {
    expect(isSameModel('deepseek-v4-flash', 'deepseek-v3'), isFalse);
    expect(isSameModel('gpt-4o', 'gpt-4'), isFalse);
    expect(isSameModel('', 'deepseek-v4-flash'), isFalse);
    expect(isSameModel('deepseek-v4-flash', ''), isFalse);
  });
});

group('isRespondedModelMatching', () {
  test('matches identical models', () {
    expect(
      isRespondedModelMatching('gpt-4o', 'gpt-4o'),
      isTrue,
    );
    expect(
      isRespondedModelMatching('deepseek-v4-flash', 'deepseek_v4_flash'),
      isTrue,
    );
  });

  test('tolerates official date/version suffixes (request is prefix)', () {
    expect(
      isRespondedModelMatching('gpt-4o', 'gpt-4o-2024-05-13'),
      isTrue,
    );
    expect(
      isRespondedModelMatching('gpt-4o-mini', 'gpt-4o-mini-2024-07-18'),
      isTrue,
    );
  });

  test('rejects swapped / downgraded models', () {
    expect(
      isRespondedModelMatching('gpt-4o', 'gpt-3.5-turbo'),
      isFalse,
    );
    expect(
      isRespondedModelMatching('deepseek-v3', 'gpt-4o'),
      isFalse,
    );
    expect(
      isRespondedModelMatching('deepseek-v4-flash', 'deepseek-v3'),
      isFalse,
    );
    expect(isRespondedModelMatching('', 'gpt-4o'), isFalse);
    expect(isRespondedModelMatching('gpt-4o', ''), isFalse);
  });
});

group('resolveApiModelId', () {
  test('falls back to raw modelId without provider override', () {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsProvider();
    expect(
      resolveApiModelId(settings, modelId: 'deepseek-v4-flash'),
      'deepseek-v4-flash',
    );
    expect(resolveApiModelId(settings, modelId: null), isNull);
    expect(resolveApiModelId(settings, modelId: '  '), isNull);
  });
});

group('RespondedModelRegistry', () {
  tearDown(RespondedModelRegistry.clear);

  test('records and looks up by message id', () {
    RespondedModelRegistry.record('msg-1', 'gpt-4o-2024-05-13');
    expect(RespondedModelRegistry.lookup('msg-1'), 'gpt-4o-2024-05-13');
    expect(RespondedModelRegistry.lookup('msg-2'), isNull);
  });

  test('ignores blank inputs', () {
    RespondedModelRegistry.record('msg-1', '   ');
    expect(RespondedModelRegistry.lookup('msg-1'), isNull);
    RespondedModelRegistry.record('', 'gpt-4o');
    expect(RespondedModelRegistry.lookup(''), isNull);
  });

  test('overwrites and removes', () {
    RespondedModelRegistry.record('msg-1', 'gpt-4o');
    RespondedModelRegistry.record('msg-1', 'gpt-4o-mini');
    expect(RespondedModelRegistry.lookup('msg-1'), 'gpt-4o-mini');

    RespondedModelRegistry.remove('msg-1');
    expect(RespondedModelRegistry.lookup('msg-1'), isNull);

    RespondedModelRegistry.record('msg-2', 'claude-sonnet-4-6');
    RespondedModelRegistry.clear();
    expect(RespondedModelRegistry.lookup('msg-2'), isNull);
  });
});