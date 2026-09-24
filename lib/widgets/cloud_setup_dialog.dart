import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/cloud_sync_provider.dart';
import '../services/cloud_config_store.dart';

/// Result of the cloud setup dialog: either a chosen [CloudConfig], or `null`
/// when the user cancelled.
class CloudSetupResult {
  const CloudSetupResult(this.config);
  final CloudConfig config;
}

/// Shows the "log in to cloud sync" flow.
///
/// First asks which provider to use — a custom WebDAV server or the built-in
/// MSC Cloud — then collects the credentials that provider needs and verifies
/// them before returning.
Future<CloudConfig?> showCloudSetupDialog(BuildContext context) {
  return showDialog<CloudConfig>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _CloudSetupDialog(),
  );
}

class _CloudSetupDialog extends StatefulWidget {
  const _CloudSetupDialog();

  @override
  State<_CloudSetupDialog> createState() => _CloudSetupDialogState();
}

class _CloudSetupDialogState extends State<_CloudSetupDialog> {
  /// `null` until the user picks a provider on the first step.
  CloudProviderKind? _step;

  final _serverController = TextEditingController(text: 'https://');
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pathController = TextEditingController(text: 'hue_cai');
  final _mscEmailController = TextEditingController();
  final _mscTokenController = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-fill from any config already on disk, so "re-login" is quick.
    final existing = context.read<CloudSyncProvider>().config;
    if (existing.kind != null) {
      _step = existing.kind;
      if (existing.serverUrl.isNotEmpty) _serverController.text = existing.serverUrl;
      if (existing.username.isNotEmpty) {
        _userController.text = existing.username;
        _mscEmailController.text = existing.username;
      }
      if (existing.password.isNotEmpty) {
        _passwordController.text = existing.password;
        _mscTokenController.text = existing.password;
      }
      if (existing.remotePath.isNotEmpty) _pathController.text = existing.remotePath;
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _pathController.dispose();
    _mscEmailController.dispose();
    _mscTokenController.dispose();
    super.dispose();
  }

  CloudConfig _buildConfig() {
    if (_step == CloudProviderKind.mscCloud) {
      return CloudConfig(
        kind: CloudProviderKind.mscCloud,
        username: _mscEmailController.text.trim(),
        password: _mscTokenController.text.trim(),
        remotePath: _pathController.text.trim().isEmpty
            ? 'hue_cai'
            : _pathController.text.trim(),
      );
    }
    return CloudConfig(
      kind: CloudProviderKind.customWebDav,
      serverUrl: _serverController.text.trim(),
      username: _userController.text.trim(),
      password: _passwordController.text,
      remotePath: _pathController.text.trim().isEmpty
          ? 'hue_cai'
          : _pathController.text.trim(),
    );
  }

  Future<void> _submit() async {
    final config = _buildConfig();

    // Validate before spending a network round-trip on obviously bad input.
    final missing = <String>[];
    if (config.kind == CloudProviderKind.customWebDav) {
      if (config.serverUrl.isEmpty || config.serverUrl == 'https://') {
        missing.add('Server URL');
      }
    }
    if (config.username.isEmpty) {
      missing.add(config.kind == CloudProviderKind.mscCloud
          ? 'Email'
          : 'User name');
    }
    if (config.password.isEmpty) {
      missing.add(config.kind == CloudProviderKind.mscCloud
          ? 'API token'
          : 'Password');
    }
    if (missing.isNotEmpty) {
      setState(() => _error = 'Please fill in: ${missing.join(', ')}');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final provider = context.read<CloudSyncProvider>();
    final ok = await provider.configureProvider(config);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(config);
    } else {
      setState(() {
        _busy = false;
        _error = provider.syncErrorMessage ?? 'Connection failed.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Cloud Sync Login'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: _step == null ? _buildProviderChoice(theme) : _buildForm(theme),
        ),
      ),
      actions: _buildActions(),
    );
  }

  // --------------------------------------------------------- provider choice

  Widget _buildProviderChoice(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose where your projects are synced.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        _providerTile(
          theme,
          icon: Icons.cloud_outlined,
          title: 'MSC Cloud',
          subtitle:
              'Built-in hosting. Sign in with your account email and an API '
              'token created on the account page.',
          onTap: () => setState(() => _step = CloudProviderKind.mscCloud),
        ),
        const SizedBox(height: 8),
        _providerTile(
          theme,
          icon: Icons.dns_outlined,
          title: 'Custom WebDAV provider',
          subtitle:
              'Nextcloud, Synology, ownCloud or any other WebDAV server. '
              'Use your server URL plus its user name and password.',
          onTap: () => setState(() => _step = CloudProviderKind.customWebDav),
        ),
      ],
    );
  }

  Widget _providerTile(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- form

  Widget _buildForm(ThemeData theme) {
    final isMsc = _step == CloudProviderKind.mscCloud;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 18),
              tooltip: 'Back',
              onPressed: _busy ? null : () => setState(() {
                _step = null;
                _error = null;
              }),
            ),
            Text(
              isMsc ? 'MSC Cloud' : 'Custom WebDAV provider',
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isMsc) ...[
          Text(
            'Sign in with your MSC Cloud account. Create an API token under '
            'Account → API access tokens, then paste it below.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mscEmailController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'you@example.com',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mscTokenController,
            enabled: !_busy,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'API token',
              helperText: 'Shown only once when you create it.',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off,
                    size: 18),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ] else ...[
          TextField(
            controller: _serverController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'https://cloud.example.com/remote.php/dav/files/me/',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _userController,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'User name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            enabled: !_busy,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off,
                    size: 18),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _pathController,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Remote folder',
            helperText: 'Sub-folder on the server where projects are stored.',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline,
                  size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  List<Widget> _buildActions() {
    if (_step == null) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Connect & Login'),
      ),
    ];
  }
}
