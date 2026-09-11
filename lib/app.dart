import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'providers/project_provider.dart';
import 'providers/app_settings.dart';
import 'screens/workspace_screen.dart';

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

class HueCaiApp extends StatelessWidget {
  const HueCaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProjectProvider()),
      ],
      child: _AppContent(),
    );
  }
}

class _AppContent extends StatefulWidget {
  @override
  State<_AppContent> createState() => _AppContentState();
}

class _AppContentState extends State<_AppContent> with WindowListener {
  static final _navKey = GlobalKey<NavigatorState>();
  bool _closeDialogOpen = false;

  @override
  void initState() {
    super.initState();
    if (_isDesktop) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (_isDesktop) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Guard against double invocation while the dialog is up.
    if (_closeDialogOpen) return;
    final pp = context.read<ProjectProvider>();
    if (!pp.hasUnsavedChanges || pp.currentProject == null) {
      await windowManager.destroy();
      return;
    }
    _closeDialogOpen = true;
    final ctx = _navKey.currentContext;
    final choice = (ctx == null)
        ? 'discard'
        : await showDialog<String>(
            context: ctx,
            barrierDismissible: false,
            builder: (dctx) => AlertDialog(
              title: Text('dialog.unsaved_title'.tr()),
              content: Text('dialog.unsaved_message'.tr()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dctx).pop('cancel'),
                  child: Text('dialog.cancel'.tr()),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dctx).pop('discard'),
                  child: Text('dialog.discard'.tr()),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dctx).pop('save'),
                  child: Text('dialog.save'.tr()),
                ),
              ],
            ),
          );
    _closeDialogOpen = false;
    if (choice == 'save') {
      await pp.saveProject();
      await windowManager.destroy();
    } else if (choice == 'discard') {
      await windowManager.destroy();
    }
    // 'cancel' / null: keep the window open.
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    return MaterialApp(
      navigatorKey: _navKey,
      title: '绘彩',
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.light,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      themeMode: settings.themeMode,
      home: const WorkspaceScreen(),
    );
  }
}
