import 'package:flutter/material.dart';

class AppSettings extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  String _languageCode = 'zh';

  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void setLanguageCode(String code) {
    _languageCode = code;
    notifyListeners();
  }
}
