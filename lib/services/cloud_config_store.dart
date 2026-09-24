import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Which backing store the user picked for cloud sync.
enum CloudProviderKind {
  /// A user-supplied WebDAV server (Nextcloud, Synology, self-hosted, ...).
  customWebDav,

  /// The built-in MSC Cloud hosting, which is itself a WebDAV endpoint
  /// (`{baseURL}/dav/`) authenticated with a login email + API token.
  mscCloud,
}

/// Persisted cloud-sync configuration: the chosen provider plus whatever
/// credentials that provider needs.
class CloudConfig {
  CloudConfig({
    this.kind,
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.remotePath = 'hue_cai',
  });

  /// `null` means the user has not chosen a provider yet — the first run of
  /// cloud sync must ask.
  final CloudProviderKind? kind;

  /// WebDAV root URL. Unused for [CloudProviderKind.mscCloud], whose URL is
  /// derived from the service base URL.
  final String serverUrl;

  /// WebDAV user name (custom) or MSC login email.
  final String username;

  /// WebDAV password (custom) or MSC account API token.
  final String password;

  /// Sub-directory under the WebDAV root where projects are stored.
  final String remotePath;

  bool get isConfigured =>
      kind != null && username.isNotEmpty && password.isNotEmpty;

  CloudConfig copyWith({
    CloudProviderKind? kind,
    String? serverUrl,
    String? username,
    String? password,
    String? remotePath,
  }) {
    return CloudConfig(
      kind: kind ?? this.kind,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remotePath: remotePath ?? this.remotePath,
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind?.name,
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'remotePath': remotePath,
      };

  factory CloudConfig.fromJson(Map<String, dynamic> json) {
    final rawKind = json['kind'] as String?;
    return CloudConfig(
      kind: rawKind == null
          ? null
          : CloudProviderKind.values.firstWhere(
              (k) => k.name == rawKind,
              orElse: () => CloudProviderKind.customWebDav,
            ),
      serverUrl: json['serverUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      remotePath: json['remotePath'] as String? ?? 'hue_cai',
    );
  }
}

/// Reads and writes [CloudConfig] as JSON next to the other app settings.
///
/// The file lives in the application documents directory with restrictive
/// permissions where the platform supports it, because it holds an API token.
class CloudConfigStore {
  static const String _fileName = 'huecai_cloud.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Loads the stored config, returning an empty one when nothing is saved.
  Future<CloudConfig> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return CloudConfig();
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return CloudConfig.fromJson(raw);
    } catch (_) {
      // A corrupt config must not break app start-up; fall back to empty and
      // let the user re-enter credentials.
      return CloudConfig();
    }
  }

  /// Persists [config] and clears the stored credentials when it is empty.
  Future<void> save(CloudConfig config) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(config.toJson()));
      if (!Platform.isWindows) {
        // Best-effort hardening on POSIX; ignored where unsupported.
        await Process.run('chmod', ['600', file.path]);
      }
    } catch (_) {}
  }

  /// Removes any stored credentials.
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
