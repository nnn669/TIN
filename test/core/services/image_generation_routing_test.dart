import 'package:flutter_test/flutter_test.dart';

import 'package:tin/core/models/settings_provider.dart';
import 'package:tin/core/providers/settings_provider.dart';
import 'package:tin/core/services/image_generation_routing.dart';

void main() {
  test('routes configured provider and model without changing prompt args', () {
    final settings = SettingsProvider();
    final chat = ProviderConfig(
      id: 'chat',
      enabled: true,
      name: 'Chat',
      apiKey: 'chat-key',
      baseUrl: 'https://chat.example/v1',
      modelOverrides: const {
        'chat-model': {
          'imageProviderId': 'images',
          'imageModelId': 'flux-pro',
        },
      },
    );
    final images = ProviderConfig(
      id: 'images',
      enabled: true,
      name: 'Images',
      apiKey: 'image-key',
      baseUrl: 'https://images.example/v1',
    );
    settings.setProviderConfigsForTesting({'chat': chat, 'images': images});

    final result = ImageGenerationRouting.resolveToolArguments(
      name: ImageGenerationRouting.toolName,
      arguments: const {'prompt': 'a red fox'},
      settings: settings,
      providerKey: 'chat',
      modelId: 'chat-model',
    );

    expect(result.error, isNull);
    expect(result.arguments['prompt'], 'a red fox');
    expect(result.arguments['model'], 'flux-pro');
    expect(result.arguments['api_base_url'], 'https://images.example/v1');
    expect(result.arguments['api_key'], 'image-key');
  });

  test('rejects a partial association and does not leak arguments', () {
    final settings = SettingsProvider();
    final chat = ProviderConfig(
      id: 'chat',
      enabled: true,
      name: 'Chat',
      apiKey: 'chat-key',
      baseUrl: 'https://chat.example/v1',
      modelOverrides: const {
        'chat-model': {'imageProviderId': 'images'},
      },
    );
    settings.setProviderConfigsForTesting({'chat': chat});

    final result = ImageGenerationRouting.resolveToolArguments(
      name: ImageGenerationRouting.toolName,
      arguments: const {'prompt': 'a red fox'},
      settings: settings,
      providerKey: 'chat',
      modelId: 'chat-model',
    );

    expect(result.error, contains('both'));
    expect(result.arguments, isEmpty);
  });

  test('leaves unrelated tools unchanged', () {
    final settings = SettingsProvider();
    final original = <String, dynamic>{'prompt': 'a red fox'};

    final result = ImageGenerationRouting.resolveToolArguments(
      name: 'kelivo_list_image_models',
      arguments: original,
      settings: settings,
      providerKey: 'missing',
      modelId: 'missing',
    );

    expect(result.error, isNull);
    expect(identical(result.arguments, original), isTrue);
  });
}