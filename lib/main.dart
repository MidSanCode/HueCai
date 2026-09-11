import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'providers/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  final settings = AppSettings();
  await settings.load();

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(title: '绘彩'),
      () async {
        // Intercept the native close so an unsaved-changes prompt can run.
        await windowManager.setPreventClose(true);
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  runApp(
    ChangeNotifierProvider.value(
      value: settings,
      child: EasyLocalization(
        supportedLocales: const [
          Locale('zh'),
          Locale('en'),
        ],
        path: 'assets/l10n',
        fallbackLocale: const Locale('en'),
        child: const HueCaiApp(),
      ),
    ),
  );
}
