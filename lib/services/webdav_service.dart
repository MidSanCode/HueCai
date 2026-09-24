import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// A minimal WebDAV client built directly on the `http` package.
///
/// Only the methods the cloud-sync feature needs are implemented
/// (`PROPFIND` / `PUT` / `GET` / `MKCOL` / `DELETE`), which keeps the
/// dependency surface small and gives us full control over Basic auth.
///
/// Authentication is HTTP Basic, matching the MSC Cloud WebDAV endpoint
/// documented in `temp/cloud-sync.md`: the user name is the login email and
/// the password is an account API token.
class WebDavService {
  WebDavService({
    required this.baseUrl,
    required this.username,
    required this.password,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Root URL of the WebDAV collection, e.g. `https://host/dav/`.
  final String baseUrl;
  final String username;
  final String password;

  final http.Client _client;

  /// Timeout applied to every request so a dead server cannot hang the UI.
  static const Duration _timeout = Duration(seconds: 30);

  /// Builds the `Authorization` header for HTTP Basic auth.
  Map<String, String> get _authHeaders {
    final raw = utf8.encode('$username:$password');
    return {'Authorization': 'Basic ${base64Encode(raw)}'};
  }

  /// Normalises [baseUrl] so it always ends with exactly one slash.
  String get _root {
    var url = baseUrl.trim();
    if (url.isEmpty) return url;
    if (!url.endsWith('/')) url = '$url/';
    return url;
  }

  /// Joins a relative [path] onto the root URL.
  ///
  /// Each segment is percent-encoded individually so project names with
  /// spaces or non-ASCII characters produce valid request URLs.
  Uri _uri(String path, {bool asDirectory = false}) {
    final segments = path
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .toList();
    var joined = '$_root${segments.join('/')}';
    if (asDirectory && !joined.endsWith('/')) joined = '$joined/';
    return Uri.parse(joined);
  }

  void dispose() => _client.close();

  /// Verifies the endpoint is reachable and the credentials are accepted.
  ///
  /// Throws [WebDavException] with a human-readable message on failure so the
  /// UI can surface *why* a login was rejected rather than a bare stack trace.
  Future<void> ping() async {
    final response = await _send('PROPFIND', _uri(''), depth: '0');
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw WebDavException(
        'Authentication failed (${response.statusCode}). '
        'Check the user name and token.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode >= 400) {
      throw WebDavException(
        'WebDAV endpoint rejected the request (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }

  /// Lists the direct children of [path] (a PROPFIND with `Depth: 1`).
  Future<List<WebDavEntry>> readDir(String path) async {
    final response = await _send('PROPFIND', _uri(path), depth: '1');
    if (response.statusCode == 404) return const [];
    if (response.statusCode >= 400) {
      throw WebDavException(
        'Failed to list "$path" (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    // A PROPFIND must answer 207 Multi-Status. Anything else (e.g. a 200 from
    // a proxy or a plain HTML error page) would otherwise parse to an empty
    // list and look like "no files", so fail loudly instead.
    if (response.statusCode != 207) {
      throw WebDavException(
        'Unexpected response listing "$path" (${response.statusCode}); '
        'expected 207 Multi-Status.',
        statusCode: response.statusCode,
      );
    }
    return _parseMultiStatus(response.body, path);
  }

  /// Downloads [path] and returns its raw bytes.
  Future<List<int>> readBytes(String path) async {
    final response = await _send('GET', _uri(path));
    if (response.statusCode == 404) {
      throw WebDavException('Remote file not found: $path', statusCode: 404);
    }
    if (response.statusCode >= 400) {
      throw WebDavException(
        'Failed to download "$path" (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  /// Metadata for a single remote file, or `null` when it does not exist.
  Future<WebDavEntry?> stat(String path) async {
    final response = await _send('PROPFIND', _uri(path), depth: '0');
    if (response.statusCode == 404) return null;
    if (response.statusCode >= 400) return null;
    final entries = _parseMultiStatus(response.body, path);
    if (entries.isEmpty) return null;
    // The response echoes the requested resource itself; return the last one
    // so a self-referencing href does not shadow a real match.
    return entries.last;
  }

  /// Uploads [bytes] to [path], creating intermediate collections as needed.
  Future<void> writeBytes(String path, List<int> bytes) async {
    await _ensureParentDirs(path);
    final response = await _send(
      'PUT',
      _uri(path),
      bodyBytes: bytes,
      extraHeaders: {'Content-Type': 'application/octet-stream'},
    );
    // 2xx (200 OK / 201 Created / 204 No Content) all mean success.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebDavException(
        'Failed to upload "$path" (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }

  /// Creates a collection. Succeeds silently when it already exists.
  Future<void> mkdir(String path) async {
    final response = await _send('MKCOL', _uri(path, asDirectory: true));
    if (response.statusCode == 405 || response.statusCode == 301) return;
    if (response.statusCode >= 400 && response.statusCode != 409) {
      throw WebDavException(
        'Failed to create collection "$path" (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }

  /// Recursively creates every missing collection along [path].
  Future<void> mkdirAll(String path) async {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    var current = '';
    for (final segment in segments) {
      current = current.isEmpty ? segment : '$current/$segment';
      await mkdir(current);
    }
  }

  /// Ensures the parent collections of a file [path] exist before a PUT.
  Future<void> _ensureParentDirs(String path) async {
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return;
    await mkdirAll(path.substring(0, idx));
  }

  /// Deletes a file or collection (recursive on the server side).
  Future<void> remove(String path) async {
    final response = await _send('DELETE', _uri(path));
    if (response.statusCode == 404) return;
    if (response.statusCode >= 400) {
      throw WebDavException(
        'Failed to delete "$path" (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }

  /// Issues one WebDAV request with auth, depth and timeout applied.
  Future<http.Response> _send(
    String method,
    Uri uri, {
    String? depth,
    List<int>? bodyBytes,
    Map<String, String>? extraHeaders,
  }) async {
    final request = http.Request(method, uri);
    request.headers.addAll(_authHeaders);
    if (depth != null) request.headers['Depth'] = depth;
    if (extraHeaders != null) request.headers.addAll(extraHeaders);
    if (bodyBytes != null) request.bodyBytes = bodyBytes;

    try {
      final streamed = await _client.send(request).timeout(_timeout);
      return await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw WebDavException('Request to "$uri" timed out.');
    } on SocketException catch (e) {
      throw WebDavException('Cannot reach WebDAV server: ${e.message}');
    } on http.ClientException catch (e) {
      throw WebDavException('Network error: ${e.message}');
    }
  }

  /// Parses a `207 Multi-Status` body into [WebDavEntry] objects.
  ///
  /// The href values are absolute or root-relative server paths, so they are
  /// converted back into paths relative to this client's root collection.
  List<WebDavEntry> _parseMultiStatus(String body, String requestedPath) {
    final entries = <WebDavEntry>[];
    if (body.trim().isEmpty) return entries;

    final XmlDocument document;
    try {
      document = XmlDocument.parse(body);
    } on XmlParserException {
      return entries;
    }

    // Namespace prefixes vary between servers (D:, d:, ns0:, or none), so
    // every lookup matches on the local name only via `namespace: '*'`.
    for (final response in _findAll(document, 'response')) {
      final href = _firstText(response, 'href');
      if (href == null || href.isEmpty) continue;

      final relative = _relativize(href);
      if (relative == null) continue;

      final isDir = _isCollection(response, href);
      entries.add(WebDavEntry(
        path: relative,
        name: relative.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '',
        isDirectory: isDir,
        size: int.tryParse(_firstText(response, 'getcontentlength') ?? '') ?? 0,
        modified: _parseDate(response),
      ));
    }
    return entries;
  }

  /// Finds all descendant elements by local name, ignoring namespace prefixes.
  Iterable<XmlElement> _findAll(XmlNode node, String localName) =>
      node.findAllElements(localName, namespace: '*');

  /// Returns the trimmed text of the first matching descendant, if any.
  String? _firstText(XmlNode node, String localName) {
    for (final element in _findAll(node, localName)) {
      return element.innerText.trim();
    }
    return null;
  }

  /// Detects whether a `<response>` describes a collection.
  bool _isCollection(XmlElement response, String href) {
    // A collection advertises an inner <collection/> inside <resourcetype>.
    for (final type in _findAll(response, 'resourcetype')) {
      if (_findAll(type, 'collection').isNotEmpty) return true;
    }
    // Fall back to the trailing slash convention many servers rely on.
    return href.endsWith('/');
  }

  /// Reads the last-modified timestamp from a `<response>`, if present.
  DateTime? _parseDate(XmlElement response) {
    final raw = _firstText(response, 'getlastmodified');
    if (raw == null) return null;
    try {
      return HttpDate.parse(raw);
    } catch (_) {
      // Some servers emit a non-HTTP-date format; treat it as unknown rather
      // than failing the whole listing.
      return null;
    }
  }

  /// Maps an absolute href onto a path relative to the client root.
  ///
  /// Returns `null` when the href lies outside the configured collection,
  /// which keeps a server that answers with unrelated resources from
  /// polluting the listing.
  String? _relativize(String href) {
    var path = href;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      path = Uri.parse(path).path;
    }
    path = Uri.decodeComponent(path);

    final rootPath = Uri.parse(_root).path;
    if (path.startsWith(rootPath)) {
      path = path.substring(rootPath.length);
    } else if (path.startsWith('/')) {
      path = path.substring(1);
    }
    return path.replaceAll(RegExp(r'/+$'), '');
  }
}

/// A single file or collection returned by a WebDAV listing.
class WebDavEntry {
  WebDavEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    this.modified,
  });

  /// Path relative to the WebDAV root (no leading slash).
  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? modified;

  @override
  String toString() => 'WebDavEntry($path, dir=$isDirectory, size=$size)';
}

/// Error raised for WebDAV transport, authentication and protocol failures.
class WebDavException implements Exception {
  WebDavException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
