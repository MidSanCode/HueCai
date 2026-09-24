import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Service for interacting with the MSC Cloud Sync API.
/// Uses cookie + CSRF-token based auth; cookies are tracked in memory.
class CloudSyncService {
  final String baseUrl;
  final http.Client _client = http.Client();
  final Map<String, String> _cookies = {};
  String? _csrfToken;

  CloudSyncService({this.baseUrl = 'https://cloud.midsancode.dpdns.org'});

  /// Updates the internal CSRF token and session cookies.
  /// Must be called after login or periodically to refresh tokens.
  Future<void> refreshSession() async {
    final response = await _request('GET', '/api/me');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _csrfToken = data['csrf'] as String?;
    }
  }

  /// Public wrapper around the cookie/CSRF-aware request helper.
  Future<http.Response> request(
    String method,
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    List<int>? bytes,
    String? query,
  }) {
    return _request(method, path,
        headers: headers, body: body, bytes: bytes, query: query);
  }

  /// Developer login that captures the session cookie + CSRF token.
  Future<http.Response> devLogin(String email, String name) {
    return _request('POST', '/api/auth/dev-login',
        body: {'email': email, 'name': name});
  }

  /// Generic request wrapper that handles cookies and CSRF tokens.
  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    List<int>? bytes,
    String? query,
  }) async {
    final url = Uri.parse('$baseUrl$path${query != null ? '?$query' : ''}');
    final reqHeaders = {
      'Content-Type': 'application/json',
      ..._getCookieHeaders(),
    };
    if (method != 'GET' && _csrfToken != null) {
      reqHeaders['X-CSRF-Token'] = _csrfToken!;
    }
    if (headers != null) reqHeaders.addAll(headers);

    final request = http.Request(method, url);
    request.headers.addAll(reqHeaders);

    if (bytes != null) {
      request.bodyBytes = bytes;
    } else if (body != null) {
      request.body = jsonEncode(body);
    }

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    // Capture any session cookies set by the server.
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null) {
      _captureCookies(setCookie);
    }

    return response;
  }

  /// Parses a `set-cookie` header value and stores name=value pairs.
  void _captureCookies(String setCookieHeader) {
    for (final part in setCookieHeader.split(',')) {
      final first = part.trim().split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq > 0) {
        final name = first.substring(0, eq).trim();
        final value = first.substring(eq + 1).trim();
        if (name.isNotEmpty) _cookies[name] = value;
      }
    }
  }

  Map<String, String> _getCookieHeaders() {
    if (_cookies.isEmpty) return {};
    final joined = _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    return {'Cookie': joined};
  }

  /// Lists files in the cloud for the current user.
  Future<List<CloudObject>> listFiles({String prefix = ''}) async {
    final response = await _request('GET', '/api/services/cloudsync/files',
        query: 'prefix=$prefix');
    if (response.statusCode != 200) throw Exception('Failed to list files: ${response.body}');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final objects = data['objects'] as List;
    return objects.map((o) => CloudObject.fromJson(o as Map<String, dynamic>)).toList();
  }

  /// - Step 1: Request an S3 upload policy.
  Future<UploadRequest> uploadRequest(String name, int size) async {
    final response = await _request('POST', '/api/services/cloudsync/upload-request',
        body: {'name': name, 'size': size});
    if (response.statusCode != 200) throw Exception('Upload request failed: ${response.body}');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return UploadRequest.fromJson(data);
  }

  /// - Step 2: Perform the actual upload to S3.
  Future<void> uploadToS3(UploadRequest req, File file) async {
    final request = http.MultipartRequest('POST', Uri.parse(req.url));
    req.formData.forEach((k, v) => request.fields[k] = v);
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('S3 upload failed: ${response.statusCode}');
    }
  }

  /// - Step 3: Confirm the upload on the server.
  Future<void> confirmUpload(String key) async {
    final response = await _request('POST', '/api/services/cloudsync/confirm-upload',
        body: {'key': key});
    if (response.statusCode != 200) throw Exception('Confirm upload failed: ${response.body}');
  }

  /// Downloads a file from the cloud via a pre-signed URL.
  Future<void> downloadFile(String key, String localPath) async {
    final response = await _request('POST', '/api/services/cloudsync/download-request',
        body: {'key': key});
    if (response.statusCode != 200) throw Exception('Download request failed: ${response.body}');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final url = data['url'] as String;

    final fileResponse = await http.get(Uri.parse(url));
    if (fileResponse.statusCode == 200) {
      final file = File(localPath);
      await file.writeAsBytes(fileResponse.bodyBytes);
    } else {
      throw Exception('S3 download failed: ${fileResponse.statusCode}');
    }
  }

  /// Deletes an object or directory from the cloud.
  Future<void> deleteObject(String key) async {
    final response = await _request('DELETE', '/api/services/cloudsync/objects',
        body: {'key': key});
    if (response.statusCode != 200) throw Exception('Delete failed: ${response.body}');
  }

  /// Requests the current user's storage quota.
  Future<Map<String, dynamic>> getQuota() async {
    final response = await _request('GET', '/api/services/cloudsync/quota');
    if (response.statusCode != 200) throw Exception('Quota request failed: ${response.body}');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

class CloudObject {
  final String key;
  final String name;
  final int size;
  final String modified; // ISO8601 string
  final bool isDir;

  CloudObject({required this.key, required this.name, required this.size, required this.modified, required this.isDir});

  factory CloudObject.fromJson(Map<String, dynamic> json) => CloudObject(
    key: json['key'] as String,
    name: json['name'] as String,
    size: (json['size'] as num).toInt(),
    modified: json['modified'] as String,
    isDir: json['isDir'] as bool,
  );
}

class UploadRequest {
  final String url;
  final Map<String, String> formData;
  final String key;

  UploadRequest({required this.url, required this.formData, required this.key});

  factory UploadRequest.fromJson(Map<String, dynamic> json) => UploadRequest(
    url: json['url'] as String,
    formData: (json['formData'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString())),
    key: json['key'] as String,
  );
}