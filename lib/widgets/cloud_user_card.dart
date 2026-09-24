import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hue_cai/providers/cloud_sync_provider.dart';

class CloudUserCard extends StatelessWidget {
  const CloudUserCard({super.key});

  @override
  Widget build(BuildContext context) {
    final syncProvider = context.watch<CloudSyncProvider>();

    if (!syncProvider.isLoggedIn) {
      return Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.cloud_off, color: Colors.grey),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Cloud Sync is disabled. Login to backup your projects.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              TextButton(
                onPressed: () => _showLoginDialog(context),
                child: const Text('Login'),
              ),
            ],
          ),
        ),
      );
    }

    final used = syncProvider.usedBytes;
    final quota = syncProvider.quotaBytes;
    final storagePercent = quota > 0 ? used / quota : 0.0;

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
                  backgroundColor: Theme.of(context).primaryColor,
                  child: Text(
                    syncProvider.userName.isNotEmpty
                        ? syncProvider.userName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        syncProvider.userName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        syncProvider.userEmail,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout, size: 20),
                  onPressed: () => syncProvider.logout(),
                  tooltip: 'Logout',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cloud Storage',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                Text(
                  '${(used / 1024 / 1024).toStringAsFixed(1)} MB / ${(quota / 1024 / 1024).toStringAsFixed(1)} MB',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: storagePercent.clamp(0.0, 1.0),
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              color: storagePercent > 0.9 ? Colors.red : Colors.blue,
              minHeight: 6,
            ),
          ],
        ),
      ),
    );
  }

  void _showLoginDialog(BuildContext context) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cloud Sync Login'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && emailController.text.isNotEmpty) {
                context.read<CloudSyncProvider>().login(
                  emailController.text,
                  nameController.text,
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Login'),
          ),
        ],
      ),
    );
  }
}
