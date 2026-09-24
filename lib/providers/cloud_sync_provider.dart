import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import '../services/cloud_sync_service.dart';
import '../models/project.dart';

/// Outcome of a cloud sync conflict resolution choice.
enum SyncResolution { local, remote, both }

/// Per-project sync status used by the workspace UI.
enum SyncStatus { idle, syncing, success, error }

/// Manages cloud synchronization state and user session.
class CloudSyncProvider with ChangeNotifier {
  final CloudSyncService _service = CloudSyncService();

  // User Info
  String? _userName;
  String? _userEmail;
  int? _userId;

  // Quota Info
  double _usedBytes = 0;
  double _quotaBytes = 0;
  bool _isHealthy = true;

  // Sync State
  String? _syncingProjectId; // ID of the project currently being synced
  String? _syncErrorMessage;
  final Map<String, SyncStatus> _projectSyncStatus = {};
  final Map<String, DateTime> _lastSyncedAt = {};

  String get userName => _userName ?? 'Guest';
  String get userEmail => _userEmail ?? '';
  int? get userId => _userId;
  double get usedBytes => _usedBytes;
  double get quotaBytes => _quotaBytes;
  bool get isHealthy => _isHealthy;
  String? get syncingProjectId => _syncingProjectId;
  String? get syncErrorMessage => _syncErrorMessage;
  bool get isLoggedIn => _userId != null;

  /// Sync status for a given project id (defaults to idle).
  SyncStatus statusOf(String projectId) =>
      _projectSyncStatus[projectId] ?? SyncStatus.idle;

  /// Perform a developer login to initialize the session.
  Future<bool> login(String email, String name) async {
    try {
      final response = await _service.devLogin(email, name);
      if (response.statusCode == 200) {
        // Session established via cookies. Now fetch user info + CSRF.
        await refreshUserInfo();
        return true;
      }
      _syncErrorMessage = 'Login failed (${response.statusCode})';
    } catch (e) {
      _syncErrorMessage = 'Login failed: $e';
    }
    notifyListeners();
    return false;
  }

  /// Fetches user info and updates storage quota.
  Future<void> refreshUserInfo() async {
    try {
      final response = await _service.request('GET', '/api/me');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final user = data['user'] as Map<String, dynamic>;
        _userId = user['id'] as int;
        _userName = user['name'] as String;
        _userEmail = user['email'] as String;

        // Find the cloud sync service info in the services list.
        final services = data['services'] as List;
        final cs = services.firstWhere(
          (s) => (s as Map<String, dynamic>)['slug'] == 'cloudsync',
          orElse: () => const <String, dynamic>{},
        ) as Map<String, dynamic>;

        if (cs.isNotEmpty) {
          _usedBytes = (cs['usedBytes'] as num).toDouble();
          _quotaBytes = (cs['quotaBytes'] as num).toDouble();
          _isHealthy = cs['healthy'] as bool;
        }
        _syncErrorMessage = null;
      }
    } catch (e) {
      _syncErrorMessage = 'Failed to refresh user info: $e';
    }
    notifyListeners();
  }

  Future<void> updateQuota() async {
    try {
      final quota = await _service.getQuota();
      _usedBytes = (quota['usedBytes'] as num).toDouble();
      _quotaBytes = (quota['quotaBytes'] as num).toDouble();
    } catch (e) {
      _syncErrorMessage = 'Quota update failed: $e';
    }
    notifyListeners();
  }

  /// Uploads the local project file to the cloud under the given key.
  Future<void> _uploadProject(File localFile, String key) async {
    final bytes = await localFile.readAsBytes();
    final req = await _service.uploadRequest(key, bytes.length);
    await _service.uploadToS3(req, localFile);
    await _service.confirmUpload(req.key);
  }

  /// Syncs a local project to the cloud.
  /// Compares local file mtime against the remote object's modified time
  /// (relative to the last successful sync). When both sides changed,
  /// invokes [onConflict] which must return the chosen [SyncResolution].
  Future<void> syncProject(
    Project project,
    Future<SyncResolution> Function(DateTime localTime, DateTime remoteTime)
        onConflict,
  ) async {
    if (!isLoggedIn || project.filePath == null) return;
    _syncingProjectId = project.id;
    _syncErrorMessage = null;
    _projectSyncStatus[project.id] = SyncStatus.syncing;
    notifyListeners();

    try {
      final localFile = File(project.filePath!);
      if (!await localFile.exists()) {
        _projectSyncStatus[project.id] = SyncStatus.error;
        _syncErrorMessage = 'Local project file missing.';
        return;
      }
      final localTime = localFile.lastModifiedSync();

      final remotePrefix = 'projects/${project.id}/';
      final remoteKey = '$remotePrefix${project.name}.hcp';
      final remoteFiles = await _service.listFiles(prefix: remotePrefix);
      CloudObject? remoteObj;
      for (final f in remoteFiles) {
        if (!f.isDir && f.name.toLowerCase().endsWith('.hcp')) {
          remoteObj = f;
          break;
        }
      }

      final lastSync = _lastSyncedAt[project.id];

      if (remoteObj == null) {
        // First sync — straightforward upload.
        await _uploadProject(localFile, remoteKey);
      } else {
        final remoteTime =
            DateTime.tryParse(remoteObj.modified) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final localChanged =
            lastSync == null || localTime.isAfter(lastSync);
        final remoteChanged =
            lastSync == null || remoteTime.isAfter(lastSync);

        if (localChanged && remoteChanged) {
          // Both sides were modified since the last sync — ask the user.
          final resolution = await onConflict(localTime, remoteTime);
          switch (resolution) {
            case SyncResolution.local:
              await _uploadProject(localFile, remoteKey);
              break;
            case SyncResolution.remote:
              await _service.downloadFile(
                remoteObj.key,
                localFile.path,
              );
              break;
            case SyncResolution.both:
              final stamp = DateTime.now()
                  .millisecondsSinceEpoch;
              final copyKey =
                  '$remotePrefix${project.name}_conflict_$stamp.hcp';
              await _uploadProject(localFile, copyKey);
              break;
          }
        } else if (localChanged) {
          await _uploadProject(localFile, remoteKey);
        } else if (remoteChanged) {
          await _service.downloadFile(remoteObj.key, localFile.path);
        }
        // else: nothing changed on either side.
      }

      _lastSyncedAt[project.id] = DateTime.now();
      _projectSyncStatus[project.id] = SyncStatus.success;
    } catch (e) {
      _syncErrorMessage = 'Sync failed: $e';
      _projectSyncStatus[project.id] = SyncStatus.error;
    } finally {
      _syncingProjectId = null;
      notifyListeners();
    }
  }

  void logout() {
    _userId = null;
    _userName = null;
    _userEmail = null;
    _usedBytes = 0;
    _quotaBytes = 0;
    _projectSyncStatus.clear();
    _lastSyncedAt.clear();
    notifyListeners();
  }
}
