import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/project.dart';
import '../services/cloud_config_store.dart';
import '../services/lgdf_codec.dart';
import '../services/webdav_service.dart';

/// Outcome of a cloud sync conflict resolution choice.
enum SyncResolution { local, remote, both }

/// Per-project sync status used by the workspace UI.
///
/// [success] / [error] / [idle] map to the three states the UI reports:
/// 已同步 / 同步失败 / 未同步.
enum SyncStatus { idle, syncing, success, error }

/// Result of a completed sync attempt, used to drive user feedback.
enum SyncOutcome { uploaded, downloaded, upToDate, conflictResolved, failed }

/// Manages cloud synchronization state, credentials and per-project status.
///
/// Supports two WebDAV-backed providers:
///  * [CloudProviderKind.customWebDav] — any user-supplied WebDAV server.
///  * [CloudProviderKind.mscCloud] — the built-in MSC Cloud, reached through
///    its `/dav/` WebDAV endpoint using an email + API token.
class CloudSyncProvider with ChangeNotifier {
  CloudSyncProvider({
    this.mscBaseUrl = 'https://cloud.midsancode.dpdns.org',
    CloudConfigStore? store,
  }) : _store = store ?? CloudConfigStore();

  /// Base URL of the built-in MSC Cloud, whose WebDAV endpoint is `/dav/`.
  final String mscBaseUrl;
  final CloudConfigStore _store;

  CloudConfig _config = CloudConfig();
  WebDavService? _dav;

  // Remote account info shown in the UI (populated on a successful connect).
  String? _userName;
  String? _userEmail;
  int? _userId;
  double _usedBytes = 0;
  double _quotaBytes = 0;
  bool _isHealthy = true;

  bool _connecting = false;
  String? _syncErrorMessage;

  String? _syncingProjectId;
  final Map<String, SyncStatus> _projectSyncStatus = {};
  final Map<String, DateTime> _lastSyncedAt = {};

  // ---------------------------------------------------------------- getters

  CloudConfig get config => _config;
  CloudProviderKind? get providerKind => _config.kind;
  bool get hasChosenProvider => _config.kind != null;
  bool get isLoggingIn => _connecting;

  /// True once a provider has been chosen and its credentials are in place.
  bool get isLoggedIn => _dav != null && _config.isConfigured;

  /// MSC account ids only exist for the built-in provider.
  String get userName =>
      _userName ?? _config.username.split('@').firstOrNull ?? 'Cloud';
  String get userEmail => _userEmail ?? _config.username;
  int? get userId => _userId;
  double get usedBytes => _usedBytes;
  double get quotaBytes => _quotaBytes;
  bool get isHealthy => _isHealthy;
  String? get syncingProjectId => _syncingProjectId;
  String? get syncErrorMessage => _syncErrorMessage;

  /// Sync status for a given project id (defaults to idle/未同步).
  SyncStatus statusOf(String projectId) =>
      _projectSyncStatus[projectId] ?? SyncStatus.idle;

  /// When the project last finished a sync successfully, if ever.
  DateTime? lastSyncedAt(String projectId) => _lastSyncedAt[projectId];

  /// Human-readable provider label for status text.
  String get providerLabel {
    switch (_config.kind) {
      case CloudProviderKind.customWebDav:
        return 'Custom WebDAV';
      case CloudProviderKind.mscCloud:
        return 'MSC Cloud';
      case null:
        return 'Not configured';
    }
  }

  /// WebDAV root URL the provider currently resolves to.
  String get resolvedBaseUrl {
    switch (_config.kind) {
      case CloudProviderKind.customWebDav:
        return _config.serverUrl;
      case CloudProviderKind.mscCloud:
        return '$mscBaseUrl/dav/';
      case null:
        return '';
    }
  }

  String get _remoteRoot {
    final base = resolvedBaseUrl;
    if (base.isEmpty) return '';
    final trimmed = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final sub = _config.remotePath.replaceAll(RegExp(r'^/+|/+$'), '');
    return sub.isEmpty ? '$trimmed/' : '$trimmed/$sub/';
  }

  /// Relative key of a project's remote file: `projects/<id>/<name>.hcproj`.
  String _remoteKeyFor(Project project) =>
      'projects/${project.id}/${_sanitize(project.name)}${LgdfCodec.extension}';

  /// Strips characters that are unsafe in a remote path segment.
  String _sanitize(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'untitled' : cleaned;
  }

  // --------------------------------------------------------------- lifecycle

  /// Loads persisted config and silently reconnects when credentials exist.
  Future<void> loadConfig() async {
    _config = await _store.load();
    if (_config.isConfigured) {
      await _connect(silent: true);
    }
    notifyListeners();
  }

  /// Chooses a provider and stores its credentials, then verifies them.
  ///
  /// Returns `true` on success; on failure [syncErrorMessage] explains why
  /// (bad URL, rejected credentials, unreachable host, ...).
  Future<bool> configureProvider(CloudConfig config) async {
    _config = config;
    _syncErrorMessage = null;
    final ok = await _connect();
    if (ok) {
      await _store.save(_config);
    } else {
      // Keep the choice but do not persist credentials that do not work.
      _dav = null;
    }
    notifyListeners();
    return ok;
  }

  /// Builds the WebDAV client for the current config and verifies it.
  Future<bool> _connect({bool silent = false}) async {
    _connecting = true;
    if (!silent) notifyListeners();

    try {
      if (!_config.isConfigured) {
        _syncErrorMessage = 'Cloud sync is not configured yet.';
        return false;
      }
      final base = resolvedBaseUrl;
      if (base.isEmpty) {
        _syncErrorMessage = 'WebDAV server URL is empty.';
        return false;
      }

      _dav?.dispose();
      _dav = WebDavService(
        baseUrl: base,
        username: _config.username,
        password: _config.password,
      );

      await _dav!.ping();

      // Create the remote project root so the first listing is not a 404.
      final root = _remoteRoot;
      if (root.isNotEmpty) {
        final relative = _relativeToBase(root);
        if (relative.isNotEmpty) await _dav!.mkdirAll(relative);
      }

      _syncErrorMessage = null;

      // For the built-in provider, enrich the UI with account/quota info.
      if (_config.kind == CloudProviderKind.mscCloud) {
        await _refreshMscAccountInfo();
      } else {
        _userName = _config.username;
        _userEmail = _config.username;
        _userId = null;
        _usedBytes = 0;
        _quotaBytes = 0;
        _isHealthy = true;
      }
      return true;
    } on WebDavException catch (e) {
      _syncErrorMessage = e.message;
      return false;
    } catch (e) {
      _syncErrorMessage = 'Connection failed: $e';
      return false;
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  /// Fetches MSC account details (quota/usage) through the REST API.
  ///
  /// Uses WebDAV credentials as-is: MSC accepts the same email + API token
  /// for Basic auth, but quota figures come from `/api/me`, which needs a
  /// session — so failures here are non-fatal and simply leave quota at 0.
  Future<void> _refreshMscAccountInfo() async {
    try {
      final client = http.Client();
      final auth = base64Encode(
        utf8.encode('${_config.username}:${_config.password}'),
      );
      final response = await client
          .get(
            Uri.parse('$mscBaseUrl/api/me'),
            headers: {'Authorization': 'Basic $auth'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final user = data['user'] as Map<String, dynamic>?;
        if (user != null) {
          _userId = user['id'] as int?;
          _userName = user['name'] as String? ?? _config.username;
          _userEmail = user['email'] as String? ?? _config.username;
        }
        final services = data['services'] as List?;
        final cs = services?.firstWhere(
          (s) => (s as Map<String, dynamic>)['slug'] == 'cloudsync',
          orElse: () => const <String, dynamic>{},
        ) as Map<String, dynamic>?;
        if (cs != null && cs.isNotEmpty) {
          _usedBytes = (cs['usedBytes'] as num?)?.toDouble() ?? 0;
          _quotaBytes = (cs['quotaBytes'] as num?)?.toDouble() ?? 0;
          _isHealthy = cs['healthy'] as bool? ?? true;
        }
      }
    } catch (_) {
      // Quota is cosmetic — a failure must not break the connection.
      _userName ??= _config.username;
      _userEmail ??= _config.username;
    } finally {
      _isHealthy = true;
    }
  }

  /// Re-reads quota/usage for the active provider.
  Future<void> updateQuota() async {
    if (_config.kind == CloudProviderKind.mscCloud) {
      await _refreshMscAccountInfo();
    }
    notifyListeners();
  }

  /// Forgets the stored provider and credentials.
  Future<void> logout() async {
    _dav?.dispose();
    _dav = null;
    _config = CloudConfig();
    _userId = null;
    _userName = null;
    _userEmail = null;
    _usedBytes = 0;
    _quotaBytes = 0;
    _projectSyncStatus.clear();
    _lastSyncedAt.clear();
    _syncErrorMessage = null;
    await _store.clear();
    notifyListeners();
  }

  // ------------------------------------------------------------------ sync

  /// Strips the provider root prefix, yielding a path the client can use.
  String _relativeToBase(String absolute) {
    final base = resolvedBaseUrl;
    if (absolute.startsWith(base)) {
      return absolute.substring(base.length).replaceAll(RegExp(r'^/+'), '');
    }
    return absolute.replaceAll(RegExp(r'^/+'), '');
  }

  /// Compares the local and remote copies and moves the newer one across.
  ///
  /// When both sides changed since the last sync, [onConflict] is awaited and
  /// its choice decides which version survives (or whether both are kept).
  Future<SyncOutcome> syncProject(
    Project project,
    Future<SyncResolution> Function(DateTime localTime, DateTime remoteTime)
        onConflict,
  ) async {
    if (!isLoggedIn || project.filePath == null) {
      return SyncOutcome.failed;
    }

    _syncingProjectId = project.id;
    _syncErrorMessage = null;
    _projectSyncStatus[project.id] = SyncStatus.syncing;
    notifyListeners();

    try {
      final localFile = File(project.filePath!);
      if (!await localFile.exists()) {
        _syncErrorMessage = 'Local project file is missing.';
        _projectSyncStatus[project.id] = SyncStatus.error;
        return SyncOutcome.failed;
      }

      final remoteKey = _remoteKeyFor(project);
      final localTime = localFile.lastModifiedSync();
      final remote = await _dav!.stat(remoteKey);
      final lastSync = _lastSyncedAt[project.id];

      // First upload for this project, or the remote copy was deleted.
      if (remote == null) {
        await _upload(localFile, remoteKey);
        return _finish(project.id, SyncOutcome.uploaded);
      }

      final remoteTime = remote.modified ?? DateTime.fromMillisecondsSinceEpoch(0);
      final localChanged = lastSync == null || localTime.isAfter(lastSync);
      final remoteChanged = lastSync == null || remoteTime.isAfter(lastSync);

      if (localChanged && remoteChanged) {
        final resolution = await onConflict(localTime, remoteTime);
        switch (resolution) {
          case SyncResolution.local:
            await _upload(localFile, remoteKey);
            return _finish(project.id, SyncOutcome.conflictResolved);
          case SyncResolution.remote:
            await _download(remoteKey, localFile);
            return _finish(project.id, SyncOutcome.conflictResolved);
          case SyncResolution.both:
            // Keep the local edits as a new remote file *and* pull the
            // remote version down, so nothing is lost.
            final stamp = DateTime.now().millisecondsSinceEpoch;
            final copyKey =
                'projects/${project.id}/${_sanitize(project.name)}_conflict_$stamp'
                '${LgdfCodec.extension}';
            await _upload(localFile, copyKey);
            await _download(remoteKey, localFile);
            return _finish(project.id, SyncOutcome.conflictResolved);
        }
      } else if (localChanged) {
        await _upload(localFile, remoteKey);
        return _finish(project.id, SyncOutcome.uploaded);
      } else if (remoteChanged) {
        await _download(remoteKey, localFile);
        return _finish(project.id, SyncOutcome.downloaded);
      }

      return _finish(project.id, SyncOutcome.upToDate);
    } on WebDavException catch (e) {
      _syncErrorMessage = e.message;
      _projectSyncStatus[project.id] = SyncStatus.error;
      return SyncOutcome.failed;
    } catch (e) {
      _syncErrorMessage = 'Sync failed: $e';
      _projectSyncStatus[project.id] = SyncStatus.error;
      return SyncOutcome.failed;
    } finally {
      _syncingProjectId = null;
      notifyListeners();
    }
  }

  /// Writes the success/failure status and clears the transient syncing flag.
  SyncOutcome _finish(String projectId, SyncOutcome outcome) {
    _projectSyncStatus[projectId] = SyncStatus.success;
    _lastSyncedAt[projectId] = DateTime.now();
    _syncErrorMessage = null;
    return outcome;
  }

  /// Uploads [file] to [key], relative to the provider root.
  Future<void> _upload(File file, String key) async {
    final bytes = await file.readAsBytes();
    await _dav!.writeBytes(_remotePathFor(key), bytes);
  }

  /// Downloads [key] into [file], replacing its contents.
  Future<void> _download(String key, File file) async {
    final bytes = await _dav!.readBytes(_remotePathFor(key));
    await file.writeAsBytes(bytes);
  }

  /// Prefixes a project key with the configured remote sub-directory.
  String _remotePathFor(String key) {
    final sub = _config.remotePath.replaceAll(RegExp(r'^/+|/+$'), '');
    return sub.isEmpty ? key : '$sub/$key';
  }

  /// Lists files already stored in the cloud (for the sync browser).
  Future<List<WebDavEntry>> listRemoteFiles({String prefix = ''}) async {
    if (!isLoggedIn) return const [];
    final sub = _config.remotePath.replaceAll(RegExp(r'^/+|/+$'), '');
    final path = prefix.isEmpty
        ? sub
        : (sub.isEmpty ? prefix : '$sub/$prefix');
    return _dav!.readDir(path);
  }

  /// Marks a project as locally modified (dirty) since its last sync.
  void markDirty(String projectId) {
    if (_projectSyncStatus[projectId] == SyncStatus.success) {
      _projectSyncStatus[projectId] = SyncStatus.idle;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _dav?.dispose();
    super.dispose();
  }
}
