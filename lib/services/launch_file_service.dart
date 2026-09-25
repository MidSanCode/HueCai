import 'dart:io';

import 'package:flutter/services.dart';

/// Resolves the file a user asked us to open when the app was launched as the
/// handler for `.hcproj`.
///
/// The OS starts the executable with the document path as an argument, so the
/// Dart entrypoint receives it through `dart_entrypoint_arguments` (wired up in
/// `windows/runner/main.cpp`, `macos/.../MainFlutterWindow.swift` and the Linux
/// runner). Android and iOS deliver it through the `hue_cai/launch` channel
/// instead, since neither passes a path on the command line.
class LaunchFileService {
  LaunchFileService._();

  static const MethodChannel _channel = MethodChannel('hue_cai/launch');

  /// Path of the document the app was launched with, if any.
  ///
  /// Resolved once and cached; [consume] returns it only a single time so a
  /// rebuild cannot re-open the same project.
  static String? _pending;
  static bool _resolved = false;

  /// Extensions we are willing to open from the command line.
  static const List<String> _acceptedExtensions = ['.hcproj', '.hcp'];

  /// The launch document path, without clearing it.
  static String? get pendingPath => _pending;

  /// Reads the launch argument from the platform, once.
  ///
  /// [arguments] should be the value of `Platform.executableArguments`-style
  /// entrypoint arguments that the runner passed through.
  static Future<String?> resolve(List<String> arguments) async {
    if (_resolved) return _pending;
    _resolved = true;

    // 1. Command-line argument (Windows / macOS / Linux).
    for (final arg in arguments) {
      final candidate = _normalize(arg);
      if (candidate != null) {
        _pending = candidate;
        return _pending;
      }
    }

    // 2. Platform channel (Android VIEW intent / iOS openURL).
    try {
      final path = await _channel.invokeMethod<String>('getLaunchFile');
      final candidate = path == null ? null : _normalize(path);
      if (candidate != null) _pending = candidate;
    } on MissingPluginException {
      // No native handler registered (e.g. desktop, web): nothing to do.
    } catch (_) {
      // A malformed payload must not stop startup.
    }

    return _pending;
  }

  /// Returns the launch path and clears it, so it is opened at most once.
  static String? consume() {
    final path = _pending;
    _pending = null;
    return path;
  }

  /// Clears any pending path without returning it.
  static void clear() => _pending = null;

  /// Resets cached state. Test-only.
  static void resetForTest() {
    _pending = null;
    _resolved = false;
  }

  /// Seeds a pending path. Test-only.
  static void setForTest(String? path) {
    _pending = path;
    _resolved = true;
  }

  /// Validates an argument and returns a normalized absolute path, or null.
  ///
  /// Only arguments naming an existing file with a known project extension are
  /// accepted, so unrelated runner flags (`--enable-dart-profiling`, etc.) are
  /// never mistaken for a document.
  static String? _normalize(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    // Runners may quote a path containing spaces.
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    // Ignore any other switch the runner may forward.
    if (value.startsWith('-')) return null;

    final lower = value.toLowerCase();
    if (!_acceptedExtensions.any(lower.endsWith)) return null;

    final file = File(value);
    if (!file.existsSync()) return null;
    return file.absolute.path;
  }
}
