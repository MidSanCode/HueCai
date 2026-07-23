import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class AppSettings extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  String _languageCode = 'zh';

  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;

  Future<void> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/huecai_settings.json');
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _themeMode = ThemeMode.values.firstWhere(
          (e) => e.toString() == json['themeMode'],
          orElse: () => ThemeMode.system,
        );
        _languageCode = json['languageCode'] as String? ?? 'zh';
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/huecai_settings.json');
      await file.writeAsString(jsonEncode({
        'themeMode': _themeMode.toString(),
        'languageCode': _languageCode,
      }));
    } catch (_) {}
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _save();
    notifyListeners();
  }

  void setLanguageCode(String code) {
    _languageCode = code;
    _save();
    notifyListeners();
  }
}