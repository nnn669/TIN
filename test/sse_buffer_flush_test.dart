import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tin/core/providers/settings_provider.dart';
import 'package:tin/core/services/api/chat_api_service.dart';

ProviderConfig _testConfig(String baseUrl) {
  return ProviderConfig(
    id: 'SseTest',
    enabled: true,
    name: 'SseTest',
    apiKey: 'test-key',
    baseUrl: baseUrl,
    providerType: ProviderKind.openai,
  );
}

void main() {
  group('SSE response parsing', () {
    test(
      'content is not truncated when final SSE chunk lacks trailing newline',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async => server.close(force: true));

        server.listen((request) {
          request.response.statusCode = 200;
          request.response.headers
            ..contentType = ContentType('text', 'event-stream')
            ..set('Transfer-Encoding', 'chunked');

          final chunk1 = jsonEncode({
            'choices': [
              {
                'delta': {'content': 'Hello '},
                'finish_reason': null,
              },
            ],
          });
          final chunk2 = jsonEncode({
            'choices': [
              {
                'delta': {'content': 'World'},
                'finish_reason': 'stop',
              },
            ],
          });

          request.response.write('data: $chunk1\n\n');
          request.response.write('data: $chunk2\n\n');
          request.response.write('data: [DONE]');
          request.response.close();
        });

        final config = _testConfig('http://localhost:${server.port}/v1');
        final chunks = <ChatStreamChunk>[];
        await for (final chunk in ChatApiService.sendMessageStream(
          config: config,
          modelId: 'test-model',
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
        )) {
          chunks.add(chunk);
        }

        expect(chunks.map((chunk) => chunk.content).join(), 'Hello World');
        expect(chunks.last.isDone, isTrue);
      },
    );

    test('stream without done sentinel still yields all content', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));

      server.listen((request) {
        request.response.statusCode = 200;
        request.response.headers
          ..contentType = ContentType('text', 'event-stream')
          ..set('Transfer-Encoding', 'chunked');

        final chunk1 = jsonEncode({
          'choices': [
            {
              'delta': {'content': 'Partial'},
              'finish_reason': null,
            },
          ],
        });
        final chunk2 = jsonEncode({
          'choices': [
            {
              'delta': {'content': ' response'},
              'finish_reason': null,
            },
          ],
        });

        request.response.write('data: $chunk1\n\n');
        request.response.write('data: $chunk2');
        request.response.close();
      });

      final config = _testConfig('http://localhost:${server.port}/v1');
      final chunks = await ChatApiService.sendMessageStream(
        config: config,
        modelId: 'test-model',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      ).toList();

      expect(chunks.map((chunk) => chunk.content).join(), 'Partial response');
      expect(chunks.last.isDone, isTrue);
    });

    test('usage-only chunk after stop populates token details', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));

      server.listen((request) {
        request.response.statusCode = 200;
        request.response.headers
          ..contentType = ContentType('text', 'event-stream')
          ..set('Transfer-Encoding', 'chunked');

        final stopChunk = jsonEncode({
          'choices': [
            {
              'finish_reason': 'stop',
              'delta': {'content': '', 'reasoning_content': null},
              'index': 0,
              'logprobs': null,
            },
          ],
          'object': 'chat.completion.chunk',
          'usage': null,
          'model': 'deepseek-v4-pro',
          'id': 'chatcmpl-test',
        });
        final usageChunk = jsonEncode({
          'choices': [],
          'object': 'chat.completion.chunk',
          'usage': {
            'prompt_tokens': 842,
            'completion_tokens': 53,
            'total_tokens': 895,
            'completion_tokens_details': {'reasoning_tokens': 30},
            'prompt_tokens_details': {'cached_tokens': 384},
          },
          'model': 'deepseek-v4-pro',
          'id': 'chatcmpl-test',
        });

        request.response.write('data: $stopChunk\n\n');
        request.response.write('data: $usageChunk\n\n');
        request.response.write('data: [DONE]\n\n');
        request.response.close();
      });

      final config = _testConfig('http://localhost:${server.port}/v1');
      final chunks = await ChatApiService.sendMessageStream(
        config: config,
        modelId: 'deepseek-v4-pro',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      ).toList();

      expect(chunks.last.isDone, isTrue);
      expect(chunks.last.totalTokens, 895);
      expect(chunks.last.usage?.promptTokens, 842);
      expect(chunks.last.usage?.completionTokens, 53);
      expect(chunks.last.usage?.cachedTokens, 384);
    });

    test('stream request accepts a normal JSON response', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));

      server.listen((request) async {
        final requestBody = await utf8.decoder.bind(request).join();
        expect(jsonDecode(requestBody)['stream'], isTrue);
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'JSON fallback'},
                'finish_reason': 'stop',
              },
            ],
            'usage': {
              'prompt_tokens': 2,
              'completion_tokens': 3,
              'total_tokens': 5,
            },
          }),
        );
        await request.response.close();
      });

      final config = _testConfig('http://localhost:${server.port}/v1');
      final chunks = await ChatApiService.sendMessageStream(
        config: config,
        modelId: 'test-model',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      ).toList();

      expect(chunks.map((chunk) => chunk.content).join(), 'JSON fallback');
      expect(chunks.last.isDone, isTrue);
      expect(chunks.last.totalTokens, 5);
    });
  });
}
