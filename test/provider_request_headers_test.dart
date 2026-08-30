import 'package:flutter_test/flutter_test.dart';

import 'package:tin/core/providers/settings_provider.dart';
import 'package:tin/core/services/api/provider_request_headers.dart';

ProviderConfig _config(String baseUrl) {
  return ProviderConfig(
    id: 'test',
    enabled: true,
    name: 'test',
    apiKey: 'test-key',
    baseUrl: baseUrl,
    providerType: ProviderKind.openai,
  );
}

void main() {
  group('providerDefaultHeaders', () {
    test('identifies requests to compatible model gateways as TIN', () {
      final headers = providerDefaultHeaders(
        _config('https://gateway.example.com/v1'),
      );

      expect(headers['User-Agent'], 'TIN');
      expect(headers, isNot(contains('X-OpenRouter-Title')));
    });

    test('uses TIN identity for OpenRouter attribution', () {
      final headers = providerDefaultHeaders(
        _config('https://openrouter.ai/api/v1'),
      );

      expect(headers['User-Agent'], 'TIN');
      expect(headers['X-OpenRouter-Title'], 'TIN');
      expect(headers['HTTP-Referer'], 'https://github.com/nnn669/TIN');
    });
  });
}
