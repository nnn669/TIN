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
