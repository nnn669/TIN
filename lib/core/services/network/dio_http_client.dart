import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:http/http.dart' as http;

import 'request_logger.dart';

class NetworkProxyConfig {
  final bool enabled;
  final String host;
  final int port;
  final String? username;
  final String? password;

  const NetworkProxyConfig({
    required this.enabled,
    required this.host,
    required this.port,
    this.username,
    this.password,
  });

  bool get isValid => enabled && host.trim().isNotEmpty && port > 0;
}

class DioHttpClient extends http.BaseClient {
  DioHttpClient({
    NetworkProxyConfig? proxy,
    CancelToken? cancelToken,
  })  : _proxy = proxy,
        _cancelToken = cancelToken ?? CancelToken(),
        _dio = Dio(
          BaseOptions(
            connectTimeout: null,
            sendTimeout: null,
            receiveTimeout: null,
            validateStatus: (_) => true,
          ),
        ) {
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.connectionTimeout = null;
        client.idleTimeout = const Duration(days: 3650);
        if (_proxy?.isValid == true) {
          final p = _proxy!;
          client.findProxy = (_) => 'PROXY ${p.host}:${p.port}';
          if (p.username != null && p.username!.trim().isNotEmpty) {
            client.addProxyCredentials(
              p.host,
              p.port,
              '',
              HttpClientBasicCredentials(p.username!, p.password ?? ''),
            );
          }
        }
        return client;
      },
    );
  }

  final Dio _dio;
  final NetworkProxyConfig? _proxy;
  final CancelToken _cancelToken;

  @override
  void close() {
    try {
      if (!_cancelToken.isCancelled) {
        _cancelToken.cancel('closed');
      }
    } catch (_) {}
    try {
      _dio.close(force: true);
    } catch (_) {}
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final reqId = RequestLogger.nextRequestId();
    final uri = request.url;
    final method = request.method.toUpperCase();

    List<int> bodyBytes = const <int>[];
    try {
      bodyBytes = await request.finalize().toBytes();
    } catch (_) {}

    if (RequestLogger.enabled) {
      RequestLogger.logLine('[REQ $reqId] $method $uri');
      if (request.headers.isNotEmpty) {
        RequestLogger.logLine('[REQ $reqId] headers=${RequestLogger.encodeObject(request.headers)}');
      }
      if (bodyBytes.isNotEmpty) {
        final decoded = RequestLogger.safeDecodeUtf8(bodyBytes);
        final bodyText = decoded.isNotEmpty ? decoded : 'base64:${base64Encode(bodyBytes)}';
        RequestLogger.logLine('[REQ $reqId] body=${RequestLogger.escape(bodyText)}');
      }
    }

    try {
      final resp = await _dio.request<ResponseBody>(
        uri.toString(),
        data: bodyBytes.isEmpty ? null : bodyBytes,
        options: Options(
          method: method,
          headers: request.headers,
          responseType: ResponseType.stream,
          followRedirects: request.followRedirects,
          maxRedirects: request.maxRedirects,
          receiveDataWhenStatusError: true,
        ),
        cancelToken: _cancelToken,
      );

      final statusCode = resp.statusCode ?? 0;
      final headers = <String, String>{};
      resp.headers.forEach((name, values) {
        if (values.isEmpty) return;
        headers[name] = values.join(',');
      });

      if (RequestLogger.enabled) {
        RequestLogger.logLine('[RES $reqId] status=$statusCode');
        if (headers.isNotEmpty) {
          RequestLogger.logLine('[RES $reqId] headers=${RequestLogger.encodeObject(headers)}');
        }
      }

      final body = resp.data!;
      final int? contentLength = (body.contentLength != null && body.contentLength! >= 0) ? body.contentLength : null;
      StreamSubscription<Uint8List>? sub;

      final controller = StreamController<List<int>>(sync: true);
      controller.onListen = () {
        sub = body.stream.listen(
          (chunk) {
            controller.add(chunk);
            if (RequestLogger.enabled) {
              final s = RequestLogger.safeDecodeUtf8(chunk);
              if (s.isNotEmpty) {
                RequestLogger.logLine('[RES $reqId] chunk=${RequestLogger.escape(s)}');
              }
            }
          },
          onError: (e, st) {
            if (RequestLogger.enabled) {
              RequestLogger.logLine('[RES $reqId] error=${RequestLogger.escape(e.toString())}');
            }
            controller.addError(e, st);
            controller.close();
          },
          onDone: () {
            if (RequestLogger.enabled) {
              RequestLogger.logLine('[RES $reqId] done');
            }
            controller.close();
          },
          cancelOnError: false,
        );
      };
      controller.onCancel = () async {
        try {
          if (!_cancelToken.isCancelled) {
            _cancelToken.cancel('cancelled');
          }
        } catch (_) {}
        try {
          await sub?.cancel();
        } catch (_) {}
        try {
          await controller.close();
        } catch (_) {}
      };

      return http.StreamedResponse(
        http.ByteStream(controller.stream),
        statusCode,
        contentLength: contentLength,
        request: request,
        headers: headers,
        isRedirect: resp.isRedirect ?? false,
        reasonPhrase: resp.statusMessage,
      );
    } on DioException catch (e) {
      if (RequestLogger.enabled) {
        RequestLogger.logLine('[RES $reqId] dio_error=${RequestLogger.escape(e.toString())}');
      }
      throw http.ClientException(e.toString(), uri);
    } catch (e) {
      if (RequestLogger.enabled) {
        RequestLogger.logLine('[RES $reqId] error=${RequestLogger.escape(e.toString())}');
      }
      throw http.ClientException(e.toString(), uri);
    }
  }
}
