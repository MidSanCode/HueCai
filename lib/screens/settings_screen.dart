import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkMode = false;
  String _language = 'zh';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _sectionHeader('外观'),
          SwitchListTile(
            title: const Text('深色模式'),
            subtitle: const Text('切换深色/浅色主题'),
            value: _darkMode,
            onChanged: (v) => setState(() => _darkMode = v),
          ),
          const Divider(),
          _sectionHeader('语言'),
          ListTile(
            title: const Text('语言'),
            subtitle: Text(_language == 'zh' ? '中文' : 'English'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('选择语言'),
                  children: [
                    SimpleDialogOption(
                      onPressed: () {
                        setState(() => _language = 'zh');
                        Navigator.of(ctx).pop();
                      },
                      child: Text('中文', style: TextStyle(
                        fontWeight: _language == 'zh' ? FontWeight.bold : FontWeight.normal,
                      )),
                    ),
                    SimpleDialogOption(
                      onPressed: () {
                        setState(() => _language = 'en');
                        Navigator.of(ctx).pop();
                      },
                      child: Text('English', style: TextStyle(
                        fontWeight: _language == 'en' ? FontWeight.bold : FontWeight.normal,
                      )),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(),
          _sectionHeader('画布'),
          ListTile(
            title: const Text('默认分辨率'),
            subtitle: const Text('72 DPI'),
            trailing: const Icon(Icons.chevron_right),
          ),
          const Divider(),
          _sectionHeader('关于'),
          ListTile(
            title: Text('app.name'.tr()),
            subtitle: const Text('版本 1.0.0'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        )),
    );
  }
}
