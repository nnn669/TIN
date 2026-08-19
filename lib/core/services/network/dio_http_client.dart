import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:http/http.dart' as http;
import 'package:socks5_proxy/socks_client.dart' as socks;

import 'request_logger.dart';

Future<InternetAddress?> _resolveProxyAddress(String host) async {
  final parsed = InternetAddress.tryParse(host);
  if (parsed != null) return parsed;
  try {
    final list = await InternetAddress.lookup(host);
    return list.isNotEmpty ? list.first : null;
  } catch (_) {
    return null;
  }
}

ConnectionTask<Socket> _directConnection(Uri uri, SecurityContext? context) {
  if (uri.scheme == 'https') {
    final Future<SecureSocket> socket = SecureSocket.connect(uri.host, uri.port, context: context);
    return ConnectionTask.fromSocket(socket, () async => (await socket).close());
  }
  final Future<Socket> socket = Socket.connect(uri.host, uri.port);
  return ConnectionTask.fromSocket(socket, () async => (await socket).close());
}

Stream<List<int>> _normalizeStreamingResponse(Stream<List<int>> source, {required bool requestedEventStream, required bool responseIsJson}) async* {
  if (!requestedEventStream || !responseIsJson) {
    yield* source;
    return;
  }
  var started = false;
  await for (final chunk in source) {
    if (!started) {
      started = true;
      yield utf8.encode('data: ');
    }
    yield chunk;
  }
  if (started) yield utf8.encode('\n\n');
}

class NetworkProxyConfig {
  final bool enabled;
  final String type;
  final String host;
  final int port;
  final String? username;
  final String? password;

  const NetworkProxyConfig({required this.enabled, this.type = 'http', required this.host, required this.port, this.username, this.password});
  bool get isValid => enabled && host.trim().isNotEmpty && port > 0;
}

class DioHttpClient extends http.BaseClient {
  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _sendTimeout = Duration(seconds: 20);
  static const Duration _receiveTimeout = Duration(seconds: 45);
  static const Duration _socketIdleTimeout = Duration(seconds: 45);

  DioHttpClient({this._proxy, CancelToken? cancelToken})
    : _cancelToken = cancelToken ?? CancelToken(),
      _dio = Dio(BaseOptions(connectTimeout: _connectTimeout, sendTimeout: _sendTimeout, receiveTimeout: _receiveTimeout, validateStatus: (_) => true)) {
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.connectionTimeout = _connectTimeout;
        client.idleTimeout = _socketIdleTimeout;
        if (_proxy?.isValid == true) {
          final p = _proxy!;
          if (p.type == 'socks5') {
            Future<InternetAddress?>? proxyAddrFuture;
            client.connectionFactory = (uri, proxyHost, proxyPort) async {
              proxyAddrFuture ??= _resolveProxyAddress(p.host);
              final proxyAddr = await proxyAddrFuture;
              if (proxyAddr == null) return _directConnection(uri, null);
              final proxies = <socks.ProxySettings>[socks.ProxySettings(proxyAddr, p.port, username: p.username, password: p.password)];
              final socket = socks.SocksTCPClient.connect(proxies, InternetAddress(uri.host, type: InternetAddressType.unix), uri.port);
              if (uri.scheme == 'https') {
                final Future<SecureSocket> secureSocket;
                return ConnectionTask.fromSocket(secureSocket = (await socket).secure(uri.host), () async => (await secureSocket).close());
              }
              return ConnectionTask.fromSocket(socket, () async => (await socket).close());
            };
          } else {
            client.findProxy = (_) => 'PROXY ${p.host}:${p.port}';
            if (p.username != null && p.username!.trim().isNotEmpty) {
              client.addProxyCredentials(p.host, p.port, '', HttpClientBasicCredentials(p.username!, p.password ?? ''));
            }
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
    try { _dio.close(); } catch (_) {}
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final reqId = RequestLogger.nextRequestId();
    final uri = request.url;
    final method = request.method.toUpperCase();
    final requestStarted = Stopwatch()..start();
    List<int> bodyBytes = const <int>[];
    try { bodyBytes = await request.finalize().toBytes(); } catch (_) {}
    final reqHeaders = Map<String, String>.from(request.headers);
    reqHeaders.putIfAbsent('User-Agent', () => 'TIN');
    if (RequestLogger.enabled) {
      RequestLogger.logLine('[REQ $reqId] $method $uri');
      if (reqHeaders.isNotEmpty) RequestLogger.logLine('[REQ $reqId] headers=${RequestLogger.encodeObject(RequestLogger.redactHeaders(reqHeaders))}');
      if (bodyBytes.isNotEmpty) {
        final decoded = RequestLogger.safeDecodeUtf8(bodyBytes);
        final logged = decoded.isNotEmpty
            ? RequestLogger.redactSensitiveJson(decoded)
            : 'base64:${base64Encode(bodyBytes)}';
        RequestLogger.logLine('[REQ $reqId] body=${RequestLogger.escape(logged)}');
      }
    }
    try {
      if (Platform.isAndroid && uri.scheme.toLowerCase() == 'http') {
        throw http.ClientException(
          'Cleartext HTTP is disabled on Android; use HTTPS.',
          uri,
        );
      }
      final resp = await _dio.request<ResponseBody>(uri.toString(), data: bodyBytes.isEmpty ? null : bodyBytes, options: Options(method: method, headers: reqHeaders, responseType: ResponseType.stream, followRedirects: request.followRedirects, maxRedirects: request.maxRedirects, receiveDataWhenStatusError: true), cancelToken: _cancelToken);
      final statusCode = resp.statusCode ?? 0;
      final headers = <String, String>{};
      resp.headers.forEach((name, values) { if (values.isNotEmpty) headers[name] = values.join(','); });
      final contentType = (headers['content-type'] ?? '').toLowerCase();
      final requestedEventStream = (reqHeaders['Accept'] ?? reqHeaders['accept'] ?? '').toLowerCase().contains('text/event-stream');
      final responseIsJson = contentType.contains('application/json') || contentType.contains('+json');
      if (RequestLogger.enabled) {
        RequestLogger.logLine('[RES $reqId] status=$statusCode headers_ms=${requestStarted.elapsedMilliseconds}');
        if (headers.isNotEmpty) RequestLogger.logLine('[RES $reqId] headers=${RequestLogger.encodeObject(RequestLogger.redactHeaders(headers))}');
        if (requestedEventStream && responseIsJson) RequestLogger.logLine('[RES $reqId] normalized_json_as_sse=true');
      }
      final body = resp.data!;
      final int? contentLength = body.contentLength >= 0 ? body.contentLength : null;
      final normalizedStream = _normalizeStreamingResponse(body.stream, requestedEventStream: requestedEventStream, responseIsJson: responseIsJson);
      final controller = StreamController<List<int>>(sync: true);
      StreamSubscription<List<int>>? bodySubscription;
      var sawBodyBytes = false;
      Timer? idleTimer;
      void armIdleTimer() {
        idleTimer?.cancel();
        idleTimer = Timer(_receiveTimeout, () {
          bodySubscription?.cancel();
          controller.addError(TimeoutException('No response data received within ${_receiveTimeout.inSeconds} seconds'));
          controller.close();
        });
      }
      controller.onListen = () {
        armIdleTimer();
        bodySubscription = normalizedStream.listen((chunk) {
          if (!sawBodyBytes && chunk.isNotEmpty) {
            sawBodyBytes = true;
            if (RequestLogger.enabled) RequestLogger.logLine('[RES $reqId] first_byte_ms=${requestStarted.elapsedMilliseconds}');
          }
          armIdleTimer();
          controller.add(chunk);
          if (RequestLogger.enabled && RequestLogger.saveOutput) {
            final s = RequestLogger.safeDecodeUtf8(chunk);
            if (s.isNotEmpty) {
              final logged = RequestLogger.redactSensitiveJson(s);
              RequestLogger.logLine('[RES $reqId] chunk=${RequestLogger.escape(logged)}');
            }
          }
        }, onError: (Object e, StackTrace st) {
          idleTimer?.cancel();
          if (RequestLogger.enabled) RequestLogger.logLine('[RES $reqId] error=${RequestLogger.escape(e.toString())}');
          controller.addError(e, st);
          controller.close();
        }, onDone: () {
          idleTimer?.cancel();
          if (RequestLogger.enabled) RequestLogger.logLine('[RES $reqId] done_ms=${requestStarted.elapsedMilliseconds}');
          controller.close();
        }, cancelOnError: false);
      };
      controller.onPause = () => bodySubscription?.pause();
      controller.onResume = () => bodySubscription?.resume();
      controller.onCancel = () { idleTimer?.cancel(); bodySubscription?.cancel(); };
      return http.StreamedResponse(http.ByteStream(controller.stream), statusCode, contentLength: responseIsJson && requestedEventStream ? null : contentLength, request: request, headers: headers, isRedirect: resp.isRedirect, reasonPhrase: resp.statusMessage);
    } on DioException catch (e) {
      if (RequestLogger.enabled) RequestLogger.logLine('[RES $reqId] dio_error=${RequestLogger.escape(e.toString())}');
      throw http.ClientException(e.toString(), uri);
    } catch (e) {
      if (RequestLogger.enabled) RequestLogger.logLine('[RES $reqId] error=${RequestLogger.escape(e.toString())}');
      throw http.ClientException(e.toString(), uri);
    }
  }
}