import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../providers/app_settings.dart';
import '../utils/logger.dart';
import '../services/config_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final locale = context.locale;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('app.name'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionCard(
            theme: theme,
            title: 'settings.appearance'.tr(),
            children: [
              ListTile(
                title: Text('settings.theme_mode'.tr()),
                subtitle: Text(settings.themeMode == ThemeMode.dark
                    ? 'settings.dark'.tr()
                    : settings.themeMode == ThemeMode.light
                        ? 'settings.light'.tr()
                        : 'settings.system'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      title: Text('settings.theme_mode'.tr()),
                      children: [
                        SimpleDialogOption(
                          onPressed: () {
                            settings.setThemeMode(ThemeMode.light);
                            Navigator.of(ctx).pop();
                          },
                          child: Text('settings.light'.tr(), style: TextStyle(
                            fontWeight: settings.themeMode == ThemeMode.light
                                ? FontWeight.bold : FontWeight.normal,
                          )),
                        ),
                        SimpleDialogOption(
                          onPressed: () {
                            settings.setThemeMode(ThemeMode.dark);
                            Navigator.of(ctx).pop();
                          },
                          child: Text('settings.dark'.tr(), style: TextStyle(
                            fontWeight: settings.themeMode == ThemeMode.dark
                                ? FontWeight.bold : FontWeight.normal,
                          )),
                        ),
                        SimpleDialogOption(
                          onPressed: () {
                            settings.setThemeMode(ThemeMode.system);
                            Navigator.of(ctx).pop();
                          },
                          child: Text('settings.system'.tr(), style: TextStyle(
                            fontWeight: settings.themeMode == ThemeMode.system
                                ? FontWeight.bold : FontWeight.normal,
                          )),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          _sectionCard(
            theme: theme,
            title: 'settings.language'.tr(),
            children: [
              ListTile(
                title: Text('settings.language'.tr()),
                subtitle: Text(locale.languageCode == 'zh' ? '中文' : 'English'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      title: Text('settings.select_language'.tr()),
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
            ],
          ),
          _sectionCard(
            theme: theme,
            title: 'settings.canvas'.tr(),
            children: [
              ListTile(
                title: Text('settings.default_dpi'.tr()),
                subtitle: const Text('72 DPI'),
                trailing: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          _sectionCard(
            theme: theme,
            title: 'settings.logs'.tr(),
            children: [
              ListTile(
                leading: const Icon(Icons.file_download),
                title: Text('settings.export_log'.tr()),
                subtitle: Text('settings.export_log_desc'.tr()),
                onTap: () async {
                  final logPath = await AppLogger().export();
                  final result = await FilePicker.platform.saveFile(
                    dialogTitle: 'settings.export_log'.tr(),
                    fileName: 'huecai_log.txt',
                    type: FileType.any,
                  );
                  if (result != null) {
                    try {
                      await File(logPath).copy(result);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('settings.export_done'.tr())),
                        );
                      }
                    } catch (_) {}
                  }
                },
              ),
            ],
          ),
          _sectionCard(
            theme: theme,
            title: 'settings.about'.tr(),
            children: [
              ListTile(
                title: Text('app.name'.tr()),
                subtitle: Text('${'settings.version'.tr()} (${ConfigService.buildVersion})'),
              ),
              ListTile(
                leading: const Icon(Icons.build),
                title: const Text('Build Number'),
                subtitle: Text(ConfigService.buildNumber),
              ),
              ListTile(
                title: Text('settings.copyright'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required ThemeData theme,
    required String title,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}
