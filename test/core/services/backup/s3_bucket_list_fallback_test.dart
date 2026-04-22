import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/backup.dart';
import 'package:Kelivo/core/services/backup/s3_client.dart';

S3Config _config(HttpServer server) {
  return S3Config(
    endpoint: 'http://${server.address.address}:${server.port}',
    region: 'us-east-1',
    bucket: 'backup-bucket',
    accessKeyId: 'test-access-key',
    secretAccessKey: 'test-secret-key',
    prefix: 'kelivo_backups',
    pathStyle: true,
  );
}

String _listResultXml() {
  return '''<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Contents>
    <Key>kelivo_backups/kelivo_backup_2026-04-22T10-11-12.123456.zip</Key>
    <LastModified>2026-04-22T10:11:12.123Z</LastModified>
    <Size>128</Size>
  </Contents>
</ListBucketResult>''';
}

String _legacyListResultXml() {
  return '''<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Contents>
    <Key>kelivo_backups/kelivo_backup_2026-04-20T09-00-00.123456.zip</Key>
    <LastModified>2026-04-20T09:00:00.123Z</LastModified>
    <Size>64</Size>
  </Contents>
</ListBucketResult>''';
}

String _noSuchKeyXml() {
  return '''<?xml version="1.0" encoding="UTF-8"?>
<Error>
  <Code>NoSuchKey</Code>
  <Message>The specified key does not exist.</Message>
</Error>''';
}

String _manifestJson() {
  return '''{
  "version": 1,
  "items": [
    {
      "key": "kelivo_backups/kelivo_backup_2026-04-22T10-11-12.123456.zip",
      "displayName": "kelivo_backup_2026-04-22T10-11-12.123456.zip",
      "size": 128,
      "lastModified": "2026-04-22T10:11:12.123Z"
    }
  ]
}''';
}

void main() {
  group('S3 bucket list fallback', () {
    test('test() succeeds when manifest key is missing', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      final seenPaths = <String>[];
      server.listen((request) async {
        seenPaths.add(request.uri.path);
        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.contentType = ContentType(
          'application',
          'xml',
          charset: 'utf-8',
        );
        request.response.write(_noSuchKeyXml());
        await request.response.close();
      });

      await const S3BackupClient().test(_config(server));

      expect(seenPaths, [
        '/backup-bucket/kelivo_backups/.kelivo_backups_manifest.json',
      ]);
    });

    test(
      'listObjects returns manifest items when bucket listing is unavailable',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });

        final seenPaths = <String>[];
        server.listen((request) async {
          seenPaths.add(request.uri.path);
          if (request.uri.path ==
              '/backup-bucket/kelivo_backups/.kelivo_backups_manifest.json') {
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType.json;
            request.response.write(_manifestJson());
          } else if (request.uri.path == '/backup-bucket' ||
              request.uri.path == '/backup-bucket/') {
            request.response.statusCode = HttpStatus.notFound;
            request.response.headers.contentType = ContentType(
              'application',
              'xml',
              charset: 'utf-8',
            );
            request.response.write(_noSuchKeyXml());
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        });

        final items = await const S3BackupClient().listObjects(_config(server));

        expect(items, hasLength(1));
        expect(
          seenPaths,
          contains(
            '/backup-bucket/kelivo_backups/.kelivo_backups_manifest.json',
          ),
        );
      },
    );

    test(
      'listObjects merges manifest items with legacy ListBucket items',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });

        server.listen((request) async {
          if (request.uri.path ==
              '/backup-bucket/kelivo_backups/.kelivo_backups_manifest.json') {
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType.json;
            request.response.write(_manifestJson());
          } else if (request.uri.path == '/backup-bucket') {
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType(
              'application',
              'xml',
              charset: 'utf-8',
            );
            request.response.write(_legacyListResultXml());
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        });

        final items = await const S3BackupClient().listObjects(_config(server));

        expect(items, hasLength(2));
        expect(items.map((e) => e.displayName).toList(), [
          'kelivo_backup_2026-04-22T10-11-12.123456.zip',
          'kelivo_backup_2026-04-20T09-00-00.123456.zip',
        ]);
      },
    );

    test('uploadFile writes manifest object after upload', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      final seenPaths = <String>[];
      String? manifestBody;
      server.listen((request) async {
        seenPaths.add(request.uri.path);
        if (request.method == 'GET' &&
            request.uri.path ==
                '/backup-bucket/kelivo_backups/.kelivo_backups_manifest.json') {
          request.response.statusCode = HttpStatus.notFound;
          request.response.headers.contentType = ContentType(
            'application',
            'xml',
            charset: 'utf-8',
          );
          request.response.write(_noSuchKeyXml());
        } else if (request.method == 'PUT' &&
            request.uri.path == '/backup-bucket/kelivo_backups/demo.zip') {
          await request.drain<void>();
          request.response.statusCode = HttpStatus.ok;
        } else if (request.method == 'PUT' &&
            request.uri.path ==
                '/backup-bucket/kelivo_backups/.kelivo_backups_manifest.json') {
          manifestBody = await utf8.decoder.bind(request).join();
          request.response.statusCode = HttpStatus.ok;
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final tmpDir = await Directory.systemTemp.createTemp(
        'kelivo_s3_manifest_upload_',
      );
      addTearDown(() async {
        if (await tmpDir.exists()) {
          await tmpDir.delete(recursive: true);
        }
      });
      final file = File('${tmpDir.path}/demo.zip');
      await file.writeAsBytes([1, 2, 3]);

      await const S3BackupClient().uploadFile(
        _config(server),
        key: 'kelivo_backups/demo.zip',
        file: file,
      );

      expect(
        seenPaths,
        contains('/backup-bucket/kelivo_backups/.kelivo_backups_manifest.json'),
      );
      expect(manifestBody, contains('"key":"kelivo_backups/demo.zip"'));
    });

    test(
      'listObjects uses primary bucket URL when provider accepts it',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });

        var requestCount = 0;
        final seenPaths = <String>[];
        server.listen((request) async {
          requestCount += 1;
          seenPaths.add(request.uri.path);
          if (request.uri.path ==
              '/backup-bucket/kelivo_backups/.kelivo_backups_manifest.json') {
            request.response.statusCode = HttpStatus.notFound;
            request.response.headers.contentType = ContentType(
              'application',
              'xml',
              charset: 'utf-8',
            );
            request.response.write(_noSuchKeyXml());
          } else {
            expect(request.uri.path, '/backup-bucket');
            expect(request.uri.queryParameters['list-type'], '2');
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType(
              'application',
              'xml',
              charset: 'utf-8',
            );
            request.response.write(_listResultXml());
          }
          await request.response.close();
        });

        final items = await const S3BackupClient().listObjects(_config(server));

        expect(requestCount, 2);
        expect(seenPaths, [
          '/backup-bucket/kelivo_backups/.kelivo_backups_manifest.json',
          '/backup-bucket',
        ]);
        expect(items, hasLength(1));
        expect(
          items.single.displayName,
          'kelivo_backup_2026-04-22T10-11-12.123456.zip',
        );
      },
    );

    test(
      'listObjects retries with trailing slash when primary URL returns NoSuchKey',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });

        final paths = <String>[];
        server.listen((request) async {
          paths.add(request.uri.path);
          if (request.uri.path ==
              '/backup-bucket/kelivo_backups/.kelivo_backups_manifest.json') {
            request.response.statusCode = HttpStatus.notFound;
            request.response.headers.contentType = ContentType(
              'application',
              'xml',
              charset: 'utf-8',
            );
            request.response.write(_noSuchKeyXml());
          } else if (request.uri.path == '/backup-bucket') {
            request.response.statusCode = HttpStatus.notFound;
            request.response.headers.contentType = ContentType(
              'application',
              'xml',
              charset: 'utf-8',
            );
            request.response.write(_noSuchKeyXml());
          } else if (request.uri.path == '/backup-bucket/') {
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType(
              'application',
              'xml',
              charset: 'utf-8',
            );
            request.response.write(_listResultXml());
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        });

        final items = await const S3BackupClient().listObjects(_config(server));

        expect(paths, [
          '/backup-bucket/kelivo_backups/.kelivo_backups_manifest.json',
          '/backup-bucket',
          '/backup-bucket/',
        ]);
        expect(items, hasLength(1));
      },
    );

    test(
      'test() does not fall back to ListBucket when manifest key is missing',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          await server.close(force: true);
        });

        final paths = <String>[];
        server.listen((request) async {
          paths.add(request.uri.path);
          request.response.statusCode = HttpStatus.notFound;
          request.response.headers.contentType = ContentType(
            'application',
            'xml',
            charset: 'utf-8',
          );
          request.response.write(_noSuchKeyXml());
          await request.response.close();
        });

        await const S3BackupClient().test(_config(server));

        expect(paths, [
          '/backup-bucket/kelivo_backups/.kelivo_backups_manifest.json',
        ]);
      },
    );

    test('listObjects preserves non-NoSuchKey failures', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      var requestCount = 0;
      server.listen((request) async {
        requestCount += 1;
        if (request.uri.path ==
            '/backup-bucket/kelivo_backups/.kelivo_backups_manifest.json') {
          request.response.statusCode = HttpStatus.notFound;
          request.response.headers.contentType = ContentType(
            'application',
            'xml',
            charset: 'utf-8',
          );
          request.response.write(_noSuchKeyXml());
        } else {
          request.response.statusCode = HttpStatus.forbidden;
          request.response.headers.contentType = ContentType(
            'application',
            'xml',
            charset: 'utf-8',
          );
          request.response.write('''<?xml version="1.0" encoding="UTF-8"?>
<Error>
  <Code>AccessDenied</Code>
  <Message>Access Denied</Message>
</Error>''');
        }
        await request.response.close();
      });

      await expectLater(
        () => const S3BackupClient().listObjects(_config(server)),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('AccessDenied'),
          ),
        ),
      );
      expect(requestCount, 2);
    });

    test('endpoint that already includes bucket is not duplicated', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      final paths = <String>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        if (request.method == 'GET' &&
            request.uri.path ==
                '/backup-bucket/kelivo_backups/.kelivo_backups_manifest.json') {
          request.response.statusCode = HttpStatus.notFound;
          request.response.headers.contentType = ContentType(
            'application',
            'xml',
            charset: 'utf-8',
          );
          request.response.write(_noSuchKeyXml());
        } else if (request.method == 'PUT') {
          await request.drain<void>();
          request.response.statusCode = HttpStatus.ok;
        } else if (request.method == 'GET') {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType(
            'application',
            'xml',
            charset: 'utf-8',
          );
          request.response.write(_listResultXml());
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final cfg = S3Config(
        endpoint:
            'http://${server.address.address}:${server.port}/backup-bucket',
        region: 'us-east-1',
        bucket: 'backup-bucket',
        accessKeyId: 'test-access-key',
        secretAccessKey: 'test-secret-key',
        prefix: 'kelivo_backups',
        pathStyle: true,
      );

      final tmpDir = await Directory.systemTemp.createTemp(
        'kelivo_s3_endpoint_dedupe_',
      );
      addTearDown(() async {
        if (await tmpDir.exists()) {
          await tmpDir.delete(recursive: true);
        }
      });
      final file = File('${tmpDir.path}/demo.zip');
      await file.writeAsBytes([1, 2, 3]);

      await const S3BackupClient().uploadFile(
        cfg,
        key: 'kelivo_backups/demo.zip',
        file: file,
      );
      await const S3BackupClient().test(cfg);
      await const S3BackupClient().listObjects(cfg);

      expect(
        paths,
        containsAll([
          '/backup-bucket/kelivo_backups/.kelivo_backups_manifest.json',
          '/backup-bucket/kelivo_backups/demo.zip',
          '/backup-bucket',
        ]),
      );
      expect(paths, isNot(contains('/backup-bucket/backup-bucket')));
      expect(
        paths,
        isNot(contains('/backup-bucket/backup-bucket/kelivo_backups/demo.zip')),
      );
    });
  });
}
