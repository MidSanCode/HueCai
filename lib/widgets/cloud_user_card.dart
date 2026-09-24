import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/cloud_sync_provider.dart';
import '../services/cloud_config_store.dart';
import 'cloud_setup_dialog.dart';

/// Header card on the workspace showing cloud-sync login state and usage.
///
/// When cloud sync is not configured the card explains the feature and offers
/// a login button; once connected it shows the account, provider, storage
/// usage and a sign-out action.
class CloudUserCard extends StatelessWidget {
  const CloudUserCard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CloudSyncProvider>();
    final theme = Theme.of(context);

    if (!provider.isLoggedIn) {
      return Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.cloud_off, color: theme.colorScheme.outline),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  provider.hasChosenProvider
                      ? 'Cloud Sync is not connected. Log in to back up your '
                          'projects.'
                      : 'Cloud Sync is disabled. Log in to back up your '
                          'projects.',
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              ),
              if (provider.isLoggingIn)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              FilledButton.tonal(
                onPressed: provider.isLoggingIn
                    ? null
                    : () => showCloudSetupDialog(context),
                child: const Text('Login'),
              ),
            ],
          ),
        ),
      );
    }

    final used = provider.usedBytes;
    final quota = provider.quotaBytes;
    final hasQuota = quota > 0;
    final storagePercent = hasQuota ? used / quota : 0.0;
    final isMsc = provider.providerKind == CloudProviderKind.mscCloud;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    provider.userName.isNotEmpty
                        ? provider.userName[0].toUpperCase()
                        : '?',
                    style: TextStyle(color: theme.colorScheme.onPrimary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.userName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        provider.userEmail,
                        style: TextStyle(
                            color: theme.colorScheme.outline, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                _providerChip(theme, provider.providerLabel),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.logout, size: 20),
                  tooltip: 'Logout',
                  onPressed: () => _confirmLogout(context, provider),
                ),
              ],
            ),
            // Quota is only reported by MSC Cloud; custom WebDAV servers do
            // not expose a storage limit, so hide the bar rather than imply 0.
            if (isMsc && hasQuota) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cloud Storage',
                      style: TextStyle(
                          fontSize: 12, color: theme.colorScheme.outline),
                    ),
                  ),
                  Text(
                    '${_mb(used)} MB / ${_mb(quota)} MB',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: storagePercent.clamp(0.0, 1.0),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: storagePercent > 0.9
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
                minHeight: 6,
              ),
            ] else ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.folder_outlined,
                      size: 16, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      provider.resolvedBaseUrl.isEmpty
                          ? 'Not configured'
                          : '${provider.resolvedBaseUrl}'
                              '${provider.config.remotePath}',
                      style: TextStyle(
                          fontSize: 12, color: theme.colorScheme.outline),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Small label showing which provider currently backs sync.
  Widget _providerChip(ThemeData theme, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  String _mb(double bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);

  Future<void> _confirmLogout(
      BuildContext context, CloudSyncProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out of cloud sync?'),
        content: const Text(
          'Saved credentials will be removed from this device. Projects '
          'already in the cloud are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await provider.logout();
  }
}
