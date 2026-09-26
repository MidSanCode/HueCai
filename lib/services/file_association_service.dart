import 'dart:io';

import 'package:flutter/foundation.dart';

/// Registers (and unregisters) `.hcproj` as a file type that opens with this
/// app on the desktop platforms where that is done imperatively.
///
/// - **Windows**: writes the `HKCU\Software\Classes\.hcproj` ProgID mapping
///   (per-user, no admin rights needed) and notifies the shell.
/// - **Linux**: installs a MIME type and a `.desktop` entry under the user's
///   XDG data dir.
/// - **macOS / iOS / Android**: declared statically in the platform bundles
///   (Info.plist / AndroidManifest), so nothing is done here at runtime.
class FileAssociationService {
  FileAssociationService._();

  static const String extension = '.hcproj';
  static const String legacyExtension = '.hcp';
  static const String progId = 'huecai.project';
  static const String fileDescription = 'hue_cai drawing project';

  /// Ensures the association exists on platforms that need runtime
  /// registration. Safe to call on every launch — it is idempotent and skips
  /// platforms whose association is declared statically.
  static Future<void> ensureRegistered() async {
    if (kIsWeb) return;
    try {
      if (Platform.isWindows) {
        await _registerWindows();
      } else if (Platform.isLinux) {
        await _registerLinux();
      }
    } catch (_) {
      // Association is best-effort; never block startup over it.
    }
  }

  // --------------------------------------------------------------- Windows

  /// Writes the ProgID under HKCU and points both extensions at it.
  static Future<void> _registerWindows() async {
    final exe = Platform.resolvedExecutable.replaceAll('/', '\\');
    final icon = '$exe,0';

    // .hcproj and legacy .hcp -> huecai.project
    for (final ext in [extension, legacyExtension]) {
      await _regAdd(
        'HKCU\\Software\\Classes\\$ext',
        valueName: '',
        data: progId,
      );
    }

    await _regAdd('HKCU\\Software\\Classes\\$progId',
        valueName: '', data: fileDescription);
    await _regAdd('HKCU\\Software\\Classes\\$progId\\DefaultIcon',
        valueName: '', data: icon);
    await _regAdd(
      'HKCU\\Software\\Classes\\$progId\\shell\\open\\command',
      valueName: '',
      data: '"$exe" "%1"',
    );

    // Tell the shell to refresh its icon/association cache.
    await _shChangeNotify();
  }

  /// Removes the Windows association (per-user keys only).
  static Future<void> unregisterWindows() async {
    if (!Platform.isWindows) return;
    for (final key in [
      'HKCU\\Software\\Classes\\$progId',
      'HKCU\\Software\\Classes\\$extension',
      'HKCU\\Software\\Classes\\$legacyExtension',
    ]) {
      await Process.run('reg', ['delete', key, '/f']);
    }
    await _shChangeNotify();
  }

  static Future<void> _regAdd(
    String key, {
    required String valueName,
    required String data,
  }) {
    final args = ['add', key, '/ve', '/d', data, '/f'];
    if (valueName.isNotEmpty) {
      args
        ..remove('/ve')
        ..insertAll(2, ['/v', valueName]);
    }
    return Process.run('reg', args);
  }

  /// `SHChangeNotify(SHCNE_ASSOCCHANGED)` so Explorer picks the change up.
  static Future<void> _shChangeNotify() async {
    // ie4uinit.exe ships with Windows and triggers a shell refresh without
    // needing to compile a native call into the runner.
    await Process.run('ie4uinit.exe', ['-show']);
  }

  // ----------------------------------------------------------------- Linux

  /// Installs `application/x-hcproj` and a desktop entry for the current user.
  static Future<void> _registerLinux() async {
    final home = Platform.environment['HOME'];
    if (home == null) return;
    final exe = Platform.resolvedExecutable;

    // MIME definition.
    final mimeDir = Directory('$home/.local/share/mime/packages');
    await mimeDir.create(recursive: true);
    await File('${mimeDir.path}/huecai.xml').writeAsString(
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">\n'
      '  <mime-type type="application/x-hcproj">\n'
      '    <comment>$fileDescription</comment>\n'
      '    <glob pattern="*$extension"/>\n'
      '    <glob pattern="*$legacyExtension"/>\n'
      '  </mime-type>\n'
      '</mime-info>\n',
    );

    // Desktop entry.
    final appsDir = Directory('$home/.local/share/applications');
    await appsDir.create(recursive: true);
    await File('${appsDir.path}/huecai.desktop').writeAsString(
      '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=HueCai\n'
      'Comment=$fileDescription\n'
      'Exec=$exe %f\n'
      'MimeType=application/x-hcproj;\n'
      'Categories=Graphics;\n'
      'Terminal=false\n',
    );

    // Refresh the user databases (best-effort; tools may be absent).
    await Process.run('update-mime-database', ['$home/.local/share/mime']);
    await Process.run('update-desktop-database', [appsDir.path]);
  }
}
