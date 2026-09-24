import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hue_cai/services/webdav_service.dart';

/// A request handler that records what was sent and returns a canned response.
class _Recorder {
  final List<http.BaseRequest> requests = [];
  final Map<String, http.Response> responses = {};
  int Function(http.BaseRequest request)? statusFor;
  String Function(http.BaseRequest request)? bodyFor;

  http.Client client() => _MockClient(this);
}

class _MockClient extends http.BaseClient {
  _MockClient(this.recorder);
  final _Recorder recorder;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    recorder.requests.add(request);
    final key = '${request.method} ${request.url.path}';
    final canned = recorder.responses[key];
    final status = canned?.statusCode ??
        recorder.statusFor?.call(request) ??
        200;
    final body = canned?.body ?? recorder.bodyFor?.call(request) ?? '';
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      request: request,
    );
  }
}

/// Multi-Status body shaped like the MSC Cloud WebDAV endpoint returns.
const _multiStatus = '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/</D:href>
    <D:propstat>
      <D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/hue_cai/</D:href>
    <D:propstat>
      <D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/hue_cai/projects/p1/sketch.hcp</D:href>
    <D:propstat>
      <D:prop>
        <D:resourcetype/>
        <D:getcontentlength>2048</D:getcontentlength>
        <D:getlastmodified>Wed, 17 Sep 2026 06:49:33 GMT</D:getlastmodified>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>
''';

void main() {
  group('WebDavService.readDir', () {
    test('parses collections, sizes and timestamps from a Multi-Status', () async {
      final rec = _Recorder()
        ..responses['PROPFIND /dav/hue_cai'] =
            http.Response(_multiStatus, 207);
      final dav = WebDavService(
        baseUrl: 'https://host/dav/',
        username: 'me@example.com',
        password: 'token',
        client: rec.client(),
      );

      final entries = await dav.readDir('hue_cai');

      expect(entries, hasLength(3));
      final dir = entries.firstWhere((e) => e.path == 'hue_cai');
      expect(dir.isDirectory, isTrue);

      final file = entries.firstWhere((e) => e.name == 'sketch.hcp');
      expect(file.isDirectory, isFalse);
      expect(file.path, 'hue_cai/projects/p1/sketch.hcp');
      expect(file.size, 2048);
      expect(file.modified, isNotNull);
    });

    test('rejects a non-Multi-Status reply instead of reporting "no files"',
        () async {
      final rec = _Recorder()
        ..statusFor = ((_) => 200)
        ..bodyFor = ((_) => '<html>proxy error</html>');
      final dav = WebDavService(
        baseUrl: 'https://host/dav/',
        username: 'u',
        password: 'p',
        client: rec.client(),
      );

      await expectLater(
        dav.readDir('hue_cai'),
        throwsA(isA<WebDavException>()
            .having((e) => e.statusCode, 'statusCode', 200)),
      );
    });

    test('sends Basic auth and Depth: 1', () async {
      final rec = _Recorder()
        ..responses['PROPFIND /dav/'] = http.Response(_multiStatus, 207);
      final dav = WebDavService(
        baseUrl: 'https://host/dav',
        username: 'me@example.com',
        password: 'tok',
        client: rec.client(),
      );

      await dav.readDir('');

      final req = rec.requests.single;
      expect(req.method, 'PROPFIND');
      expect(req.headers['Depth'], '1');
      expect(
        req.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('me@example.com:tok'))}',
      );
      // A missing trailing slash must be normalised so the path is valid.
      expect(req.url.path, '/dav/');
    });
  });

  group('WebDavService.writeBytes', () {
    test('creates parent collections then PUTs the bytes', () async {
      final rec = _Recorder()
        // MKCOL on an existing collection commonly answers 405.
        ..responses['MKCOL /dav/hue_cai/'] = http.Response('', 405)
        ..responses['MKCOL /dav/hue_cai/projects/'] = http.Response('', 201)
        ..responses['MKCOL /dav/hue_cai/projects/p1/'] = http.Response('', 201)
        ..responses['PUT /dav/hue_cai/projects/p1/sketch.hcp'] =
            http.Response('', 201);
      final dav = WebDavService(
        baseUrl: 'https://host/dav/',
        username: 'u',
        password: 'p',
        client: rec.client(),
      );

      await dav.writeBytes('hue_cai/projects/p1/sketch.hcp', [1, 2, 3]);

      final methods = rec.requests.map((r) => r.method).toList();
      expect(methods, containsAll(['MKCOL', 'PUT']));
      expect(methods.last, 'PUT');

      final put = rec.requests.last as http.Request;
      expect(put.bodyBytes, [1, 2, 3]);
    });

    test('percent-encodes spaces and non-ASCII in the remote path', () async {
      final rec = _Recorder()
        ..responses['MKCOL /dav/projects/'] = http.Response('', 201)
        ..statusFor = ((_) => 201);
      final dav = WebDavService(
        baseUrl: 'https://host/dav/',
        username: 'u',
        password: 'p',
        client: rec.client(),
      );

      await dav.writeBytes('projects/我的 画.hcp', [0]);

      final put = rec.requests.last;
      // The wire URL must be percent-encoded: no raw space or non-ASCII.
      expect(put.url.toString(), isNot(contains(' ')));
      expect(put.url.toString(), contains('%20'));
      expect(put.url.toString(), contains(Uri.encodeComponent('我的')));
      // Decoding it must round-trip back to the original path.
      expect(Uri.decodeComponent(put.url.path), '/dav/projects/我的 画.hcp');
    });
  });

  group('WebDavService errors', () {
    test('ping reports rejected credentials clearly', () async {
      final rec = _Recorder()..statusFor = (_) => 401;
      final dav = WebDavService(
        baseUrl: 'https://host/dav/',
        username: 'u',
        password: 'wrong',
        client: rec.client(),
      );

      await expectLater(
        dav.ping(),
        throwsA(isA<WebDavException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', contains('Authentication'))),
      );
    });

    test('stat returns null for a missing file', () async {
      final rec = _Recorder()..statusFor = (_) => 404;
      final dav = WebDavService(
        baseUrl: 'https://host/dav/',
        username: 'u',
        password: 'p',
        client: rec.client(),
      );

      expect(await dav.stat('projects/none.hcp'), isNull);
    });

    test('readBytes surfaces a missing file', () async {
      final rec = _Recorder()..statusFor = (_) => 404;
      final dav = WebDavService(
        baseUrl: 'https://host/dav/',
        username: 'u',
        password: 'p',
        client: rec.client(),
      );

      await expectLater(
        dav.readBytes('missing.hcp'),
        throwsA(isA<WebDavException>()),
      );
    });
  });
}
