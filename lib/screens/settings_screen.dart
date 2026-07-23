import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../providers/app_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final locale = context.locale;

    return Scaffold(
      appBar: AppBar(
        title: Text('app.name'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _sectionHeader(context, '外观'),
          SwitchListTile(
            title: Text('深色模式'),
            subtitle: Text(settings.themeMode == ThemeMode.dark ? "当前: 深色" : settings.themeMode == ThemeMode.light ? "当前: 浅色" : "当前: 跟随系统"),
            value: settings.themeMode == ThemeMode.dark,
            onChanged: (v) {
              final mode = v ? ThemeMode.dark : ThemeMode.light;
              settings.setThemeMode(mode);
            },
          ),
          ListTile(
            title: Text('主题模式'),
            subtitle: Text(settings.themeMode == ThemeMode.dark
                ? '深色'
                : settings.themeMode == ThemeMode.light
                    ? '浅色'
                    : '跟随系统'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('选择主题'),
                  children: [
                    SimpleDialogOption(
                      onPressed: () {
                        settings.setThemeMode(ThemeMode.light);
                        Navigator.of(ctx).pop();
                      },
                      child: Text('浅色', style: TextStyle(
                        fontWeight: settings.themeMode == ThemeMode.light
                            ? FontWeight.bold : FontWeight.normal,
                      )),
                    ),
                    SimpleDialogOption(
                      onPressed: () {
                        settings.setThemeMode(ThemeMode.dark);
                        Navigator.of(ctx).pop();
                      },
                      child: Text('深色', style: TextStyle(
                        fontWeight: settings.themeMode == ThemeMode.dark
                            ? FontWeight.bold : FontWeight.normal,
                      )),
                    ),
                    SimpleDialogOption(
                      onPressed: () {
                        settings.setThemeMode(ThemeMode.system);
                        Navigator.of(ctx).pop();
                      },
                      child: Text('跟随系统', style: TextStyle(
                        fontWeight: settings.themeMode == ThemeMode.system
                            ? FontWeight.bold : FontWeight.normal,
                      )),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(),
          _sectionHeader(context, '语言'),
          ListTile(
            title: Text('语言'),
            subtitle: Text(locale.languageCode == 'zh' ? '中文' : 'English'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('选择语言'),
                  children: [
                    SimpleDialogOption(
                      onPressed: () {
                        context.setLocale(const Locale('zh'));
                        settings.setLanguageCode('zh');
                        Navigator.of(ctx).pop();
                      },
                      child: Text('中文', style: TextStyle(
                        fontWeight: locale.languageCode == 'zh'
                            ? FontWeight.bold : FontWeight.normal,
                      )),
                    ),
                    SimpleDialogOption(
                      onPressed: () {
                        context.setLocale(const Locale('en'));
                        settings.setLanguageCode('en');
                        Navigator.of(ctx).pop();
                      },
                      child: Text('English', style: TextStyle(
                        fontWeight: locale.languageCode == 'en'
                            ? FontWeight.bold : FontWeight.normal,
                      )),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(),
          _sectionHeader(context, '画布'),
          ListTile(
            title: Text('默认分辨率'),
            subtitle: const Text('72 DPI'),
            trailing: const Icon(Icons.chevron_right),
          ),
          const Divider(),
          _sectionHeader(context, '关于'),
          ListTile(
            title: Text('app.name'.tr()),
            subtitle: const Text('版本 1.0.0'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        )),
    );
  }
}
