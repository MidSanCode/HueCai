import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/app_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  final settings = AppSettings();
  await settings.load();

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