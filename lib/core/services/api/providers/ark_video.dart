part of '../chat_api_service.dart';

/// Creates and polls an Ark-compatible video generation task
/// (Seedance and relays exposing the same contents/generations/tasks API).
///
/// content[] item roles follow the Ark video API:
/// - 1 image  -> first_frame
/// - 2 images -> first_frame + last_frame
/// - 3+       -> first_frame + reference_image for the rest
Stream<ChatStreamChunk> _sendArkVideoStream(
  http.Client client,
  ProviderConfig config,
  String modelId,
  List<Map<String, dynamic>> messages, {
  List<String>? userImagePaths,
  Map<String, String>? extraHeaders,
  Map<String, dynamic>? extraBody,
}) async* {
  final prompt = await _lastOpenAIImagePrompt(messages);
  final imageUrls = await _arkVideoImageUrls(messages, userImagePaths);
  if (prompt.isEmpty && imageUrls.isEmpty) {
    throw const FormatException(
      'Video generation requires a prompt or at least one image.',
    );
  }

  final contentItems = <Map<String, dynamic>>[
    if (prompt.isNotEmpty) {'type': 'text', 'text': prompt},
    for (var i = 0; i < imageUrls.length; i++)
      {
        'type': 'image_url',
        'image_url': {'url': imageUrls[i]},
        'role': i == 0
            ? 'first_frame'
            : (imageUrls.length == 2 && i == 1
                  ? 'last_frame'
                  : 'reference_image'),
      },
  ];

  final body = <String, dynamic>{
    'model': _apiModelId(config, modelId),
    'content': contentItems,
  };
  final custom = _customBody(config, modelId);
  if (custom.isNotEmpty) body.addAll(custom);
  if (extraBody != null && extraBody.isNotEmpty) {
    extraBody.forEach((key, value) {
      body[key] = value is String ? _parseOverrideValue(value) : value;
    });
  }

  final headers = <String, String>{
    'Authorization': 'Bearer ${_apiKeyForRequest(config, modelId)}',
    'Content-Type': 'application/json',
    ..._customHeaders(config, modelId),
    if (extraHeaders != null) ...extraHeaders,
  };

  final createResponse = await client.post(
    _openAIImagesUrl(config, '/contents/generations/tasks'),
    headers: headers,
    body: jsonEncode(body),
  );
  if (createResponse.statusCode < 200 || createResponse.statusCode >= 300) {
    throw HttpException(
      'HTTP ${createResponse.statusCode}: ${createResponse.body}',
    );
  }
  final created = jsonDecode(createResponse.body);
  final taskId =
      (created is Map ? (created['id'] ?? created['task_id']) : null)
          ?.toString()
          .trim() ??
      '';
  if (taskId.isEmpty) {
    throw const FormatException('Video generation API returned no task id.');
  }

  final pollHeaders = Map<String, String>.of(headers)
    ..removeWhere((key, _) => key.toLowerCase() == 'content-type');
  final deadline = DateTime.now().add(const Duration(minutes: 15));
  var intervalSeconds = 3;
  const maxIntervalSeconds = 10;

  while (true) {
    await Future<void>.delayed(Duration(seconds: intervalSeconds));
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'Video generation task $taskId timed out.',
        const Duration(minutes: 15),
      );
    }

    final http.Response response;
    try {
      response = await client.get(
        _openAIImagesUrl(config, '/contents/generations/tasks/$taskId'),
        headers: pollHeaders,
      );
    } on http.ClientException {
      // Surface stop/cancel immediately.
      rethrow;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 429 || response.statusCode >= 500) {
        continue;
      }
      throw HttpException('HTTP ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException(
        'Video generation task returned a non-object body.',
      );
    }
    final status = (decoded['status'] ?? '').toString();
    if (status == 'succeeded') {
      final content = decoded['content'];
      final videoUrl =
          (content is Map
                  ? (content['video_url'] ?? content['file_url'])
                  : null)
              ?.toString()
              .trim() ??
          '';
      if (videoUrl.isEmpty) {
        throw const FormatException(
          'Video generation task succeeded without a video URL.',
        );
      }
      final localPath = await _downloadArkVideo(
        client,
        videoUrl,
        headers: pollHeaders,
      );
      final usage = _arkVideoUsage(decoded.cast<String, dynamic>());
      yield ChatStreamChunk(
        content: '[video:${localPath ?? videoUrl}]',
        isDone: true,
        totalTokens: usage?.totalTokens ?? 0,
        usage: usage,
      );
      return;
    }
    if (status == 'failed' || status == 'cancelled') {
      final err = decoded['error'];
      final message = err is Map
          ? ((err['message'] ?? err['code']) ?? 'unknown error').toString()
          : (err?.toString() ?? 'unknown error');
      throw FormatException('Video generation task $status: $message');
    }
    if (intervalSeconds < maxIntervalSeconds) {
      intervalSeconds = intervalSeconds + 2 > maxIntervalSeconds
          ? maxIntervalSeconds
          : intervalSeconds + 2;
    }
  }
}

Future<List<String>> _arkVideoImageUrls(
  List<Map<String, dynamic>> messages,
  List<String>? userImagePaths,
) async {
  final input = await _openAIImagesInput(messages, userImagePaths);
  final urls = <String>[];
  for (final ref in input.imageRefs.take(7)) {
    switch (ref.kind) {
      case 'url':
      case 'data':
        urls.add(ref.src);
        break;
      default:
        final fixed = SandboxPathResolver.fix(ref.src);
        final bytes = await File(fixed).readAsBytes();
        final mime = _mimeFromPath(fixed);
        urls.add('data:$mime;base64,${base64Encode(bytes)}');
    }
  }
  return urls;
}

TokenUsage? _arkVideoUsage(Map<String, dynamic> decoded) {
  final usage = decoded['usage'];
  if (usage is! Map) return null;
  final total =
      (usage['total_tokens'] ?? usage['completion_tokens'] ?? 0) as int? ?? 0;
  return TokenUsage(
    promptTokens: 0,
    completionTokens: total,
    totalTokens: total,
  );
}

Future<String?> _downloadArkVideo(
  http.Client client,
  String rawUrl, {
  required Map<String, String> headers,
}) async {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return null;
  }
  try {
    final requestHeaders = Map<String, String>.of(headers)
      ..removeWhere((key, _) => key.toLowerCase() == 'content-type')
      ..['Accept'] = 'video/*';
    final response = await client.get(uri, headers: requestHeaders);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        response.bodyBytes.isEmpty) {
      return null;
    }
    var ext = 'mp4';
    final path = uri.path.toLowerCase();
    for (final candidate in const ['mp4', 'mov', 'webm', 'm4v']) {
      if (path.endsWith('.$candidate')) {
        ext = candidate;
        break;
      }
    }
    return AppDirectories.saveVideoBytes(response.bodyBytes, ext: ext);
  } catch (_) {
    return null;
  }
}
