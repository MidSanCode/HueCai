import 'package:flutter/material.dart';
import '../providers/cloud_sync_provider.dart';

/// Shows a conflict-resolution dialog when both the local project and the
/// cloud copy were modified since the last sync.
Future<SyncResolution?> showCloudConflictDialog(
  BuildContext context, {
  required DateTime localTime,
  required DateTime remoteTime,
}) {
  return showDialog<SyncResolution>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sync Conflict'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This project was modified both locally and in the cloud since '
            'the last sync. Choose which version to keep.',
          ),
          const SizedBox(height: 12),
          Text(
            'Local:  ${_fmt(localTime)}',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Cloud:  ${_fmt(remoteTime)}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(SyncResolution.local),
          child: const Text('Keep Local'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(SyncResolution.remote),
          child: const Text('Keep Remote'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(SyncResolution.both),
          child: const Text('Keep Both'),
        ),
      ],
    ),
  );
}

String _fmt(DateTime dt) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}