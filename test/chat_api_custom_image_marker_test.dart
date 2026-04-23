import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';

ProviderConfig _openAiConfig(String baseUrl) {
  return ProviderConfig(
    id: 'OpenAITest',
    enabled: true,
    name: 'OpenAITest',
    apiKey: 'test-key',
    baseUrl: baseUrl,
    providerType: ProviderKind.openai,
    useResponseApi: false,
  );
}

void main() {
  group('ChatApiService custom image markers', () {
    test('encodes existing local custom image markers as data URLs', () async {
      final body = await _sendAndCaptureRequestBody((baseUrl) async {
        final dir = await Directory.systemTemp.createTemp('kelivo_local_img_');
        addTearDown(() async {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        });

        final file = File('${dir.path}/sample.png');
        await file.writeAsBytes(const [1, 2, 3, 4]);

        return ChatApiService.sendMessageStream(
          config: _openAiConfig(baseUrl),
          modelId: 'gpt-4.1',
          messages: [
            {'role': 'user', 'content': 'before [image:${file.path}] after'},
          ],
          stream: false,
        ).toList();
      });

      final parts = _extractSingleMessageParts(body);
      expect(parts, hasLength(2));
      expect(parts.first['type'], 'text');
      expect(parts.first['text'], 'before  after');
      expect(parts.last['type'], 'image_url');
      expect(
        (parts.last['image_url'] as Map<String, dynamic>)['url'] as String,
        'data:image/png;base64,AQIDBA==',
      );
    });

    test(
      'passes data URL custom image markers through without file access',
      () async {
        const dataUrl = 'data:image/png;base64,QUJD';
        final body = await _sendAndCaptureRequestBody((baseUrl) async {
          return ChatApiService.sendMessageStream(
            config: _openAiConfig(baseUrl),
            modelId: 'gpt-4.1',
            messages: const [
              {
                'role': 'user',
                'content': 'inline [image:data:image/png;base64,QUJD]',
              },
            ],
            stream: false,
          ).toList();
        });

        final parts = _extractSingleMessageParts(body);
        expect(parts, hasLength(2));
        expect(parts.first['type'], 'text');
        expect(parts.first['text'], 'inline');
        expect(parts.last['type'], 'image_url');
        expect(
          (parts.last['image_url'] as Map<String, dynamic>)['url'] as String,
          dataUrl,
        );
      },
    );

    test(
      'keeps missing local custom image markers as text instead of reading files',
      () async {
        final missingPath =
            '${Directory.systemTemp.path}/missing_${DateTime.now().microsecondsSinceEpoch}.png';
        final body = await _sendAndCaptureRequestBody((baseUrl) async {
          return ChatApiService.sendMessageStream(
            config: _openAiConfig(baseUrl),
            modelId: 'gpt-4.1',
            messages: [
              {'role': 'user', 'content': 'before [image:$missingPath] after'},
            ],
            stream: false,
          ).toList();
        });

        final parts = _extractSingleMessageParts(body);
        expect(parts, hasLength(1));
        expect(parts.single['type'], 'text');
        expect(parts.single['text'], 'before [image:$missingPath] after');
      },
    );
  });
}

Future<Map<String, dynamic>> _sendAndCaptureRequestBody(
  Future<List<dynamic>> Function(String baseUrl) sendRequest,
) async {
  Map<String, dynamic>? requestBody;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final baseUrl = 'http://${server.address.address}:${server.port}/v1';

  try {
    server.listen((request) async {
      final rawBody = await utf8.decoder.bind(request).join();
      requestBody = (jsonDecode(rawBody) as Map).cast<String, dynamic>();
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'chatcmpl-1',
          'object': 'chat.completion',
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': 'ok'},
              'finish_reason': 'stop',
            },
          ],
          'usage': {
            'prompt_tokens': 1,
            'completion_tokens': 1,
            'total_tokens': 2,
          },
        }),
      );
      await request.response.close();
    });

    final chunks = await sendRequest(baseUrl);
    expect(chunks, isNotEmpty);
    expect(requestBody, isNotNull);
    return requestBody!;
  } finally {
    await server.close(force: true);
  }
}

List<Map<String, dynamic>> _extractSingleMessageParts(
  Map<String, dynamic> body,
) {
  final messages = (body['messages'] as List).cast<dynamic>();
  expect(messages, hasLength(1));
  final content =
      (messages.single as Map<String, dynamic>)['content'] as List<dynamic>;
  return content
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList(growable: false);
}
