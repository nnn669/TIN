import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:tin/core/providers/settings_provider.dart';
import 'package:tin/core/services/api/chat_api_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => '$path/cache';

  @override
  Future<String?> getTemporaryPath() async => '$path/tmp';
}

ProviderConfig _config(String baseUrl) {
  return ProviderConfig(
    id: 'ArkVideoTest',
    enabled: true,
    name: 'ArkVideoTest',
    apiKey: 'test-key',
    baseUrl: baseUrl,
    providerType: ProviderKind.openai,
  );
}

void main() {
  group('Ark video generation routing', () {
    test('detects seedance models and override-flagged models', () {
      final plain = _config('https://ark.example/api/v3');
      expect(
        ChatApiService.supportsArkVideoGeneration(
          plain,
          'doubao-seedance-2-5-260628',
        ),
        isTrue,
      );
      expect(
        ChatApiService.supportsArkVideoGeneration(plain, 'seedance-2.5'),
        isTrue,
      );
      expect(
        ChatApiService.supportsArkVideoGeneration(plain, 'gpt-image-2'),
        isFalse,
      );

      final flagged = ProviderConfig(
        id: 'ArkVideoTest',
        enabled: true,
        name: 'ArkVideoTest',
        apiKey: 'test-key',
        baseUrl: 'https://ark.example/api/v3',
        providerType: ProviderKind.openai,
        modelOverrides: const {
          'my-video-model': {'videoGeneration': true},
        },
      );
      expect(
        ChatApiService.supportsArkVideoGeneration(flagged, 'my-video-model'),
        isTrue,
      );
      expect(
        ChatApiService.supportsArkVideoGeneration(flagged, 'other-model'),
        isFalse,
      );
    });

    test(
      'creates task, polls and downloads the video locally',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'kelivo_ark_video_',
        );
        final previousPathProvider = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
        addTearDown(() async {
          PathProviderPlatform.instance = previousPathProvider;
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });

        final firstFrame = File('${tempDir.path}/first.png');
        await firstFrame.writeAsBytes(const [1, 2, 3, 4]);
        final lastFrame = File('${tempDir.path}/last.png');
        await lastFrame.writeAsBytes(const [5, 6, 7, 8]);

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });

        var pollCount = 0;
        Map<String, dynamic>? createBody;
        server.listen((request) async {
          if (request.method == 'POST' &&
              request.uri.path == '/v1/contents/generations/tasks') {
            createBody =
                jsonDecode(await utf8.decoder.bind(request).join())
                    as Map<String, dynamic>;
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'id': 'cgt-test-1'}));
            await request.response.close();
            return;
          }
          if (request.uri.path == '/v1/contents/generations/tasks/cgt-test-1') {
            pollCount += 1;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(
                pollCount == 1
                    ? {'status': 'queued'}
                    : {
                        'status': 'succeeded',
                        'content': {
                          'video_url':
                              'http://${server.address.address}:${server.port}/result.mp4',
                        },
                        'usage': {'total_tokens': 4321},
                      },
              ),
            );
            await request.response.close();
            return;
          }
          if (request.uri.path == '/result.mp4') {
            request.response.add([9, 9, 8, 8]);
            await request.response.close();
            return;
          }
          request.response.statusCode = 404;
          await request.response.close();
        });

        final chunks = await ChatApiService.sendMessageStream(
          config: _config('http://${server.address.address}:${server.port}/v1'),
          modelId: 'doubao-seedance-2-5-260628',
          messages: const [
            {'role': 'user', 'content': 'a cat runs'},
          ],
          userImagePaths: [firstFrame.path, lastFrame.path],
        ).toList();

        expect(createBody?['model'], 'doubao-seedance-2-5-260628');
        final content = createBody?['content'] as List;
        expect(content, hasLength(3));
        expect(content[0]['type'], 'text');
        expect(content[0]['text'], 'a cat runs');
        expect(content[1]['role'], 'first_frame');
        expect(
          (content[1]['image_url'] as Map)['url'],
          startsWith('data:image/png;base64,'),
        );
        expect(content[2]['role'], 'last_frame');

        expect(chunks, hasLength(1));
        expect(chunks.single.usage?.totalTokens, 4321);
        final videoPath = RegExp(
          r'\[video:([^\]]+)\]',
        ).firstMatch(chunks.single.content)!.group(1)!;
        expect(videoPath.endsWith('.mp4'), isTrue);
        expect(await File(videoPath).readAsBytes(), const [9, 9, 8, 8]);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('throws when the task fails', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      var polled = false;
      server.listen((request) async {
        if (request.method == 'POST') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'id': 'cgt-fail-1'}));
          await request.response.close();
          return;
        }
        if (polled) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'status': 'failed',
              'error': {'message': 'content policy violation'},
            }),
          );
          await request.response.close();
          return;
        }
        polled = true;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'status': 'running'}));
        await request.response.close();
      });

      await expectLater(
        ChatApiService.sendMessageStream(
          config: _config('http://${server.address.address}:${server.port}/v1'),
          modelId: 'seedance-2.0-fast',
          messages: const [
            {'role': 'user', 'content': 'draw a cat'},
          ],
        ).toList(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('content policy violation'),
          ),
        ),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
