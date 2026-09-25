import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'providers/app_settings.dart';
import 'services/file_association_service.dart';
import 'services/launch_file_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  final settings = AppSettings();
  await settings.load();

  // When the OS launches us as the `.hcproj` handler, the document path arrives
  // as an argument (desktop) or over a platform channel (mobile).
  await LaunchFileService.resolve(args);
  // Make sure `.hcproj` is associated with this app where that is done
  // imperatively (Windows / Linux); mobile declares it statically.
  await FileAssociationService.ensureRegistered();

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
