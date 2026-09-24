import 'package:flutter/material.dart';

import '../providers/cloud_sync_provider.dart';

/// Asks which version to keep when the local project and its cloud copy both
/// changed since the last sync.
///
/// Returns the chosen [SyncResolution], or `null` when the user dismissed the
/// dialog — callers should treat `null` as "do nothing" rather than silently
/// overwriting one side. `barrierDismissible` is therefore false and an
/// explicit cancel action is offered.
Future<SyncResolution?> showCloudConflictDialog(
  BuildContext context, {
  required DateTime localTime,
  required DateTime remoteTime,
  String? projectName,
  int? localSize,
  int? remoteSize,
}) {
  return showDialog<SyncResolution>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: const Text('Cloud sync conflict'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                projectName == null
                    ? 'This project was modified both locally and in the '
                        'cloud since the last sync. Choose which version to '
                        'keep.'
                    : '"$projectName" was modified both locally and in the '
                        'cloud since the last sync. Choose which version to '
                        'keep.',
              ),
              const SizedBox(height: 16),
              _versionRow(
                theme,
                icon: Icons.computer,
                label: 'This device',
                time: localTime,
                size: localSize,
              ),
              const SizedBox(height: 8),
              _versionRow(
                theme,
                icon: Icons.cloud,
                label: 'Cloud copy',
                time: remoteTime,
                size: remoteSize,
              ),
              const SizedBox(height: 16),
              Text(
                'Keeping both saves the local version as a separate copy in '
                'the cloud and then restores the cloud version here.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(SyncResolution.remote),
            child: const Text('Keep cloud version'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(SyncResolution.both),
            child: const Text('Keep both'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(SyncResolution.local),
            child: const Text('Keep this device'),
          ),
        ],
      );
    },
  );
}

/// One line describing a version: where it lives, when and how big.
Widget _versionRow(
  ThemeData theme, {
  required IconData icon,
  required String label,
  required DateTime time,
  int? size,
}) {
  return Row(
    children: [
      Icon(icon, size: 18, color: theme.colorScheme.primary),
      const SizedBox(width: 10),
      Expanded(
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      ),
      Text(
        '${_fmt(time)}${size != null ? '  ·  ${_kb(size)}' : ''}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

String _fmt(DateTime dt) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

String _kb(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
